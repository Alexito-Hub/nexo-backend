defmodule NexoWeb.HealthController do
  use NexoWeb, :controller

  @doc """
  Sonda de salud para orquestadores y balanceadores. Comprueba que la conexión
  a MongoDB responde: un proceso vivo con la base caída no es "sano".
  """
  def show(conn, _params) do
    case Mongo.ping(Nexo.Db.conn()) do
      {:ok, _} ->
        json(conn, %{status: "ok", db: "ok"})

      _ ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "degraded", db: "error"})
    end
  end
end
