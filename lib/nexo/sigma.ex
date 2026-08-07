defmodule Nexo.Sigma do
  @moduledoc """
  Acceso a SIGMA (UPLA).

  El backend NUNCA persiste la contraseña: se usa una sola vez para confirmar
  que quien se registra es un docente real y se descarta. De ese login se
  conserva el *token* de sesión de SIGMA — cifrado (ver `Nexo.Vault`) — que es
  lo que permite consultar secciones y notas en nombre del docente. Cuando ese
  token caduca, el docente vuelve a iniciar sesión.

  El módulo concreto se resuelve por configuración para sustituirlo en tests.
  """

  @type profile :: %{
          code: String.t(),
          first_name: String.t(),
          last_name: String.t(),
          teacher?: boolean(),
          token: String.t() | nil
        }

  @type section :: %{
          id: String.t(),
          code: String.t(),
          subject: String.t(),
          section: String.t(),
          periodo: String.t(),
          enrolled: integer() | nil
        }

  @type student :: %{
          code: String.t(),
          first_name: String.t(),
          last_name: String.t(),
          attendance: String.t() | nil,
          grade: String.t() | nil
        }

  @type error :: :invalid_credentials | :unavailable | :session_expired

  @callback verify_login(usuario_id :: String.t(), password :: String.t()) ::
              {:ok, profile()} | {:error, error()}

  @callback list_sections(token :: String.t()) :: {:ok, [section()]} | {:error, error()}

  @callback list_section_students(token :: String.t(), cle_auto :: String.t()) ::
              {:ok, [student()]} | {:error, error()}

  @callback section_grades(token :: String.t(), cle_auto :: String.t(), unit :: String.t()) ::
              {:ok, [student()]} | {:error, error()}

  def verify_login(usuario_id, password), do: impl().verify_login(usuario_id, password)
  def list_sections(token), do: impl().list_sections(token)
  def list_section_students(token, cle_auto), do: impl().list_section_students(token, cle_auto)
  def section_grades(token, cle_auto, unit), do: impl().section_grades(token, cle_auto, unit)

  defp impl do
    Application.get_env(:nexo, :sigma_client, Nexo.Sigma.Client)
  end
end
