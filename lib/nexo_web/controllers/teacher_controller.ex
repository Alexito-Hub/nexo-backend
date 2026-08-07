defmodule NexoWeb.TeacherController do
  use NexoWeb, :controller

  alias NexoWeb.AuthController

  @doc "Estado del docente autenticado (la app decide qué mostrar según `estado`)."
  def me(conn, _params) do
    json(conn, %{teacher: AuthController.teacher_view(conn.assigns.current_teacher)})
  end
end
