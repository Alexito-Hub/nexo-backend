defmodule Nexo.Sigma.Client do
  @moduledoc """
  Cliente HTTP real contra `POST /api/Login/SesionV1` de SIGMA.

  Réplica del contrato que ya usa la app Flutter: la clave viaja en base64 y
  `nomSys` identifica el sistema. Un `success: false` es señal POSITIVA de
  credenciales inválidas; cualquier fallo de red/HTML se reporta como
  `:unavailable` para no confundir caídas de SIGMA con contraseñas malas
  (misma distinción que hace la app).
  """
  @behaviour Nexo.Sigma

  @impl true
  def verify_login(usuario_id, password) do
    body = %{
      "usuarioId" => usuario_id,
      "clave" => Base.encode64(password),
      "nomSys" => "SIGMA"
    }

    case Req.post(req(), url: "/Login/SesionV1", json: body) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true, "data" => data}}}
      when is_map(data) ->
        info = data["info"] || %{}

        {:ok,
         %{
           code: to_string(info["codigo"] || usuario_id),
           first_name: to_string(info["nombres"] || ""),
           last_name: to_string(info["apellidos"] || ""),
           teacher?: truthy?(info["isDocente"])
         }}

      {:ok, %Req.Response{status: 200, body: %{"success" => false}}} ->
        {:error, :invalid_credentials}

      _other ->
        {:error, :unavailable}
    end
  end

  defp truthy?(true), do: true
  defp truthy?(1), do: true
  defp truthy?(v) when is_binary(v), do: String.downcase(v) in ["true", "1", "s"]
  defp truthy?(_), do: false

  defp req do
    Req.new(
      base_url: Application.get_env(:nexo, :sigma_base_url, "https://sigma.upla.edu.pe/api"),
      headers: [{"user-agent", "Nexo-Backend/0.1 (Elixir)"}],
      receive_timeout: 30_000,
      retry: false
    )
  end
end
