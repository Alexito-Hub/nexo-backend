defmodule Mix.Tasks.Nexo.Directory do
  @shortdoc "Carga el directorio de estudiantes del prototipo"

  @moduledoc """
  Llena `directory_students` con datos de prototipo.

      mix nexo.directory              # 120 estudiantes
      mix nexo.directory 300          # la cantidad que quieras
      mix nexo.directory 120 --seed 7 # otra semilla, otro directorio

  Los estudiantes son inventados pero tienen la forma exacta de SIGMA (ver
  `Nexo.Directory.Prototype`). La tarea **reemplaza** el contenido anterior:
  el directorio es un espejo, no un histórico.

  Cuando haya permiso para leer la Intranet, esta tarea deja de usarse.
  """
  use Mix.Task

  alias Nexo.{Db, Directory, DirectoryAccess}
  alias Nexo.Directory.Prototype

  @impl true
  def run(args) do
    Application.ensure_all_started(:nexo)

    {opts, rest, _} = OptionParser.parse(args, strict: [seed: :integer])
    count = rest |> List.first() |> parse_count()
    seed = Keyword.get(opts, :seed, 20_260_809)

    Db.ensure_indexes()

    students = Prototype.generate(count, seed)
    :ok = Directory.replace_all(students)

    Mix.shell().info(
      "Directorio cargado: #{Directory.count()} estudiantes en #{Db.database_name()}."
    )

    Mix.shell().info("Escuelas: #{Enum.join(Directory.schools(), ", ")}")

    case DirectoryAccess.system_admins() do
      [] ->
        Mix.shell().error("""
        Aviso: SYSTEM_ADMINS está vacío, así que nadie puede entrar todavía.
        Añade tu código o DNI al .env para poder repartir accesos.
        """)

      admins ->
        Mix.shell().info("Administradores del sistema: #{Enum.join(admins, ", ")}")
    end
  end

  defp parse_count(nil), do: 120

  defp parse_count(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> Mix.raise("Cantidad inválida: #{value}")
    end
  end
end
