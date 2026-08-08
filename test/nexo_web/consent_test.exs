defmodule NexoWeb.ConsentTest do
  @moduledoc """
  El opt-in del piloto: dónde queda lo que el estudiante autoriza y qué pasa
  cuando se arrepiente. Revocar tiene que borrar de verdad, no solo marcar.
  """
  use NexoWeb.ConnCase, async: false

  alias Nexo.{Accounts, Consents, Db}

  setup do
    for c <- ~w(teachers students refresh_tokens audit_log teacher_sections consents
                student_snapshots) do
      Mongo.delete_many(Db.conn(), c, %{})
    end

    :ok
  end

  defp student(conn, usuario \\ "E001") do
    %{"access_token" => access} =
      post(conn, "/api/v1/auth/student/login", %{"usuario" => usuario, "clave" => "ok"})
      |> json_response(200)

    put_req_header(conn, "authorization", "Bearer #{access}")
  end

  defp authorized_teacher(conn) do
    %{"access_token" => access} =
      post(conn, "/api/v1/auth/teacher/login", %{"usuario" => "D001", "clave" => "ok"})
      |> json_response(200)

    {:ok, _} =
      Accounts.set_teacher_status(Accounts.get_teacher_by_code("D001"), "autorizado", "t")

    put_req_header(conn, "authorization", "Bearer #{access}")
  end

  test "un docente no puede usar el acceso de estudiante y viceversa", %{conn: conn} do
    assert post(conn, "/api/v1/auth/student/login", %{"usuario" => "D001", "clave" => "ok"})
           |> json_response(403)

    assert post(conn, "/api/v1/auth/teacher/login", %{"usuario" => "E001", "clave" => "ok"})
           |> json_response(403)
  end

  test "por defecto no hay consentimiento", %{conn: conn} do
    res = student(conn) |> get("/api/v1/student/consent") |> json_response(200)

    assert res["consentimiento"] == %{"otorgado" => false, "modulos" => []}
    assert res["modulos_disponibles"] == ["horario", "notas", "pagos", "avance"]
  end

  test "el estudiante autoriza módulos y queda registrado con fecha", %{conn: conn} do
    res =
      student(conn)
      |> put("/api/v1/student/consent", %{"modulos" => ["horario", "pagos"]})
      |> json_response(200)

    assert res == %{"otorgado" => true, "modulos" => ["horario", "pagos"]}

    consent = Consents.current("E001")
    assert consent["modules"] == ["horario", "pagos"]
    assert consent["granted_at"]
    assert consent["terms_version"] == "1"
  end

  test "rechazar equivale a no autorizar nada", %{conn: conn} do
    res =
      student(conn) |> put("/api/v1/student/consent", %{"modulos" => []}) |> json_response(200)

    assert res["otorgado"] == false
    refute Consents.granted?("E001")
  end

  test "no se puede subir un módulo sin consentirlo", %{conn: conn} do
    res =
      student(conn)
      |> put("/api/v1/student/snapshots/pagos", %{"datos" => %{"deuda" => 250}})
      |> json_response(403)

    assert res["error"] == "modulo_no_consentido"
  end

  test "el snapshot se guarda cifrado y el docente lo ve solo con consentimiento",
       %{conn: conn} do
    alumno = student(conn)
    put(alumno, "/api/v1/student/consent", %{"modulos" => ["pagos"]})

    put(alumno, "/api/v1/student/snapshots/pagos", %{"datos" => %{"deuda" => 250.5}})
    |> json_response(200)

    # En la base no queda nada legible.
    doc = Mongo.find_one(Db.conn(), "student_snapshots", %{student_code: "E001"})
    assert %BSON.Binary{binary: cifrado} = doc["payload"]
    refute cifrado =~ "deuda"

    res =
      authorized_teacher(conn)
      |> get("/api/v1/teacher/sections/S-1/students/E001/shared/pagos")
      |> json_response(200)

    assert res["datos"] == %{"deuda" => 250.5}
  end

  test "revocar borra los datos compartidos y corta el acceso del docente", %{conn: conn} do
    alumno = student(conn)
    put(alumno, "/api/v1/student/consent", %{"modulos" => ["pagos"]})
    put(alumno, "/api/v1/student/snapshots/pagos", %{"datos" => %{"deuda" => 250}})

    delete(alumno, "/api/v1/student/consent") |> json_response(200)

    assert Mongo.find_one(Db.conn(), "student_snapshots", %{student_code: "E001"}) == nil

    res =
      authorized_teacher(conn)
      |> get("/api/v1/teacher/sections/S-1/students/E001/shared/pagos")
      |> json_response(403)

    assert res["error"] == "sin_consentimiento"
  end

  test "quitar un módulo elimina solo los datos de ese módulo", %{conn: conn} do
    alumno = student(conn)
    put(alumno, "/api/v1/student/consent", %{"modulos" => ["pagos", "horario"]})
    put(alumno, "/api/v1/student/snapshots/pagos", %{"datos" => %{"deuda" => 250}})
    put(alumno, "/api/v1/student/snapshots/horario", %{"datos" => %{"clases" => 5}})

    put(alumno, "/api/v1/student/consent", %{"modulos" => ["horario"]})

    assert Mongo.find_one(Db.conn(), "student_snapshots", %{
             student_code: "E001",
             module: "pagos"
           }) == nil

    assert Mongo.find_one(Db.conn(), "student_snapshots", %{
             student_code: "E001",
             module: "horario"
           })
  end

  test "el historial conserva cada decisión, incluidas las revocadas", %{conn: conn} do
    alumno = student(conn)
    put(alumno, "/api/v1/student/consent", %{"modulos" => ["pagos"]})
    delete(alumno, "/api/v1/student/consent")
    put(alumno, "/api/v1/student/consent", %{"modulos" => ["horario"]})

    res = get(alumno, "/api/v1/student/consent/history") |> json_response(200)

    assert length(res["historial"]) == 2
    assert Enum.any?(res["historial"], &(&1["revocado_en"] != nil))
  end

  test "un docente no alcanza datos de un alumno que no es de su sección", %{conn: conn} do
    otro = student(conn, "E004")
    put(otro, "/api/v1/student/consent", %{"modulos" => ["pagos"]})
    put(otro, "/api/v1/student/snapshots/pagos", %{"datos" => %{"deuda" => 1}})

    assert authorized_teacher(conn)
           |> get("/api/v1/teacher/sections/S-1/students/E004/shared/pagos")
           |> json_response(404)
  end
end
