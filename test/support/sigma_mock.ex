defmodule Nexo.SigmaMock do
  @moduledoc """
  SIGMA falso para tests. Credenciales reconocidas:

  - "D001"/"ok"  → docente válido
  - "E001"/"ok"  → estudiante (no docente)
  - cualquier otra clave → credenciales inválidas
  - usuario "down" → SIGMA caído
  """
  @behaviour Nexo.Sigma

  @impl true
  def verify_login("down", _), do: {:error, :unavailable}

  def verify_login("D001", "ok") do
    {:ok, %{code: "D001", first_name: "María", last_name: "Quispe", teacher?: true}}
  end

  def verify_login("E001", "ok") do
    {:ok, %{code: "E001", first_name: "José", last_name: "Rojas", teacher?: false}}
  end

  def verify_login(_, _), do: {:error, :invalid_credentials}
end
