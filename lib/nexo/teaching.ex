defmodule Nexo.Teaching do
  @moduledoc """
  Datos académicos que un docente autorizado puede consultar.

  Aquí vive la garantía central del proyecto: **un docente solo alcanza sus
  propias secciones**. SIGMA ya aplica ese límite, pero no nos fiamos de eso:
  cada consulta se valida contra la lista de secciones del propio docente antes
  de salir a la red, y queda auditada. Si la sección no aparece en su lista, la
  lista se refresca una vez (puede ser una asignación nueva) y, si sigue sin
  aparecer, la petición se rechaza.
  """
  alias Nexo.{Accounts, Audit, Db, Sigma}

  @collection "teacher_sections"

  @doc "Secciones del docente. Refresca desde SIGMA y las cachea para el scoping."
  def list_sections(teacher) do
    with {:ok, token} <- token_for(teacher),
         {:ok, sections} <- handle(teacher, Sigma.list_sections(token)) do
      cache_sections(teacher, sections)
      {:ok, sections}
    end
  end

  @doc "Estudiantes de una sección del docente."
  def list_students(teacher, cle_auto) do
    with {:ok, token} <- token_for(teacher),
         :ok <- authorize_section(teacher, cle_auto),
         {:ok, students} <- handle(teacher, Sigma.list_section_students(token, cle_auto)) do
      audit(teacher, :section_students_read, %{section: cle_auto, count: length(students)})
      {:ok, students}
    end
  end

  @doc """
  Notas de una unidad para la sección indicada. `unit` es el
  `tipoCalificacion` de SIGMA ("1" o "2").
  """
  def section_grades(teacher, cle_auto, unit) do
    with {:ok, token} <- token_for(teacher),
         :ok <- authorize_section(teacher, cle_auto),
         {:ok, grades} <- handle(teacher, Sigma.section_grades(token, cle_auto, unit)) do
      audit(teacher, :section_grades_read, %{section: cle_auto, unidad: unit})
      {:ok, grades}
    end
  end

  @doc """
  Notas de un estudiante concreto dentro de una sección del docente.
  Doble validación: la sección debe ser suya y el estudiante debe pertenecer a
  esa sección. Se audita nominalmente porque identifica a una persona.
  """
  def student_grades(teacher, cle_auto, student_code, unit) do
    with {:ok, token} <- token_for(teacher),
         :ok <- authorize_section(teacher, cle_auto),
         {:ok, grades} <- handle(teacher, Sigma.section_grades(token, cle_auto, unit)) do
      case Enum.find(grades, &(&1.code == student_code)) do
        nil ->
          {:error, :not_found}

        student ->
          audit(teacher, :student_grades_read, %{section: cle_auto, unidad: unit}, student_code)
          {:ok, student}
      end
    end
  end

  # --- Scoping -------------------------------------------------------------

  defp authorize_section(teacher, cle_auto) do
    if cached_section?(teacher, cle_auto) do
      :ok
    else
      # Puede ser una asignación reciente: refrescamos una vez antes de negar.
      case list_sections(teacher) do
        {:ok, sections} ->
          if Enum.any?(sections, &(&1.id == cle_auto)) do
            :ok
          else
            audit(teacher, :section_access_denied, %{section: cle_auto})
            {:error, :forbidden}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp cached_section?(teacher, cle_auto) do
    Mongo.find_one(Db.conn(), @collection, %{
      teacher_id: teacher_id(teacher),
      cle_auto: cle_auto
    }) != nil
  end

  # Se actualiza sección por sección (son pocas) en vez de borrar y reinsertar:
  # así dos peticiones simultáneas nunca dejan al docente sin secciones a mitad
  # de camino ni chocan contra el índice único.
  defp cache_sections(teacher, sections) do
    id = teacher_id(teacher)
    now = Db.now()

    for s <- sections do
      Mongo.update_one(
        Db.conn(),
        @collection,
        %{teacher_id: id, cle_auto: s.id},
        %{
          "$set" => %{
            "subject" => s.subject,
            "section" => s.section,
            "periodo" => s.periodo,
            "synced_at" => now
          }
        },
        upsert: true
      )
    end

    # Las secciones que ya no le pertenecen dejan de estar autorizadas.
    Mongo.delete_many(Db.conn(), @collection, %{
      teacher_id: id,
      cle_auto: %{"$nin" => Enum.map(sections, & &1.id)}
    })

    :ok
  end

  # --- Auxiliares ----------------------------------------------------------

  # Un token de SIGMA caducado no es un error del docente: se le pide iniciar
  # sesión de nuevo y se olvida el token guardado.
  defp handle(teacher, {:error, :session_expired}) do
    Accounts.clear_sigma_token(teacher)
    {:error, :session_expired}
  end

  defp handle(_teacher, result), do: result

  defp token_for(teacher) do
    case Accounts.sigma_token(teacher) do
      {:ok, token} -> {:ok, token}
      :error -> {:error, :session_expired}
    end
  end

  defp teacher_id(teacher), do: Db.id_to_string(teacher["_id"])

  defp audit(teacher, action, detail, student_code \\ nil) do
    Audit.log(action, %{
      actor_type: "teacher",
      actor_id: teacher["sigma_code"],
      student_code: student_code,
      detail: detail
    })
  end
end
