defmodule NexoWeb.Router do
  use NexoWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :teacher_auth do
    plug NexoWeb.AuthPlug
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
    post "/auth/refresh", AuthController, :refresh
  end

  scope "/api/v1/teacher", NexoWeb do
    pipe_through [:api, :teacher_auth]

    get "/me", TeacherController, :me

    # Fase 2 (requiere allowlist activa): secciones, alumnos, notas.
    scope "/" do
      pipe_through :teacher_authorized
      # get "/sections", SectionController, :index
      # get "/students/:codigo/grades", StudentDataController, :grades
    end
  end

  scope "/api/v1/admin", NexoWeb do
    pipe_through [:api, :admin]

    get "/teachers", AdminController, :list_teachers
    put "/teachers/:id/status", AdminController, :set_teacher_status
    get "/audit", AdminController, :audit
  end
end
