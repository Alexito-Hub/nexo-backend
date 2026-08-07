defmodule Nexo.Audit do
  @moduledoc """
  Registro de auditoría (colección `audit_log`): toda acción sensible — login,
  aprobación, lectura de datos de un alumno — queda con actor, acción,
  objetivo, IP y timestamp. Es requisito de la Ley 29733 poder demostrar
  quién accedió a qué.
  """
  alias Nexo.Db

  @collection "audit_log"

  def log(action, attrs \\ %{}) do
    doc =
      attrs
      |> Map.new()
      |> Map.merge(%{action: to_string(action), inserted_at: Db.now()})

    Mongo.insert_one(Db.conn(), @collection, doc)
  end

  def recent(limit \\ 100) do
    Db.conn()
    |> Mongo.find(@collection, %{}, sort: %{inserted_at: -1}, limit: limit)
    |> Enum.to_list()
  end
end
