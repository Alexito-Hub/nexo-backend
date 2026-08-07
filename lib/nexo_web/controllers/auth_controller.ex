defmodule NexoWeb.AuthController do
  use NexoWeb, :controller

  alias Nexo.{Accounts, Audit, Auth, Db, Sigma}

  @doc """
  Login docente: verifica credenciales contra SIGMA (una vez, sin persistir),
  exige `isDocente`, registra/actualiza al docente y emite tokens propios.
  """
  def teacher_login(conn, %{"usuario" => usuario, "clave" => clave})
      when is_binary(usuario) and is_binary(clave) do
    case Sigma.verify_login(usuario, clave) do
      {:ok, %{teacher?: true} = profile} ->
        {:ok, teacher} = Accounts.upsert_teacher_from_sigma(profile)
        teacher_id = Db.id_to_string(teacher["_id"])

        Audit.log(:teacher_login, %{
          actor_type: "teacher",
          actor_id: teacher["sigma_code"],
          ip: client_ip(conn)
        })

        json(conn, %{
          access_token: Auth.sign_access_token(teacher_id),
          refresh_token: Auth.issue_refresh_token(teacher_id),
          expires_in: Auth.access_ttl_seconds(),
          teacher: teacher_view(teacher)
        })

      {:ok, _no_docente} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "no_docente", detail: "Esta cuenta no es de un docente."})

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "credenciales_invalidas"})

      {:error, :unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "sigma_no_disponible"})
    end
  end

  def teacher_login(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  def refresh(conn, %{"refresh_token" => raw}) when is_binary(raw) do
    case Auth.exchange_refresh_token(raw) do
      {:ok, %{teacher_id: id, new_refresh: new_refresh}} ->
        json(conn, %{
          access_token: Auth.sign_access_token(id),
          refresh_token: new_refresh,
          expires_in: Auth.access_ttl_seconds()
        })

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "refresh_invalido"})
    end
  end

  def refresh(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  def teacher_view(teacher) do
    %{
      id: Db.id_to_string(teacher["_id"]),
      codigo: teacher["sigma_code"],
      nombres: teacher["first_name"],
      apellidos: teacher["last_name"],
      estado: teacher["status"]
    }
  end

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
