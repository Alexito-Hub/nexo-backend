defmodule Nexo.Consents do
  @moduledoc """
  Consentimientos de estudiantes y los datos que autorizan a compartir.

  Dos colecciones, ambas en MongoDB (nada vive en el dispositivo ni en disco
  local):

  * `consents` — el registro legal. Cada decisión del estudiante se guarda como
    un documento nuevo con la fecha, la versión del texto aceptado y la IP:
    **no se sobrescribe**, porque ante un reclamo hay que poder demostrar qué
    se aceptó y cuándo. Revocar añade una revocación, no borra el historial.
  * `student_snapshots` — los datos en sí (horario, pagos, avance), que la app
    del estudiante sube solo si hay consentimiento vigente. El contenido se
    guarda cifrado (`Nexo.Vault`) y se borra al revocar.

  El backend nunca consulta la Intranet en nombre del estudiante: solo recibe
  lo que su propia app decide subir. Así cada dato almacenado tiene un
  consentimiento asociado y verificable.
  """
  alias Nexo.{Audit, Db, Vault}

  @consents "consents"
  @snapshots "student_snapshots"

  @scope "piloto_desarrollo"
  @modules ~w(horario pagos avance)

  def scope, do: @scope
  def modules, do: @modules

  @doc "Consentimiento vigente del estudiante, o `nil` si nunca aceptó o revocó."
  def current(student_code) do
    Db.conn()
    |> Mongo.find(@consents, %{student_code: student_code, scope: @scope},
      sort: %{granted_at: -1},
      limit: 1
    )
    |> Enum.to_list()
    |> List.first()
    |> case do
      %{"revoked_at" => nil} = consent -> consent
      _ -> nil
    end
  end

  def granted?(student_code), do: current(student_code) != nil

  def module_granted?(student_code, module) do
    case current(student_code) do
      nil -> false
      consent -> module in (consent["modules"] || [])
    end
  end

  @doc """
  Registra la decisión del estudiante. `modules` son los módulos que autoriza
  compartir; una lista vacía equivale a rechazar.
  """
  def grant(student_code, modules, opts \\ []) do
    modules = Enum.filter(modules, &(&1 in @modules))

    if modules == [] do
      revoke(student_code, opts)
    else
      doc = %{
        "student_code" => student_code,
        "scope" => @scope,
        "modules" => modules,
        "terms_version" => Keyword.get(opts, :terms_version, "1"),
        "granted_at" => Db.now(),
        "revoked_at" => nil,
        "ip" => Keyword.get(opts, :ip)
      }

      {:ok, _} = Mongo.insert_one(Db.conn(), @consents, doc)

      # Deja de compartir lo que ya no autorizó.
      Mongo.delete_many(Db.conn(), @snapshots, %{
        student_code: student_code,
        module: %{"$nin" => modules}
      })

      Audit.log(:consent_granted, %{
        actor_type: "student",
        actor_id: student_code,
        student_code: student_code,
        detail: %{modules: modules, scope: @scope},
        ip: Keyword.get(opts, :ip)
      })

      {:ok, doc}
    end
  end

  @doc "Revoca el consentimiento y elimina los datos compartidos."
  def revoke(student_code, opts \\ []) do
    now = Db.now()

    Mongo.update_many(
      Db.conn(),
      @consents,
      %{student_code: student_code, scope: @scope, revoked_at: nil},
      %{"$set" => %{"revoked_at" => now}}
    )

    # Revocar significa que los datos dejan de estar disponibles, no solo que
    # se marque una casilla.
    Mongo.delete_many(Db.conn(), @snapshots, %{student_code: student_code})

    Audit.log(:consent_revoked, %{
      actor_type: "student",
      actor_id: student_code,
      student_code: student_code,
      detail: %{scope: @scope},
      ip: Keyword.get(opts, :ip)
    })

    {:ok, :revoked}
  end

  @doc "Historial completo de decisiones del estudiante (para transparencia)."
  def history(student_code) do
    Db.conn()
    |> Mongo.find(@consents, %{student_code: student_code}, sort: %{granted_at: -1})
    |> Enum.to_list()
  end

  # --- Datos compartidos ---------------------------------------------------

  @doc """
  Guarda un snapshot que sube la app del estudiante. Se rechaza si el módulo
  no está consentido: sin consentimiento no hay dato que guardar.
  """
  def put_snapshot(student_code, module, payload) when is_map(payload) do
    cond do
      module not in @modules ->
        {:error, :invalid_module}

      not module_granted?(student_code, module) ->
        {:error, :not_granted}

      true ->
        encrypted = %BSON.Binary{binary: Vault.encrypt(Jason.encode!(payload))}

        Mongo.update_one(
          Db.conn(),
          @snapshots,
          %{student_code: student_code, module: module},
          %{"$set" => %{"payload" => encrypted, "updated_at" => Db.now()}},
          upsert: true
        )

        {:ok, :saved}
    end
  end

  def put_snapshot(_student_code, _module, _payload), do: {:error, :invalid_payload}

  @doc """
  Lee un snapshot. Vuelve a comprobar el consentimiento en el momento de la
  lectura: una revocación surte efecto inmediato aunque el dato aún existiera.
  """
  def get_snapshot(student_code, module) do
    with true <- module_granted?(student_code, module),
         %{"payload" => %BSON.Binary{binary: data}, "updated_at" => updated_at} <-
           Mongo.find_one(Db.conn(), @snapshots, %{student_code: student_code, module: module}),
         {:ok, json} <- Vault.decrypt(data),
         {:ok, payload} <- Jason.decode(json) do
      {:ok, %{module: module, payload: payload, updated_at: updated_at}}
    else
      false -> {:error, :not_granted}
      nil -> {:error, :not_found}
      _ -> {:error, :not_found}
    end
  end
end
