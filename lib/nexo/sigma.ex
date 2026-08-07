defmodule Nexo.Sigma do
  @moduledoc """
  Verificación de identidad contra SIGMA (UPLA).

  El backend NUNCA persiste las credenciales: se usan una sola vez para
  confirmar que quien se registra es un docente real de la universidad y se
  descartan. El módulo concreto se resuelve por configuración para poder
  sustituirlo en tests.
  """

  @type profile :: %{
          code: String.t(),
          first_name: String.t(),
          last_name: String.t(),
          teacher?: boolean()
        }

  @callback verify_login(usuario_id :: String.t(), password :: String.t()) ::
              {:ok, profile()} | {:error, :invalid_credentials} | {:error, :unavailable}

  def verify_login(usuario_id, password), do: impl().verify_login(usuario_id, password)

  defp impl do
    Application.get_env(:nexo, :sigma_client, Nexo.Sigma.Client)
  end
end
