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

defmodule NexoWeb.GuardianAuthPlug do
  @moduledoc """
  Exige un token de apoderado y lo recarga en cada petición: revocar el
  vínculo corta el acceso al instante, sin esperar a que caduque el token.
  """
  import Plug.Conn
  alias Nexo.{Auth, Guardians}

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{type: :guardian, id: id}} <- Auth.verify_access_token(token),
         %{} = guardian <- Guardians.get(id),
         true <- Guardians.active?(guardian) do
      assign(conn, :current_guardian, guardian)
    else
      _ -> NexoWeb.AuthPlug.unauthorized(conn)
    end
  end
end

defmodule NexoWeb.ActorPlug do
  @moduledoc """
  Identifica a quien pide, sea docente o estudiante.

  El directorio no distingue por tipo de cuenta —lo que decide es el acceso
  concedido, no si eres alumno o profesor—, así que necesita un plug que
  acepte ambos tokens y deje un actor uniforme en `:current_actor`.
  """
  import Plug.Conn
  alias Nexo.{Accounts, Auth, Students}

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{type: type, id: id}} <- Auth.verify_access_token(token),
         %{} = actor <- load(type, id) do
      assign(conn, :current_actor, actor)
    else
      _ -> NexoWeb.AuthPlug.unauthorized(conn)
    end
  end

  defp load(:teacher, id) do
    case Accounts.get_teacher(id) do
      nil ->
        nil

      teacher ->
        %{
          type: :teacher,
          code: teacher["sigma_code"],
          first_name: teacher["first_name"],
          last_name: teacher["last_name"]
        }
    end
  end

  defp load(:student, id) do
    case Students.get(id) do
      nil ->
        nil

      student ->
        %{
          type: :student,
          code: student["code"],
          first_name: student["first_name"],
          last_name: student["last_name"]
        }
    end
  end

  # Un apoderado no es un actor del directorio: su token no abre esta puerta,
  # y se le responde 401 como a cualquier desconocido.
  defp load(_type, _id), do: nil
end

defmodule NexoWeb.RequireDirectoryPlug do
  @moduledoc """
  Exige acceso vigente al directorio de estudiantes. Se relee en cada
  petición: revocar el acceso surte efecto al instante, sin esperar a que
  caduque el token.
  """
  import Plug.Conn
  alias Nexo.DirectoryAccess

  def init(opts), do: opts

  def call(%{assigns: %{current_actor: %{code: code}}} = conn, opts) do
    case DirectoryAccess.role(code) do
      nil ->
        denied(conn)

      :autorizado when opts == [:admin] ->
        denied(conn, "solo_administradores", "Esta acción es de administradores.")

      role ->
        assign(conn, :directory_role, role)
    end
  end

  def call(conn, _opts), do: NexoWeb.AuthPlug.unauthorized(conn)

  defp denied(
         conn,
         error \\ "sin_acceso_directorio",
         detail \\ "Tu cuenta no tiene acceso al directorio de estudiantes."
       ) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(%{error: error, detail: detail})
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
