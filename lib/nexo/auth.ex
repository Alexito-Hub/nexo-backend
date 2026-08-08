defmodule Nexo.Auth do
  @moduledoc """
  Tokens propios del backend, tanto para docentes como para estudiantes.

  - Acceso: `Phoenix.Token` firmado, vida corta (15 min). Lleva el tipo de
    sujeto y su id; el estado (allowlist, consentimiento) se relee de la base
    en cada petición, así una suspensión o una revocación surten efecto
    inmediato aunque el token siga vigente.
  - Refresh: token opaco de 30 días en la colección `refresh_tokens`; solo se
    guarda su hash SHA-256, es revocable y rota en cada uso (rotación atómica
    vía `find_one_and_update`). Un índice TTL purga los vencidos.
  """
  alias Nexo.Db

  @collection "refresh_tokens"
  @access_ttl 15 * 60
  @refresh_ttl_days 30
  @salt "nexo access v2"

  @type subject :: :teacher | :student

  def access_ttl_seconds, do: @access_ttl

  @spec sign_access_token(subject(), String.t()) :: String.t()
  def sign_access_token(type, id) when type in [:teacher, :student] do
    Phoenix.Token.sign(NexoWeb.Endpoint, @salt, %{type: type, id: id})
  end

  @spec verify_access_token(String.t()) ::
          {:ok, %{type: subject(), id: String.t()}} | {:error, :invalid_token}
  def verify_access_token(token) when is_binary(token) do
    case Phoenix.Token.verify(NexoWeb.Endpoint, @salt, token, max_age: @access_ttl) do
      {:ok, %{type: type, id: id}} -> {:ok, %{type: type, id: id}}
      _ -> {:error, :invalid_token}
    end
  end

  def verify_access_token(_), do: {:error, :invalid_token}

  def issue_refresh_token(type, id) when type in [:teacher, :student] do
    raw = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, _} =
      Mongo.insert_one(Db.conn(), @collection, %{
        subject_type: to_string(type),
        subject_id: id,
        token_hash: hash(raw),
        expires_at: DateTime.add(Db.now(), @refresh_ttl_days, :day),
        revoked_at: nil,
        inserted_at: Db.now()
      })

    raw
  end

  @doc "Valida un refresh token y lo rota: el usado queda revocado atómicamente."
  def exchange_refresh_token(raw) when is_binary(raw) do
    now = Db.now()

    result =
      Mongo.find_one_and_update(
        Db.conn(),
        @collection,
        %{token_hash: hash(raw), revoked_at: nil, expires_at: %{"$gt" => now}},
        %{"$set" => %{revoked_at: now}}
      )

    case result do
      {:ok,
       %Mongo.FindAndModifyResult{
         value: %{"subject_type" => subject_type, "subject_id" => id}
       }} ->
        type = String.to_existing_atom(subject_type)
        {:ok, %{type: type, id: id, new_refresh: issue_refresh_token(type, id)}}

      _ ->
        {:error, :invalid_token}
    end
  end

  def exchange_refresh_token(_), do: {:error, :invalid_token}

  @doc "Corta todas las sesiones de un sujeto (suspensión, cierre de sesión)."
  def revoke_all(type, id) do
    Mongo.update_many(
      Db.conn(),
      @collection,
      %{subject_type: to_string(type), subject_id: id, revoked_at: nil},
      %{"$set" => %{revoked_at: Db.now()}}
    )
  end

  defp hash(raw), do: Base.encode16(:crypto.hash(:sha256, raw), case: :lower)
end
