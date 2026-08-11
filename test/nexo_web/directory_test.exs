defmodule NexoWeb.DirectoryTest do
  @moduledoc """
  El directorio de estudiantes y su portero.

  Lo que se fija aquí es la regla que motivó el apartado: **quien entra no lo
  decide el tipo de cuenta sino el acceso concedido**. Un estudiante
  autorizado entra; un docente sin autorizar, no.
  """
  use NexoWeb.ConnCase, async: false

  alias Nexo.{Db, Directory, DirectoryAccess}
  alias Nexo.Directory.Prototype

  @admin "62017241"

  setup do
    for collection <- [
          "teachers",
          "students",
          "refresh_tokens",
          "audit_log",
          "directory_access",
          "directory_students"
        ] do
      Mongo.delete_many(Db.conn(), collection, %{})
    end

    Db.ensure_indexes()
    :ok = Directory.replace_all(Prototype.generate(12, 42))
    :ok
  end

  defp login_student(conn, usuario \\ "E001") do
    %{"access_token" => token} =
      conn
      |> post("/api/v1/auth/student/login", %{"usuario" => usuario, "clave" => "ok"})
      |> json_response(200)

    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp login_teacher(conn, usuario \\ "D001") do
    %{"access_token" => token} =
      conn
      |> post("/api/v1/auth/teacher/login", %{"usuario" => usuario, "clave" => "ok"})
      |> json_response(200)

    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  test "sin token no se llega ni a preguntar por el acceso", %{conn: conn} do
    assert conn |> get("/api/v1/directory/access") |> json_response(401)
  end

  test "un estudiante sin autorizar sabe que no tiene acceso", %{conn: conn} do
    res = conn |> login_student() |> get("/api/v1/directory/access") |> json_response(200)

    assert res["acceso"] == false
    assert res["rol"] == nil
    assert res["tipo"] == "student"
  end

  test "sin acceso no se lista nada", %{conn: conn} do
    res =
      conn
      |> login_student()
      |> get("/api/v1/directory/students")
      |> json_response(403)

    assert res["error"] == "sin_acceso_directorio"
  end

  test "un estudiante autorizado entra y lista el directorio", %{conn: conn} do
    {:ok, _} = DirectoryAccess.grant("E001", @admin)

    autorizado = login_student(conn)

    acceso = autorizado |> get("/api/v1/directory/access") |> json_response(200)
    assert acceso["acceso"] == true
    assert acceso["rol"] == "autorizado"

    res = autorizado |> get("/api/v1/directory/students?limite=5") |> json_response(200)
    assert length(res["estudiantes"]) == 5
    assert res["total"] == 12
    assert res["paginas"] == 3
    # La lista no arrastra los módulos: eso es de la ficha.
    refute Map.has_key?(hd(res["estudiantes"]), "modulos")
  end

  test "un docente sin autorizar tampoco entra", %{conn: conn} do
    res = conn |> login_teacher() |> get("/api/v1/directory/students") |> json_response(403)
    assert res["error"] == "sin_acceso_directorio"
  end

  test "un docente autorizado entra igual que un estudiante", %{conn: conn} do
    {:ok, _} = DirectoryAccess.grant("D001", @admin)

    res = conn |> login_teacher() |> get("/api/v1/directory/students") |> json_response(200)
    assert res["total"] == 12
  end

  test "la ficha trae los módulos y queda auditada con nombre y apellido", %{conn: conn} do
    {:ok, _} = DirectoryAccess.grant("E001", @admin)
    autorizado = login_student(conn)

    %{"estudiantes" => [primero | _]} =
      autorizado |> get("/api/v1/directory/students?limite=1") |> json_response(200)

    codigo = primero["codigo"]

    res =
      autorizado
      |> get("/api/v1/directory/students/#{codigo}")
      |> json_response(200)

    ficha = res["estudiante"]
    assert ficha["codigo"] == codigo
    assert ficha["correo"] =~ "@upla.edu.pe"
    assert ficha["modulos"]["notas"]["periodo"] == "2026-1"
    assert is_list(ficha["modulos"]["horario"]["clases"])

    assert Enum.any?(
             Nexo.Audit.recent(),
             &(&1["action"] == "directory_record_read" and &1["student_code"] == codigo and
                 &1["actor_id"] == "E001")
           )
  end

  test "la búsqueda encuentra por prefijo de apellido y de código", %{conn: conn} do
    {:ok, _} = DirectoryAccess.grant("E001", @admin)
    autorizado = login_student(conn)

    %{"estudiantes" => [alguien | _]} =
      autorizado |> get("/api/v1/directory/students?limite=1") |> json_response(200)

    prefijo = alguien["apellidos"] |> String.slice(0, 4) |> String.downcase()

    res =
      autorizado
      |> get("/api/v1/directory/students?q=#{prefijo}")
      |> json_response(200)

    assert res["total"] >= 1
    assert Enum.all?(res["estudiantes"], &(String.downcase(&1["apellidos"]) =~ prefijo))

    por_codigo =
      autorizado
      |> get("/api/v1/directory/students?q=#{alguien["codigo"]}")
      |> json_response(200)

    assert por_codigo["total"] == 1
  end

  test "una ficha inexistente es 404, no un error genérico", %{conn: conn} do
    {:ok, _} = DirectoryAccess.grant("E001", @admin)

    assert conn
           |> login_student()
           |> get("/api/v1/directory/students/NO-EXISTE")
           |> json_response(404)
  end

  describe "administración del acceso" do
    setup %{conn: conn} do
      # `ADMIN-SYS` inicia sesión con un código que está en SYSTEM_ADMINS.
      %{admin: login_student(conn, "ADMIN-SYS")}
    end

    test "el administrador entra sin que nadie lo autorice", %{admin: admin} do
      res = admin |> get("/api/v1/directory/access") |> json_response(200)
      assert res["rol"] == "admin"
    end

    test "concede y revoca acceso a otro código", %{admin: admin, conn: conn} do
      res =
        admin
        |> put("/api/v1/directory/grants/E001", %{"estado" => "activo", "nota" => "piloto"})
        |> json_response(200)

      assert res["acceso"]["estado"] == "activo"
      assert res["acceso"]["concedido_por"] == @admin
      assert DirectoryAccess.allowed?("E001")

      # Y el interesado ya entra.
      assert conn |> login_student() |> get("/api/v1/directory/students") |> json_response(200)

      admin
      |> put("/api/v1/directory/grants/E001", %{"estado" => "revocado"})
      |> json_response(200)

      # Revocar surte efecto en la siguiente petición, sin esperar al token.
      assert conn |> login_student() |> get("/api/v1/directory/students") |> json_response(403)

      # Pero queda el rastro de que lo tuvo.
      grant = DirectoryAccess.get("E001")
      assert grant["granted_at"] != nil
      assert grant["revoked_at"] != nil
    end

    test "un autorizado normal no puede repartir accesos", %{conn: conn} do
      {:ok, _} = DirectoryAccess.grant("E001", @admin)

      res =
        conn
        |> login_student()
        |> put("/api/v1/directory/grants/E999", %{"estado" => "activo"})
        |> json_response(403)

      assert res["error"] == "solo_administradores"
    end

    test "un estado inventado se rechaza", %{admin: admin} do
      assert admin
             |> put("/api/v1/directory/grants/E001", %{"estado" => "quizas"})
             |> json_response(422)
    end
  end
end
