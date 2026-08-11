defmodule NexoWeb.Router do
  use NexoWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :teacher_auth do
    plug NexoWeb.AuthPlug
  end

  pipeline :student_auth do
    plug NexoWeb.StudentAuthPlug
  end

  pipeline :teacher_authorized do
    plug NexoWeb.RequireAuthorizedPlug
  end

  pipeline :actor_auth do
    plug NexoWeb.ActorPlug
  end

  pipeline :guardian_auth do
    plug NexoWeb.GuardianAuthPlug
  end

  pipeline :directory_access do
    plug NexoWeb.RequireDirectoryPlug
  end

  pipeline :directory_admin do
    plug NexoWeb.RequireDirectoryPlug, [:admin]
  end

  pipeline :admin do
    plug NexoWeb.AdminPlug
  end

  scope "/", NexoWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/privacidad", LegalController, :privacy
    get "/privacy", LegalController, :privacy
  end

  scope "/api/v1", NexoWeb do
    pipe_through :api

    post "/auth/teacher/login", AuthController, :teacher_login
    post "/auth/student/login", AuthController, :student_login
    post "/auth/refresh", AuthController, :refresh
  end

  # Lado estudiante: gestiona su consentimiento y sube sus propios datos.
  scope "/api/v1/student", NexoWeb do
    pipe_through [:api, :student_auth]

    get "/consent", ConsentController, :show
    put "/consent", ConsentController, :update
    delete "/consent", ConsentController, :revoke
    get "/consent/history", ConsentController, :history
    put "/snapshots/:modulo", ConsentController, :put_snapshot
  end

  scope "/api/v1/teacher", NexoWeb do
    pipe_through [:api, :teacher_auth]

    get "/me", TeacherController, :me

    # Datos académicos: exigen allowlist activa y quedan acotados a las
    # secciones del propio docente (ver `Nexo.Teaching`).
    scope "/" do
      pipe_through :teacher_authorized

      get "/sections", SectionController, :index
      get "/sections/:cle_auto/students", SectionController, :students
      get "/sections/:cle_auto/grades", SectionController, :grades
      get "/sections/:cle_auto/students/:codigo/grades", SectionController, :student_grades

      # Datos que el estudiante compartió voluntariamente: sin consentimiento
      # vigente no existen para el docente.
      get "/sections/:cle_auto/students/:codigo/shared/:modulo",
          SectionController,
          :student_snapshot
    end
  end

  # Directorio de estudiantes: apartado propio, abierto a docentes y a
  # estudiantes por igual. Lo que decide no es el tipo de cuenta sino el
  # acceso concedido (ver `Nexo.DirectoryAccess`).
  scope "/api/v1/directory", NexoWeb do
    pipe_through [:api, :actor_auth]

    # Única ruta que no exige acceso: sirve para saber si se tiene.
    get "/access", DirectoryController, :access

    scope "/" do
      pipe_through :directory_access

      get "/students", DirectoryController, :index
      get "/students/:codigo", DirectoryController, :show
      get "/schools", DirectoryController, :schools
    end

    # Repartir el acceso es cosa de los administradores del sistema.
    scope "/" do
      pipe_through :directory_admin

      get "/grants", DirectoryController, :grants
      put "/grants/:codigo", DirectoryController, :set_grant

      # Apoderados: quién puede ver a qué estudiante con DNI + PIN.
      get "/guardians", DirectoryController, :guardians
      put "/guardians/:dni", DirectoryController, :set_guardian
    end
  end

  # Acceso de apoderados: sin cuenta de la UPLA, solo la ficha de sus hijos.
  scope "/api/v1/guardian", NexoWeb do
    pipe_through :api

    post "/login", GuardianController, :login
  end

  scope "/api/v1/guardian", NexoWeb do
    pipe_through [:api, :guardian_auth]

    get "/students", GuardianController, :students
    get "/students/:codigo", GuardianController, :show
  end

  scope "/api/v1/admin", NexoWeb do
    pipe_through [:api, :admin]

    get "/teachers", AdminController, :list_teachers
    put "/teachers/:id/status", AdminController, :set_teacher_status
    get "/audit", AdminController, :audit
  end
end
