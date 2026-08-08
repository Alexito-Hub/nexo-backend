defmodule NexoWeb.TeacherAuthTest do
  # La BD es compartida entre tests (Mongo real): sin async.
  use NexoWeb.ConnCase, async: false

  alias Nexo.{Accounts, Audit}

  @login_url "/api/v1/auth/teacher/login"

  # Mongo real compartido: cada test parte de colecciones vacías.
  setup do
    for collection <- ["teachers", "refresh_tokens", "audit_log"] do
      Mongo.delete_many(Nexo.Db.conn(), collection, %{})
    end

    :ok
  end

  defp login(conn, usuario \\ "D001", clave \\ "ok") do
    post(conn, @login_url, %{"usuario" => usuario, "clave" => clave})
  end

  test "login docente válido registra como pendiente y emite tokens", %{conn: conn} do
    res = json_response(login(conn), 200)

    assert %{"access_token" => access, "refresh_token" => refresh, "teacher" => teacher} = res
    assert is_binary(access) and is_binary(refresh)
    assert teacher["estado"] == "pendiente"
    assert teacher["codigo"] == "D001"

    # Queda auditado
    assert Enum.any?(
             Audit.recent(),
             &(&1["action"] == "teacher_login" and &1["actor_id"] == "D001")
           )
  end

  test "un documento preautorizado entra ya autorizado, sin aprobación manual",
       %{conn: conn} do
    res = login(conn, "PRE-001", "ok") |> json_response(200)

    assert res["teacher"]["estado"] == "autorizado"
    assert Accounts.get_teacher_by_code("PRE-001")["authorized_by"] == "preautorizado"
  end

  test "la preautorización no resucita a un docente suspendido", %{conn: conn} do
    login(conn, "PRE-001", "ok")
    teacher = Accounts.get_teacher_by_code("PRE-001")
    {:ok, _} = Accounts.set_teacher_status(teacher, "suspendido", "admin")

    res = login(conn, "PRE-001", "ok") |> json_response(200)
    assert res["teacher"]["estado"] == "suspendido"
  end

  test "una cuenta de estudiante es rechazada", %{conn: conn} do
    assert json_response(login(conn, "E001", "ok"), 403)["error"] == "no_docente"
  end

  test "credenciales inválidas → 401; SIGMA caído → 503", %{conn: conn} do
    assert json_response(login(conn, "D001", "mala"), 401)["error"] == "credenciales_invalidas"
    assert json_response(login(conn, "down", "x"), 503)["error"] == "sigma_no_disponible"
  end

  test "/teacher/me exige token y refleja el estado", %{conn: conn} do
    %{"access_token" => access} = json_response(login(conn), 200)

    assert get(conn, "/api/v1/teacher/me") |> json_response(401)

    me =
      conn
      |> put_req_header("authorization", "Bearer #{access}")
      |> get("/api/v1/teacher/me")
      |> json_response(200)

    assert me["teacher"]["estado"] == "pendiente"
  end

  test "refresh rota el token y el usado deja de servir", %{conn: conn} do
    %{"refresh_token" => refresh} = json_response(login(conn), 200)

    res =
      post(conn, "/api/v1/auth/refresh", %{"refresh_token" => refresh}) |> json_response(200)

    assert res["refresh_token"] != refresh

    assert post(conn, "/api/v1/auth/refresh", %{"refresh_token" => refresh})
           |> json_response(401)
  end

  test "admin aprueba a un docente y la suspensión revoca sus refresh", %{conn: conn} do
    %{"refresh_token" => refresh} = json_response(login(conn), 200)
    teacher = Accounts.get_teacher_by_code("D001")
    id = Nexo.Db.id_to_string(teacher["_id"])

    # Sin clave admin → 401
    assert put(conn, "/api/v1/admin/teachers/#{id}/status", %{"estado" => "autorizado"})
           |> json_response(401)

    admin = put_req_header(conn, "x-admin-key", "test-admin-key")

    res =
      put(admin, "/api/v1/admin/teachers/#{id}/status", %{"estado" => "autorizado"})
      |> json_response(200)

    assert res["teacher"]["estado"] == "autorizado"

    put(admin, "/api/v1/admin/teachers/#{id}/status", %{"estado" => "suspendido"})

    assert post(conn, "/api/v1/auth/refresh", %{"refresh_token" => refresh})
           |> json_response(401)
  end
end
