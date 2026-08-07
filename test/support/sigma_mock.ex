defmodule Nexo.SigmaMock do
  @moduledoc """
  SIGMA simulado para los tests.

  Cuentas:

  - `"D001"`/`"ok"` → docente con las secciones `S-1` y `S-2`
  - `"D002"`/`"ok"` → otro docente, con la sección `S-9` (sirve para comprobar
    que nadie alcanza secciones ajenas)
  - `"E001"`/`"ok"` → estudiante (no docente)
  - `"down"` → SIGMA caído
  - clave `"expirado"` → devuelve un token que SIGMA ya no acepta
  """
  @behaviour Nexo.Sigma

  @sections %{
    "tok-D001" => [
      %{
        id: "S-1",
        code: "332123",
        subject: "ALGEBRA LINEAL",
        section: "A1",
        periodo: "2026-I",
        enrolled: 2
      },
      %{
        id: "S-2",
        code: "332124",
        subject: "CALCULO II",
        section: "B2",
        periodo: "2026-I",
        enrolled: 1
      }
    ],
    "tok-D002" => [
      %{
        id: "S-9",
        code: "339999",
        subject: "REDES",
        section: "C1",
        periodo: "2026-I",
        enrolled: 1
      }
    ]
  }

  @students %{
    "S-1" => [
      %{code: "E001", first_name: "José", last_name: "Rojas", attendance: "100", grade: "15"},
      %{code: "E002", first_name: "Ana", last_name: "Flores", attendance: "90", grade: "11.60"}
    ],
    "S-2" => [
      %{code: "E003", first_name: "Luis", last_name: "Pérez", attendance: "80", grade: "13"}
    ],
    "S-9" => [
      %{code: "E004", first_name: "Rosa", last_name: "Díaz", attendance: "95", grade: "17"}
    ]
  }

  @impl true
  def verify_login("down", _), do: {:error, :unavailable}

  def verify_login("D001", "expirado") do
    {:ok, profile("D001", "María", "Quispe", "tok-vencido")}
  end

  def verify_login("D001", "ok"), do: {:ok, profile("D001", "María", "Quispe", "tok-D001")}
  def verify_login("D002", "ok"), do: {:ok, profile("D002", "Carlos", "Ramos", "tok-D002")}

  def verify_login("E001", "ok") do
    {:ok,
     %{code: "E001", first_name: "José", last_name: "Rojas", teacher?: false, token: "tok-E001"}}
  end

  def verify_login(_, _), do: {:error, :invalid_credentials}

  @impl true
  def list_sections("tok-vencido"), do: {:error, :session_expired}
  def list_sections(token), do: {:ok, Map.get(@sections, token, [])}

  @impl true
  def list_section_students("tok-vencido", _), do: {:error, :session_expired}
  def list_section_students(_token, cle_auto), do: {:ok, Map.get(@students, cle_auto, [])}

  @impl true
  def section_grades("tok-vencido", _, _), do: {:error, :session_expired}
  def section_grades(_token, cle_auto, _unit), do: {:ok, Map.get(@students, cle_auto, [])}

  defp profile(code, first, last, token) do
    %{code: code, first_name: first, last_name: last, teacher?: true, token: token}
  end
end
