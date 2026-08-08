defmodule Mix.Tasks.Nexo.Seed do
  @shortdoc "Carga datos de estudiantes en MongoDB desde un archivo JSON"

  @moduledoc """
  Puebla la base con datos de estudiantes para el piloto.

      mix nexo.seed                       # réplicas de priv/seed/replicas.json
      mix nexo.seed ruta/semilla.json     # un archivo concreto

  El archivo puede contener un objeto (un estudiante) o una lista. Cada
  estudiante se guarda con su consentimiento ya otorgado —son datos de prueba
  o del propio autor— y sus módulos cifrados igual que en producción, para que
  el banco de pruebas se comporte como el sistema real.

  Los datos personales reales **no se versionan**: se cargan desde un archivo
  local y viven solo en la base.
  """
  use Mix.Task

  alias Nexo.{Consents, Db, Students}

  @default "priv/seed/replicas.json"

  @impl true
  def run(args) do
    Application.ensure_all_started(:nexo)
    ruta = List.first(args) || @default

    unless File.exists?(ruta) do
      Mix.raise("No existe el archivo #{ruta}")
    end

    Db.ensure_indexes()

    ruta
    |> File.read!()
    |> Jason.decode!()
    |> List.wrap()
    |> Enum.each(&cargar/1)

    Mix.shell().info("Listo. Base: #{Db.database_name()}")
  end

  defp cargar(%{"codigo" => codigo} = est) when is_binary(codigo) and codigo != "" do
    {:ok, _} =
      Students.upsert_from_sigma(%{
        code: codigo,
        first_name: est["nombres"] || "",
        last_name: est["apellidos"] || ""
      })

    modulos = est["modulos"] || %{}
    nombres = modulos |> Map.keys() |> Enum.filter(&(&1 in Consents.modules()))

    {:ok, _} = Consents.grant(codigo, nombres, terms_version: "seed")

    for nombre <- nombres do
      {:ok, :saved} = Consents.put_snapshot(codigo, nombre, modulos[nombre])
    end

    Mix.shell().info("  #{codigo}: #{Enum.join(nombres, ", ")}")
  end

  defp cargar(otro) do
    Mix.shell().error("  Registro sin código, omitido: #{inspect(otro, limit: 3)}")
  end
end
