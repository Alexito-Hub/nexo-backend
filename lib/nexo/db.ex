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
  Opciones de conexión. Atlas (`mongodb+srv://`) exige TLS con verificación
  estricta del certificado; un MongoDB local de pruebas va en claro, así que
  las opciones TLS solo se añaden cuando hacen falta.
  """
  def connection_opts do
    base = [name: @conn, url: url(), pool_size: pool_size()]
    if tls?(url()), do: base ++ [ssl_opts: ssl_opts()], else: base
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

  defp tls?(url) do
    String.starts_with?(url, "mongodb+srv://") or url =~ "tls=true" or url =~ "ssl=true"
  end

  defp pool_size, do: Application.get_env(:nexo, :mongodb_pool_size, 5)

  def conn, do: @conn

  @doc "Nombre de la base de datos según la URI configurada."
  def database_name do
    url()
    |> URI.parse()
    |> Map.get(:path)
    |> to_string()
    |> String.trim_leading("/")
    |> case do
      "" -> "(sin nombre en la URI)"
      name -> name
    end
  end

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

    create_indexes("teacher_sections", [
      %{key: %{teacher_id: 1, cle_auto: 1}, name: "teacher_section_unique", unique: true}
    ])

    create_indexes("students", [
      %{key: %{code: 1}, name: "code_unique", unique: true}
    ])

    # Un consentimiento vigente por estudiante y ámbito; el histórico de
    # revocaciones se conserva, por eso el índice no es único.
    create_indexes("consents", [
      %{key: %{student_code: 1, scope: 1}, name: "student_scope_idx"},
      %{key: %{granted_at: -1}, name: "granted_at_idx"}
    ])

    create_indexes("student_snapshots", [
      %{key: %{student_code: 1, module: 1}, name: "student_module_unique", unique: true}
    ])

    create_indexes("directory_access", [
      %{key: %{code: 1}, name: "code_unique", unique: true},
      %{key: %{status: 1}, name: "status_idx"}
    ])

    # `terms` es multiclave: sostiene la búsqueda por prefijo sin recorrer la
    # colección. El resto acompaña al orden y a los filtros de la lista.
    create_indexes("directory_students", [
      %{key: %{code: 1}, name: "code_unique", unique: true},
      %{key: %{terms: 1}, name: "terms_idx"},
      %{key: %{last_name: 1, first_name: 1}, name: "name_idx"},
      %{key: %{school: 1, cycle: 1}, name: "school_cycle_idx"}
    ])

    create_indexes("guardians", [
      %{key: %{dni: 1}, name: "dni_unique", unique: true},
      %{key: %{students: 1}, name: "students_idx"}
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
