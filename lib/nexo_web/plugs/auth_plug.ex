defmodule NexoWeb.AuthPlug do
  @moduledoc """
  Exige `Authorization: Bearer <access token>` de un **docente** y lo carga
  desde la base en cada petición: un docente suspendido pierde acceso al
  instante aunque su token siga vigente.
  """
  import Plug.Conn
  alias Nexo.{Accounts, Auth}

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{type: :teacher, id: id}} <- Auth.verify_access_token(token),
         %{} = teacher <- Accounts.get_teacher(id) do
      assign(conn, :current_teacher, teacher)
    else
      _ -> NexoWeb.AuthPlug.unauthorized(conn)
    end
  end

  def unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "no_autenticado"})
    |> halt()
  end
end

defmodule NexoWeb.StudentAuthPlug do
  @moduledoc "Igual que `NexoWeb.AuthPlug` pero para tokens de estudiante."
  import Plug.Conn
  alias Nexo.{Auth, Students}

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{type: :student, id: id}} <- Auth.verify_access_token(token),
         %{} = student <- Students.get(id) do
      assign(conn, :current_student, student)
    else
      _ -> NexoWeb.AuthPlug.unauthorized(conn)
    end
  end
end

defmodule NexoWeb.RequireAuthorizedPlug do
  @moduledoc "Solo docentes con allowlist activa (`status: \"autorizado\"`)."
  import Plug.Conn

  def init(opts), do: opts

  def call(%{assigns: %{current_teacher: %{"status" => "autorizado"}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(%{
      error: "no_autorizado",
      detail: "Tu acceso aún no fue aprobado."
    })
    |> halt()
  end
end

defmodule NexoWeb.AdminPlug do
  @moduledoc """
  Autenticación de administración para el piloto: cabecera `x-admin-key`
  comparada en tiempo constante contra la clave configurada. Si no hay clave
  configurada, el área admin queda cerrada.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    configured = Application.get_env(:nexo, :admin_api_key)

    with true <- is_binary(configured) and configured != "",
         [provided] <- get_req_header(conn, "x-admin-key"),
         true <- Plug.Crypto.secure_compare(provided, configured) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "admin_no_autorizado"})
        |> halt()
    end
  end
end
