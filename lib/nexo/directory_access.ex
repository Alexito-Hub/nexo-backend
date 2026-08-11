defmodule Nexo.DirectoryAccess do
  @moduledoc """
  Quién puede entrar al directorio de estudiantes (colección `directory_access`).

  Este es el único papel del backend en este apartado: **decidir si una cuenta
  tiene acceso**. Los datos académicos son de SIGMA/Intranet; aquí solo se
  responde sí o no, y queda registrado quién concedió qué.

  Dos niveles, a propósito distintos:

  * **Administradores del sistema** (`SYSTEM_ADMINS` en el entorno). Son los
    que reparten el acceso. Van en el entorno y no en la base porque quien
    puede repartir permisos no debe poder concederse a sí mismo desde dentro
    de la aplicación: para cambiar esa lista hay que tocar el despliegue.
  * **Autorizados** (documentos de esta colección). Los concede un
    administrador y se pueden revocar en caliente. Aquí sí van en la base:
    cambian a menudo y son la operación normal del día a día.

  Revocar no borra el documento: lo marca. El histórico de quién tuvo acceso
  y cuándo es justo lo que hay que poder demostrar.
  """
  alias Nexo.{Audit, Db}

  @collection "directory_access"
  @statuses ~w(activo revocado)

  def valid_statuses, do: @statuses

  @doc "Códigos con potestad para conceder acceso (DNI o código SIGMA)."
  def system_admins do
    :nexo
    |> Application.get_env(:system_admins, "")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def admin?(code), do: code in system_admins()

  @doc """
  Acceso efectivo de un código: `:admin` (reparte y consulta), `:autorizado`
  (solo consulta) o `nil`.
  """
  def role(code) do
    cond do
      admin?(code) -> :admin
      active?(code) -> :autorizado
      true -> nil
    end
  end

  def allowed?(code), do: role(code) != nil

  def active?(code) do
    case get(code) do
      %{"status" => "activo"} -> true
      _ -> false
    end
  end

  def get(code), do: Mongo.find_one(Db.conn(), @collection, %{code: code})

  @doc "Todos los accesos concedidos, vigentes o no, del más reciente al más viejo."
  def list do
    Db.conn()
    |> Mongo.find(@collection, %{}, sort: %{updated_at: -1})
    |> Enum.to_list()
  end

  @doc """
  Concede acceso a un código. Es idempotente: volver a concederlo a alguien
  revocado lo reactiva y deja constancia de ambas decisiones en la auditoría.
  """
  def grant(code, granted_by, opts \\ []) when is_binary(code) and code != "" do
    set(code, "activo", granted_by, opts)
  end

  def revoke(code, revoked_by, opts \\ []) when is_binary(code) do
    set(code, "revocado", revoked_by, opts)
  end

  def set_status(code, status, actor, opts \\ [])

  def set_status(code, status, actor, opts) when status in @statuses do
    set(code, status, actor, opts)
  end

  def set_status(_code, _status, _actor, _opts), do: {:error, :invalid_status}

  defp set(code, status, actor, opts) do
    now = Db.now()

    doc = %{
      "status" => status,
      "note" => Keyword.get(opts, :note),
      "updated_at" => now,
      "updated_by" => actor
    }

    doc =
      if status == "activo",
        do: Map.merge(doc, %{"granted_at" => now, "granted_by" => actor, "revoked_at" => nil}),
        else: Map.merge(doc, %{"revoked_at" => now})

    {:ok, _} =
      Mongo.update_one(
        Db.conn(),
        @collection,
        %{code: code},
        %{"$set" => doc, "$setOnInsert" => %{"code" => code, "inserted_at" => now}},
        upsert: true
      )

    Audit.log(
      if(status == "activo", do: :directory_access_granted, else: :directory_access_revoked),
      actor_type: "admin",
      actor_id: actor,
      detail: %{code: code, note: Keyword.get(opts, :note)},
      ip: Keyword.get(opts, :ip)
    )

    {:ok, Map.put(doc, "code", code)}
  end
end
