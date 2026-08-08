defmodule NexoWeb.ConsentController do
  use NexoWeb, :controller

  alias Nexo.Consents

  @doc "Estado actual del consentimiento del estudiante autenticado."
  def show(conn, _params) do
    code = student_code(conn)
    consent = Consents.current(code)

    json(conn, %{
      ambito: Consents.scope(),
      modulos_disponibles: Consents.modules(),
      consentimiento:
        case consent do
          nil ->
            %{otorgado: false, modulos: []}

          c ->
            %{
              otorgado: true,
              modulos: c["modules"],
              fecha: c["granted_at"],
              version_terminos: c["terms_version"]
            }
        end
    })
  end

  @doc """
  Registra la decisión del estudiante. `modulos: []` equivale a rechazar y
  elimina lo que ya se hubiera compartido.
  """
  def update(conn, params) do
    modules = List.wrap(params["modulos"] || [])
    opts = [ip: client_ip(conn), terms_version: params["version_terminos"] || "1"]

    case Consents.grant(student_code(conn), modules, opts) do
      {:ok, :revoked} -> json(conn, %{otorgado: false, modulos: []})
      {:ok, consent} -> json(conn, %{otorgado: true, modulos: consent["modules"]})
    end
  end

  @doc "Revocación explícita: borra además los datos ya compartidos."
  def revoke(conn, _params) do
    {:ok, :revoked} = Consents.revoke(student_code(conn), ip: client_ip(conn))
    json(conn, %{otorgado: false, modulos: []})
  end

  @doc "Historial de decisiones: el estudiante puede ver qué aceptó y cuándo."
  def history(conn, _params) do
    entries =
      conn
      |> student_code()
      |> Consents.history()
      |> Enum.map(fn c ->
        %{
          modulos: c["modules"],
          otorgado_en: c["granted_at"],
          revocado_en: c["revoked_at"],
          version_terminos: c["terms_version"]
        }
      end)

    json(conn, %{historial: entries})
  end

  @doc "La app del estudiante sube un módulo de datos ya consentido."
  def put_snapshot(conn, %{"modulo" => module} = params) do
    payload = params["datos"]

    case Consents.put_snapshot(student_code(conn), module, payload) do
      {:ok, :saved} ->
        json(conn, %{guardado: true, modulo: module})

      {:error, :not_granted} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: "modulo_no_consentido",
          detail: "Autoriza este módulo antes de compartir sus datos."
        })

      {:error, :invalid_module} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "modulo_invalido", modulos_validos: Consents.modules()})

      {:error, :invalid_payload} ->
        conn |> put_status(:bad_request) |> json(%{error: "datos_invalidos"})
    end
  end

  def put_snapshot(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  defp student_code(conn), do: conn.assigns.current_student["code"]
  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
