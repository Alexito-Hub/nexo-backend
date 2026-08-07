defmodule Nexo.Db do
  @moduledoc """
  Acceso a MongoDB.

  La URI viene de configuración (`MONGODB_URI` en producción). Los índices se
  aseguran al arrancar: unicidad de docentes y tokens, TTL para que Mongo
  purgue solo los refresh tokens vencidos, y orden cronológico de auditoría.
  """
  require Logger

  @conn :mongo

  def url do
    Application.fetch_env!(:nexo, :mongodb_uri)
  end

  @doc """
  Opciones TLS para Atlas: CA del sistema operativo + verificación estricta
  del certificado con soporte de wildcard (los hosts de Atlas usan `*.mongodb.net`).
  """
  def ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  def conn, do: @conn

  def ensure_indexes_async do
    Task.start(fn -> ensure_indexes() end)
  end

  def ensure_indexes do
    create_indexes("teachers", [
      %{key: %{sigma_code: 1}, name: "sigma_code_unique", unique: true}
    ])

    create_indexes("refresh_tokens", [
      %{key: %{token_hash: 1}, name: "token_hash_unique", unique: true},
      %{key: %{teacher_id: 1}, name: "teacher_id_idx"},
      %{key: %{expires_at: 1}, name: "expires_ttl", expireAfterSeconds: 0}
    ])

    create_indexes("audit_log", [
      %{key: %{inserted_at: -1}, name: "inserted_at_idx"},
      %{key: %{actor_id: 1}, name: "actor_id_idx"}
    ])

    :ok
  rescue
    e ->
      Logger.warning("No se pudieron asegurar los índices de Mongo: #{Exception.message(e)}")
      :error
  end

  defp create_indexes(collection, indexes) do
    Mongo.create_indexes(@conn, collection, indexes)
  end

  @doc "Convierte el `_id` de un documento a string para exponerlo en la API."
  def id_to_string(%BSON.ObjectId{} = oid), do: BSON.ObjectId.encode!(oid)
  def id_to_string(other), do: to_string(other)

  @doc "Parsea un id de la API de vuelta a ObjectId. `:error` si no es válido."
  def parse_id(str) when is_binary(str) do
    {:ok, BSON.ObjectId.decode!(str)}
  rescue
    _ -> :error
  end

  def parse_id(_), do: :error

  def now, do: DateTime.utc_now(:millisecond)
end
