defmodule NexoWeb.AuthController do
  use NexoWeb, :controller

  alias Nexo.{Accounts, Audit, Auth, Db, Sigma, Students}

  @doc """
  Login docente: verifica credenciales contra SIGMA (una vez, sin persistir la
  contraseña), exige `isDocente`, registra/actualiza al docente y emite tokens
  propios.
  """
  def teacher_login(conn, %{"usuario" => usuario, "clave" => clave})
      when is_binary(usuario) and is_binary(clave) do
    case Sigma.verify_login(usuario, clave) do
      {:ok, %{teacher?: true} = profile} ->
        {:ok, teacher} = Accounts.upsert_teacher_from_sigma(profile)
        # El token de SIGMA (no la contraseña) se guarda cifrado: es lo que
        # permite consultar secciones y notas en nombre del docente.
        {:ok, teacher} = Accounts.put_sigma_token(teacher, profile[:token])
        id = Db.id_to_string(teacher["_id"])

        Audit.log(:teacher_login, %{
          actor_type: "teacher",
          actor_id: teacher["sigma_code"],
          ip: client_ip(conn)
        })

        json(conn, %{
          access_token: Auth.sign_access_token(:teacher, id),
          refresh_token: Auth.issue_refresh_token(:teacher, id),
          expires_in: Auth.access_ttl_seconds(),
          teacher: teacher_view(teacher)
        })

      {:ok, _no_docente} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "no_docente", detail: "Esta cuenta no es de un docente."})

      {:error, reason} ->
        login_error(conn, reason)
    end
  end

  def teacher_login(conn, _params), do: bad_request(conn)

  @doc """
  Login de estudiante. Solo habilita gestionar su consentimiento y subir sus
  propios datos: el backend nunca consulta la Intranet en su nombre.
  """
  def student_login(conn, %{"usuario" => usuario, "clave" => clave})
      when is_binary(usuario) and is_binary(clave) do
    case Sigma.verify_login(usuario, clave) do
      {:ok, %{teacher?: false} = profile} ->
        {:ok, student} = Students.upsert_from_sigma(profile)
        id = Db.id_to_string(student["_id"])

        Audit.log(:student_login, %{
          actor_type: "student",
          actor_id: student["code"],
          student_code: student["code"],
          ip: client_ip(conn)
        })

        json(conn, %{
          access_token: Auth.sign_access_token(:student, id),
          refresh_token: Auth.issue_refresh_token(:student, id),
          expires_in: Auth.access_ttl_seconds(),
          student: student_view(student)
        })

      {:ok, _docente} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "no_estudiante",
          detail: "Esta cuenta es de docente: usa el acceso de docentes."
        })

      {:error, reason} ->
        login_error(conn, reason)
    end
  end

  def student_login(conn, _params), do: bad_request(conn)

  def refresh(conn, %{"refresh_token" => raw}) when is_binary(raw) do
    case Auth.exchange_refresh_token(raw) do
      {:ok, %{type: type, id: id, new_refresh: new_refresh}} ->
        json(conn, %{
          access_token: Auth.sign_access_token(type, id),
          refresh_token: new_refresh,
          expires_in: Auth.access_ttl_seconds()
        })

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "refresh_invalido"})
    end
  end

  def refresh(conn, _params), do: bad_request(conn)

  def teacher_view(teacher) do
    %{
      id: Db.id_to_string(teacher["_id"]),
      codigo: teacher["sigma_code"],
      nombres: teacher["first_name"],
      apellidos: teacher["last_name"],
      estado: teacher["status"]
    }
  end

  def student_view(student) do
    %{
      id: Db.id_to_string(student["_id"]),
      codigo: student["code"],
      nombres: student["first_name"],
      apellidos: student["last_name"]
    }
  end

  defp login_error(conn, :invalid_credentials) do
    conn |> put_status(:unauthorized) |> json(%{error: "credenciales_invalidas"})
  end

  defp login_error(conn, _reason) do
    conn |> put_status(:service_unavailable) |> json(%{error: "sigma_no_disponible"})
  end

  defp bad_request(conn) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
