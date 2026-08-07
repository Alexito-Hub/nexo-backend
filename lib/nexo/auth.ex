defmodule Nexo.Auth do
  @moduledoc """
  Tokens propios del backend.

  - Acceso: `Phoenix.Token` firmado, vida corta (15 min). Lleva el id del
    docente; el estado (allowlist) se relee de la BD en cada request, así una
    suspensión surte efecto inmediato.
  - Refresh: token opaco de 30 días en la colección `refresh_tokens`; solo se
    guarda su hash SHA-256, es revocable y rota en cada uso (rotación atómica
    vía `find_one_and_update`). Un índice TTL purga los vencidos.
  """
  alias Nexo.Db

  @collection "refresh_tokens"
  @access_ttl 15 * 60
  @refresh_ttl_days 30
  @salt "teacher access v1"

  def access_ttl_seconds, do: @access_ttl

  def sign_access_token(teacher_id) do
    Phoenix.Token.sign(NexoWeb.Endpoint, @salt, %{teacher_id: teacher_id})
  end

  def verify_access_token(token) do
    case Phoenix.Token.verify(NexoWeb.Endpoint, @salt, token, max_age: @access_ttl) do
      {:ok, %{teacher_id: id}} -> {:ok, id}
      _ -> {:error, :invalid_token}
    end
  end

  def issue_refresh_token(teacher_id) do
    raw = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, _} =
      Mongo.insert_one(Db.conn(), @collection, %{
        teacher_id: teacher_id,
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
      {:ok, %Mongo.FindAndModifyResult{value: %{"teacher_id" => teacher_id}}} ->
        {:ok, %{teacher_id: teacher_id, new_refresh: issue_refresh_token(teacher_id)}}

      _ ->
        {:error, :invalid_token}
    end
  end

  def exchange_refresh_token(_), do: {:error, :invalid_token}

  def revoke_all_for_teacher(teacher_id) do
    Mongo.update_many(
      Db.conn(),
      @collection,
      %{teacher_id: teacher_id, revoked_at: nil},
      %{"$set" => %{revoked_at: Db.now()}}
    )
  end

  defp hash(raw), do: Base.encode16(:crypto.hash(:sha256, raw), case: :lower)
end
