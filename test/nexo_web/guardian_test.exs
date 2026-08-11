defmodule NexoWeb.GuardianTest do
  @moduledoc """
  Acceso de apoderados: DNI + PIN, y solo la ficha de sus hijos.

  Lo que se fija aquí es que la puerta rápida siga siendo una puerta: sin PIN
  no se entra, a fuerza bruta tampoco, y desde dentro no se alcanza a un
  estudiante ajeno.
  """
  use NexoWeb.ConnCase, async: false

  alias Nexo.{Audit, Db, Directory, Guardians}
  alias Nexo.Directory.Prototype

  @admin "62017241"
  @dni "44556677"

  setup do
    for collection <- [
          "teachers",
          "students",
          "refresh_tokens",
          "audit_log",
          "directory_access",
          "directory_students",
          "guardians"
        ] do
      Mongo.delete_many(Db.conn(), collection, %{})
    end

    Db.ensure_indexes()
    :ok = Directory.replace_all(Prototype.generate(6, 7))

    codes = Directory.list(limit: 6).students |> Enum.map(& &1.code)
    {:ok, _, pin} = Guardians.link(@dni, [Enum.at(codes, 0)], actor: @admin, name: "Rosa")

    %{pin: pin, hijo: Enum.at(codes, 0), ajeno: Enum.at(codes, 1)}
  end

  defp login(conn, dni, pin) do
    post(conn, "/api/v1/guardian/login", %{"dni" => dni, "pin" => pin})
  end

  defp session(conn, pin) do
    %{"access_token" => token} = login(conn, @dni, pin) |> json_response(200)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  test "el PIN se entrega una sola vez y no se guarda en claro", %{pin: pin} do
    assert String.length(pin) == 6
    assert String.match?(pin, ~r/^\d{6}$/)

    doc = Guardians.get_by_dni(@dni)
    refute Map.has_key?(doc, "pin")
    assert %BSON.Binary{binary: hash} = doc["pin_hash"]
    refute hash == pin
  end

  test "entra con DNI y PIN y ve a su hijo", %{conn: conn, pin: pin, hijo: hijo} do
    res = login(conn, @dni, pin) |> json_response(200)

    assert res["apoderado"]["dni"] == @dni
    assert res["apoderado"]["nombre"] == "Rosa"
    assert [%{"codigo" => ^hijo}] = res["estudiantes"]
  end

  test "sin PIN correcto no entra", %{conn: conn} do
    res = login(conn, @dni, "000000") |> json_response(401)
    assert res["error"] == "credenciales_invalidas"
  end

  test "un DNI que no existe responde igual que un PIN malo", %{conn: conn} do
    # Distinguirlos delataría qué DNIs están registrados.
    res = login(conn, "11111111", "123456") |> json_response(401)
    assert res["error"] == "credenciales_invalidas"
  end

  test "tras cinco intentos se bloquea", %{conn: conn, pin: pin} do
    for _ <- 1..5, do: login(conn, @dni, "000000")

    res = login(conn, @dni, "000000") |> json_response(429)
    assert res["error"] == "acceso_bloqueado"

    # Y ni con el PIN bueno mientras dure el bloqueo.
    assert login(conn, @dni, pin) |> json_response(429)
  end

  test "abre la ficha de su hijo y queda auditado", %{
    conn: conn,
    pin: pin,
    hijo: hijo
  } do
    res =
      session(conn, pin)
      |> get("/api/v1/guardian/students/#{hijo}")
      |> json_response(200)

    assert res["estudiante"]["codigo"] == hijo
    assert res["estudiante"]["modulos"]["notas"]["periodo"] == "2026-1"

    assert Enum.any?(
             Audit.recent(),
             &(&1["action"] == "guardian_record_read" and &1["actor_id"] == @dni and
                 &1["student_code"] == hijo)
           )
  end

  test "no alcanza a un estudiante que no es suyo", %{
    conn: conn,
    pin: pin,
    ajeno: ajeno
  } do
    res =
      session(conn, pin)
      |> get("/api/v1/guardian/students/#{ajeno}")
      |> json_response(403)

    assert res["error"] == "estudiante_ajeno"

    assert Enum.any?(
             Audit.recent(),
             &(&1["action"] == "guardian_access_denied" and &1["actor_id"] == @dni)
           )
  end

  test "revocar corta el acceso en la siguiente petición", %{
    conn: conn,
    pin: pin,
    hijo: hijo
  } do
    autenticado = session(conn, pin)
    assert autenticado |> get("/api/v1/guardian/students/#{hijo}") |> json_response(200)

    {:ok, _} = Guardians.revoke(@dni, actor: @admin)

    assert autenticado |> get("/api/v1/guardian/students/#{hijo}") |> json_response(401)
  end

  test "el token de apoderado no sirve para el directorio", %{conn: conn, pin: pin} do
    assert session(conn, pin)
           |> get("/api/v1/directory/students")
           |> json_response(401)
  end

  describe "administración" do
    setup %{conn: conn} do
      %{admin: put_req_header(conn, "authorization", "Bearer #{admin_token(conn)}")}
    end

    test "un administrador vincula un apoderado y recibe el PIN", %{
      admin: admin,
      conn: conn,
      ajeno: otro
    } do
      res =
        admin
        |> put("/api/v1/directory/guardians/99887766", %{
          "nombre" => "Luis",
          "estudiantes" => [otro]
        })
        |> json_response(200)

      assert String.match?(res["pin"], ~r/^\d{6}$/)
      assert res["apoderado"]["estudiantes"] == [otro]

      # Y ese PIN funciona de verdad.
      assert conn
             |> post("/api/v1/guardian/login", %{
               "dni" => "99887766",
               "pin" => res["pin"]
             })
             |> json_response(200)
    end

    test "actualizar la lista no cambia el PIN", %{admin: admin, hijo: hijo, ajeno: otro} do
      res =
        admin
        |> put("/api/v1/directory/guardians/#{@dni}", %{"estudiantes" => [hijo, otro]})
        |> json_response(200)

      assert res["pin"] == nil
      assert length(res["apoderado"]["estudiantes"]) == 2
    end
  end

  defp admin_token(conn) do
    %{"access_token" => token} =
      conn
      |> post("/api/v1/auth/student/login", %{"usuario" => "ADMIN-SYS", "clave" => "ok"})
      |> json_response(200)

    token
  end
end
