defmodule Nexo.Students do
  @moduledoc """
  Registro mínimo de estudiantes (colección `students`).

  A propósito guarda lo imprescindible para identificar a quien consiente:
  código y nombre. Todo lo demás —notas, pagos, horario— vive en
  `Nexo.Consents` y solo si el estudiante lo autorizó.
  """
  alias Nexo.Db

  @collection "students"

  def get(id) when is_binary(id) do
    case Db.parse_id(id) do
      {:ok, oid} -> Mongo.find_one(Db.conn(), @collection, %{_id: oid})
      :error -> nil
    end
  end

  def get_by_code(code), do: Mongo.find_one(Db.conn(), @collection, %{code: code})

  def upsert_from_sigma(%{code: code} = profile) do
    now = Db.now()

    case get_by_code(code) do
      nil ->
        doc = %{
          "code" => code,
          "first_name" => profile.first_name,
          "last_name" => profile.last_name,
          "inserted_at" => now,
          "updated_at" => now
        }

        with {:ok, %{inserted_id: id}} <- Mongo.insert_one(Db.conn(), @collection, doc) do
          {:ok, Map.put(doc, "_id", id)}
        end

      %{"_id" => id} = student ->
        updates = %{
          "first_name" => profile.first_name,
          "last_name" => profile.last_name,
          "updated_at" => now
        }

        with {:ok, _} <-
               Mongo.update_one(Db.conn(), @collection, %{_id: id}, %{"$set" => updates}) do
          {:ok, Map.merge(student, updates)}
        end
    end
  end
end
