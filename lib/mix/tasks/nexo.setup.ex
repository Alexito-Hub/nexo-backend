defmodule Mix.Tasks.Nexo.Setup do
  @shortdoc "Crea las colecciones e índices en MongoDB"

  @moduledoc """
  Inicializa la base de datos configurada en `MONGODB_URI`.

  MongoDB crea las bases y colecciones de forma perezosa, con la primera
  escritura: hasta que la aplicación no guarda algo, la base ni siquiera
  aparece en Atlas. Esta tarea las crea por adelantado con sus índices, para
  que el estado de la base sea explícito y verificable desde el primer día.

      mix nexo.setup
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Application.ensure_all_started(:nexo)

    case Nexo.Db.ensure_indexes() do
      :ok ->
        Mix.shell().info("Colecciones e índices listos en #{Nexo.Db.database_name()}.")

      :error ->
        Mix.raise("No se pudieron crear los índices. Revisa MONGODB_URI y el acceso al cluster.")
    end
  end
end
