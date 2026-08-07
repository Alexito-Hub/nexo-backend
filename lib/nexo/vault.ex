defmodule Nexo.Vault do
  @moduledoc """
  Cifrado simétrico para los pocos datos sensibles que sí deben persistir.

  Hoy protege el token de sesión de SIGMA: no es una credencial (la contraseña
  nunca se guarda), pero permite consultar en nombre del docente, así que en la
  base solo vive cifrado. AES-256-GCM con clave derivada de `SECRET_KEY_BASE`:
  rotar ese secreto invalida los tokens guardados, que es el comportamiento
  deseado.
  """

  @aad "nexo.vault.v1"

  @spec encrypt(String.t()) :: binary()
  def encrypt(plaintext) when is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plaintext, @aad, true)

    iv <> tag <> ciphertext
  end

  @spec decrypt(binary()) :: {:ok, String.t()} | :error
  def decrypt(<<iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def decrypt(_), do: :error

  defp key do
    secret = Application.fetch_env!(:nexo, NexoWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, "nexo.vault.key|" <> secret)
  end
end
