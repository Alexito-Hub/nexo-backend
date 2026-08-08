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

  pipeline :admin do
    plug NexoWeb.AdminPlug
  end

  scope "/", NexoWeb do
    pipe_through :api

    get "/health", HealthController, :show
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

  scope "/api/v1/admin", NexoWeb do
    pipe_through [:api, :admin]

    get "/teachers", AdminController, :list_teachers
    put "/teachers/:id/status", AdminController, :set_teacher_status
    get "/audit", AdminController, :audit
  end
end
