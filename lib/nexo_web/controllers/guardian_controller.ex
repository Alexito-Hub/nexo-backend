defmodule NexoWeb.GuardianController do
  use NexoWeb, :controller

  alias Nexo.{Audit, Auth, Db, Directory, Guardians}

  @doc """
  Entrada del apoderado: DNI + PIN. Sin cuenta de la UPLA de por medio, que es
  justamente el caso que resuelve este acceso.
  """
  def login(conn, %{"dni" => dni, "pin" => pin}) when is_binary(dni) and is_binary(pin) do
    case Guardians.verify(String.trim(dni), String.trim(pin)) do
      {:ok, guardian} ->
        id = Db.id_to_string(guardian["_id"])

        Audit.log(:guardian_login, %{
          actor_type: "guardian",
          actor_id: guardian["dni"],
          ip: client_ip(conn)
        })

        json(conn, %{
          access_token: Auth.sign_access_token(:guardian, id),
          refresh_token: Auth.issue_refresh_token(:guardian, id),
          expires_in: Auth.access_ttl_seconds(),
          apoderado: guardian_view(guardian),
          estudiantes: summaries(guardian)
        })

      {:error, :locked} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          error: "acceso_bloqueado",
          detail: "Demasiados intentos. Espera unos minutos y vuelve a probar."
        })

      {:error, :invalid} ->
        Audit.log(:guardian_login_failed, %{
          actor_type: "guardian",
          actor_id: String.trim(dni),
          ip: client_ip(conn)
        })

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "credenciales_invalidas", detail: "DNI o PIN incorrectos."})
    end
  end

  def login(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  @doc "Los estudiantes que este apoderado puede ver."
  def students(conn, _params) do
    json(conn, %{estudiantes: summaries(guardian(conn))})
  end

  @doc """
  Ficha del estudiante. Solo la de sus propios hijos, y cada apertura queda
  auditada igual que la de un docente.
  """
  def show(conn, %{"codigo" => codigo}) do
    g = guardian(conn)

    cond do
      not Guardians.linked?(g, codigo) ->
        Audit.log(:guardian_access_denied, %{
          actor_type: "guardian",
          actor_id: g["dni"],
          student_code: codigo,
          ip: client_ip(conn)
        })

        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "estudiante_ajeno",
          detail: "Solo puedes ver la ficha de tus hijos o tutelados."
        })

      true ->
        case Directory.get(codigo) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "no_encontrado"})

          record ->
            Audit.log(:guardian_record_read, %{
              actor_type: "guardian",
              actor_id: g["dni"],
              student_code: codigo,
              ip: client_ip(conn)
            })

            json(conn, %{estudiante: NexoWeb.DirectoryController.record_view(record)})
        end
    end
  end

  # --- Vistas ---------------------------------------------------------------

  defp summaries(guardian) do
    guardian
    |> Guardians.students()
    |> Enum.map(&Directory.get/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&NexoWeb.DirectoryController.summary_view/1)
  end

  def guardian_view(guardian) do
    %{
      dni: guardian["dni"],
      nombre: guardian["name"],
      estudiantes: length(Guardians.students(guardian))
    }
  end

  defp guardian(conn), do: conn.assigns.current_guardian

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
