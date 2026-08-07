defmodule Nexo.Accounts do
  @moduledoc """
  Docentes y su estado en la allowlist (colección `teachers`).

  Ser docente UPLA no basta: el registro nace `"pendiente"` y solo un admin lo
  pasa a `"autorizado"`. El scoping por sección/alumno se valida en cada
  consulta (fase 2), no aquí.
  """
  alias Nexo.Db

  @collection "teachers"
  @statuses ~w(pendiente autorizado suspendido)

  def valid_statuses, do: @statuses

  def get_teacher(id) when is_binary(id) do
    case Db.parse_id(id) do
      {:ok, oid} -> Mongo.find_one(Db.conn(), @collection, %{_id: oid})
      :error -> nil
    end
  end

  def get_teacher_by_code(sigma_code) do
    Mongo.find_one(Db.conn(), @collection, %{sigma_code: sigma_code})
  end

  def list_teachers do
    Db.conn()
    |> Mongo.find(@collection, %{}, sort: %{inserted_at: -1})
    |> Enum.to_list()
  end

  @doc """
  Login docente: primer acceso registra al docente como `"pendiente"`; accesos
  siguientes refrescan el nombre si SIGMA lo trae más completo.
  """
  def upsert_teacher_from_sigma(%{code: code} = profile) do
    now = Db.now()

    case get_teacher_by_code(code) do
      nil ->
        doc = %{
          "sigma_code" => code,
          "first_name" => profile.first_name,
          "last_name" => profile.last_name,
          "status" => "pendiente",
          "authorized_at" => nil,
          "authorized_by" => nil,
          "inserted_at" => now,
          "updated_at" => now
        }

        with {:ok, %{inserted_id: id}} <- Mongo.insert_one(Db.conn(), @collection, doc) do
          {:ok, Map.put(doc, "_id", id)}
        end

      %{} = teacher ->
        updates = %{
          "first_name" => presence(profile.first_name) || teacher["first_name"],
          "last_name" => presence(profile.last_name) || teacher["last_name"],
          "updated_at" => now
        }

        apply_updates(teacher, updates)
    end
  end

  def set_teacher_status(%{} = teacher, status, authorized_by) when status in @statuses do
    apply_updates(teacher, %{
      "status" => status,
      "authorized_by" => authorized_by,
      "authorized_at" => if(status == "autorizado", do: Db.now(), else: teacher["authorized_at"]),
      "updated_at" => Db.now()
    })
  end

  def set_teacher_status(_teacher, _status, _by), do: {:error, :invalid_status}

  @doc """
  Guarda el token de sesión de SIGMA obtenido en el login, cifrado en reposo.
  No es una credencial (la contraseña nunca se guarda), pero permite consultar
  en nombre del docente, así que no vive en claro.
  """
  def put_sigma_token(%{} = teacher, token) when is_binary(token) and token != "" do
    apply_updates(teacher, %{
      "sigma_token" => %BSON.Binary{binary: Nexo.Vault.encrypt(token)},
      "sigma_token_at" => Db.now(),
      "updated_at" => Db.now()
    })
  end

  def put_sigma_token(teacher, _token), do: {:ok, teacher}

  @doc "Token de SIGMA descifrado, o `:error` si no hay o no se puede leer."
  def sigma_token(%{"sigma_token" => %BSON.Binary{binary: data}}), do: Nexo.Vault.decrypt(data)
  def sigma_token(_), do: :error

  @doc "Olvida el token de SIGMA (caducó o el docente cerró sesión)."
  def clear_sigma_token(%{"_id" => id}) do
    Mongo.update_one(Db.conn(), @collection, %{_id: id}, %{
      "$unset" => %{"sigma_token" => "", "sigma_token_at" => ""}
    })
  end

  defp apply_updates(%{"_id" => id} = teacher, updates) do
    with {:ok, _} <-
           Mongo.update_one(Db.conn(), @collection, %{_id: id}, %{"$set" => updates}) do
      {:ok, Map.merge(teacher, updates)}
    end
  end

  defp presence(nil), do: nil
  defp presence(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
end
