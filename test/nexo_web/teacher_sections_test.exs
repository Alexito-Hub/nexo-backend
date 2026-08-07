defmodule NexoWeb.TeacherSectionsTest do
  @moduledoc """
  Cubre la garantía central de F2: un docente autorizado ve sus secciones y
  nada más. El caso de la sección ajena es el que sostiene todo el diseño.
  """
  use NexoWeb.ConnCase, async: false

  alias Nexo.{Accounts, Audit, Db}

  setup do
    for collection <- ["teachers", "refresh_tokens", "audit_log", "teacher_sections"] do
      Mongo.delete_many(Db.conn(), collection, %{})
    end

    :ok
  end

  # Inicia sesión y deja al docente autorizado en la allowlist.
  defp authorized_teacher(conn, usuario \\ "D001", clave \\ "ok") do
    %{"access_token" => access} =
      post(conn, "/api/v1/auth/teacher/login", %{"usuario" => usuario, "clave" => clave})
      |> json_response(200)

    teacher = Accounts.get_teacher_by_code(usuario)
    {:ok, _} = Accounts.set_teacher_status(teacher, "autorizado", "test")

    put_req_header(conn, "authorization", "Bearer #{access}")
  end

  test "un docente pendiente no alcanza los datos académicos", %{conn: conn} do
    %{"access_token" => access} =
      post(conn, "/api/v1/auth/teacher/login", %{"usuario" => "D001", "clave" => "ok"})
      |> json_response(200)

    res =
      conn
      |> put_req_header("authorization", "Bearer #{access}")
      |> get("/api/v1/teacher/sections")
      |> json_response(403)

    assert res["error"] == "no_autorizado"
  end

  test "lista sus secciones", %{conn: conn} do
    res = authorized_teacher(conn) |> get("/api/v1/teacher/sections") |> json_response(200)

    assert [%{"id" => "S-1", "asignatura" => "ALGEBRA LINEAL"}, %{"id" => "S-2"}] =
             res["secciones"]
  end

  test "lista los estudiantes de una sección propia y lo audita", %{conn: conn} do
    res =
      authorized_teacher(conn)
      |> get("/api/v1/teacher/sections/S-1/students")
      |> json_response(200)

    assert length(res["estudiantes"]) == 2
    assert Enum.any?(res["estudiantes"], &(&1["codigo"] == "E002"))

    assert Enum.any?(
             Audit.recent(),
             &(&1["action"] == "section_students_read" and &1["actor_id"] == "D001")
           )
  end

  test "NO alcanza una sección de otro docente y queda registrado", %{conn: conn} do
    res =
      authorized_teacher(conn)
      |> get("/api/v1/teacher/sections/S-9/students")
      |> json_response(403)

    assert res["error"] == "seccion_ajena"

    assert Enum.any?(
             Audit.recent(),
             &(&1["action"] == "section_access_denied" and &1["actor_id"] == "D001")
           )
  end

  test "cada docente ve solo lo suyo", %{conn: conn} do
    otro = authorized_teacher(conn, "D002", "ok")
    res = otro |> get("/api/v1/teacher/sections") |> json_response(200)

    assert [%{"id" => "S-9"}] = res["secciones"]
    assert otro |> get("/api/v1/teacher/sections/S-1/students") |> json_response(403)
  end

  test "notas de un estudiante concreto quedan auditadas nominalmente", %{conn: conn} do
    res =
      authorized_teacher(conn)
      |> get("/api/v1/teacher/sections/S-1/students/E002/grades?unidad=1")
      |> json_response(200)

    assert res["estudiante"]["nota"] == "11.60"
    assert res["unidad"] == "1"

    assert Enum.any?(
             Audit.recent(),
             &(&1["action"] == "student_grades_read" and &1["student_code"] == "E002")
           )
  end

  test "un estudiante que no está en la sección devuelve 404", %{conn: conn} do
    assert authorized_teacher(conn)
           |> get("/api/v1/teacher/sections/S-1/students/E999/grades")
           |> json_response(404)
  end

  test "si el token de SIGMA caducó se pide reiniciar sesión y se olvida", %{conn: conn} do
    res =
      authorized_teacher(conn, "D001", "expirado")
      |> get("/api/v1/teacher/sections")
      |> json_response(401)

    assert res["error"] == "sesion_sigma_expirada"
    assert Accounts.sigma_token(Accounts.get_teacher_by_code("D001")) == :error
  end

  test "el token de SIGMA no se guarda en claro", %{conn: conn} do
    authorized_teacher(conn)
    teacher = Accounts.get_teacher_by_code("D001")

    assert %BSON.Binary{binary: cifrado} = teacher["sigma_token"]
    refute cifrado =~ "tok-D001"
    assert {:ok, "tok-D001"} = Accounts.sigma_token(teacher)
  end
end
