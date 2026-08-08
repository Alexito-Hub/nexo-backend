defmodule NexoWeb.AdminController do
  use NexoWeb, :controller

  alias Nexo.{Accounts, Audit, Auth, Db}
  alias NexoWeb.AuthController

  def list_teachers(conn, _params) do
    json(conn, %{teachers: Enum.map(Accounts.list_teachers(), &AuthController.teacher_view/1)})
  end

  def set_teacher_status(conn, %{"id" => id, "estado" => estado}) do
    with true <- estado in Accounts.valid_statuses(),
         %{} = teacher <- Accounts.get_teacher(id),
         {:ok, updated} <- Accounts.set_teacher_status(teacher, estado, "admin") do
      if estado == "suspendido", do: Auth.revoke_all(:teacher, Db.id_to_string(teacher["_id"]))

      Audit.log(:teacher_status_change, %{
        actor_type: "admin",
        actor_id: "admin",
        detail: %{teacher: teacher["sigma_code"], estado: estado}
      })

      json(conn, %{teacher: AuthController.teacher_view(updated)})
    else
      false ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "estado_invalido"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "docente_no_encontrado"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "estado_invalido"})
    end
  end

  def set_teacher_status(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  def audit(conn, params) do
    limit = min(String.to_integer(params["limit"] || "100"), 500)

    entries =
      Enum.map(Audit.recent(limit), fn e ->
        %{
          accion: e["action"],
          actor: e["actor_id"],
          tipo_actor: e["actor_type"],
          estudiante: e["student_code"],
          detalle: e["detail"],
          ip: e["ip"],
          fecha: e["inserted_at"]
        }
      end)

    json(conn, %{audit: entries})
  end
end
