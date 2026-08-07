defmodule NexoWeb.SectionController do
  use NexoWeb, :controller

  alias Nexo.Teaching

  def index(conn, _params) do
    respond(conn, Teaching.list_sections(teacher(conn)), fn sections ->
      %{secciones: Enum.map(sections, &section_view/1)}
    end)
  end

  def students(conn, %{"cle_auto" => cle_auto}) do
    respond(conn, Teaching.list_students(teacher(conn), cle_auto), fn students ->
      %{estudiantes: Enum.map(students, &student_view/1)}
    end)
  end

  def grades(conn, %{"cle_auto" => cle_auto} = params) do
    unit = params["unidad"] || "1"

    respond(conn, Teaching.section_grades(teacher(conn), cle_auto, unit), fn grades ->
      %{unidad: unit, notas: Enum.map(grades, &student_view/1)}
    end)
  end

  def student_grades(conn, %{"cle_auto" => cle_auto, "codigo" => codigo} = params) do
    unit = params["unidad"] || "1"

    respond(conn, Teaching.student_grades(teacher(conn), cle_auto, codigo, unit), fn student ->
      %{unidad: unit, estudiante: student_view(student)}
    end)
  end

  defp respond(conn, {:ok, data}, view), do: json(conn, view.(data))

  defp respond(conn, {:error, :forbidden}, _view) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: "seccion_ajena",
      detail: "Solo puedes consultar las secciones que tienes asignadas."
    })
  end

  defp respond(conn, {:error, :session_expired}, _view) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: "sesion_sigma_expirada",
      detail: "Vuelve a iniciar sesión para consultar datos académicos."
    })
  end

  defp respond(conn, {:error, :not_found}, _view) do
    conn |> put_status(:not_found) |> json(%{error: "no_encontrado"})
  end

  defp respond(conn, {:error, _}, _view) do
    conn |> put_status(:service_unavailable) |> json(%{error: "sigma_no_disponible"})
  end

  defp teacher(conn), do: conn.assigns.current_teacher

  defp section_view(s) do
    %{
      id: s.id,
      codigo: s.code,
      asignatura: s.subject,
      seccion: s.section,
      periodo: s.periodo,
      matriculados: s.enrolled
    }
  end

  defp student_view(s) do
    %{
      codigo: s.code,
      nombres: s.first_name,
      apellidos: s.last_name,
      asistencia: s.attendance,
      nota: s.grade
    }
  end
end
