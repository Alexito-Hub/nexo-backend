defmodule NexoWeb.DirectoryController do
  use NexoWeb, :controller

  alias Nexo.{Audit, Directory, DirectoryAccess}

  @doc """
  Si esta cuenta puede entrar al directorio. La app lo consulta al arrancar
  para decidir si muestra el apartado: es la única pregunta que el backend
  contesta sin exigir acceso previo.
  """
  def access(conn, _params) do
    actor = actor(conn)
    role = DirectoryAccess.role(actor.code)

    json(conn, %{
      acceso: role != nil,
      rol: role && to_string(role),
      codigo: actor.code,
      tipo: to_string(actor.type)
    })
  end

  def index(conn, params) do
    page =
      Directory.list(
        query: params["q"],
        school: params["escuela"],
        cycle: to_int(params["ciclo"]),
        page: to_int(params["pagina"]) || 1,
        limit: to_int(params["limite"]) || 25
      )

    json(conn, %{
      estudiantes: Enum.map(page.students, &summary_view/1),
      total: page.total,
      pagina: page.page,
      paginas: page.pages
    })
  end

  def schools(conn, _params) do
    json(conn, %{escuelas: Directory.schools()})
  end

  def show(conn, %{"codigo" => codigo}) do
    case Directory.get(codigo) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_encontrado"})

      record ->
        actor = actor(conn)

        # Abrir la ficha de una persona se audita nominalmente: es el acceso
        # que hay que poder justificar después.
        Audit.log(:directory_record_read, %{
          actor_type: to_string(actor.type),
          actor_id: actor.code,
          student_code: codigo,
          detail: %{rol: to_string(conn.assigns[:directory_role])},
          ip: client_ip(conn)
        })

        json(conn, %{estudiante: record_view(record)})
    end
  end

  # --- Administración del acceso -------------------------------------------

  def grants(conn, _params) do
    json(conn, %{
      accesos: Enum.map(DirectoryAccess.list(), &grant_view/1),
      administradores: DirectoryAccess.system_admins()
    })
  end

  def set_grant(conn, %{"codigo" => codigo} = params) do
    estado = params["estado"] || "activo"
    actor = actor(conn)

    case DirectoryAccess.set_status(codigo, estado, actor.code,
           note: params["nota"],
           ip: client_ip(conn)
         ) do
      {:ok, grant} ->
        json(conn, %{acceso: grant_view(grant)})

      {:error, :invalid_status} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "estado_invalido"})
    end
  end

  def set_grant(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  # --- Apoderados (administración) -----------------------------------------

  def guardians(conn, _params) do
    json(conn, %{apoderados: Enum.map(Nexo.Guardians.list(), &guardian_view/1)})
  end

  @doc """
  Vincula (o actualiza) a un apoderado con sus estudiantes.

  El PIN generado se devuelve **una sola vez**, aquí: no se guarda en claro en
  ninguna parte, así que si se pierde hay que restablecerlo.
  """
  def set_guardian(conn, %{"dni" => dni} = params) do
    actor = actor(conn).code

    if params["estado"] == "revocado" do
      {:ok, guardian} = Nexo.Guardians.revoke(dni, actor: actor, ip: client_ip(conn))
      json(conn, %{apoderado: guardian_view(guardian)})
    else
      case Nexo.Guardians.link(dni, params["estudiantes"] || [],
             name: params["nombre"],
             reset_pin: params["nuevo_pin"] == true,
             actor: actor,
             ip: client_ip(conn)
           ) do
        {:ok, guardian, pin} ->
          json(conn, %{apoderado: guardian_view(guardian), pin: pin})

        {:error, :invalid_dni} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "dni_invalido"})
      end
    end
  end

  def set_guardian(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "parametros_invalidos"})
  end

  defp guardian_view(g) do
    %{
      dni: g["dni"],
      nombre: g["name"],
      estudiantes: g["students"] || [],
      estado: g["status"],
      bloqueado: Nexo.Guardians.locked?(g),
      ultimo_acceso: g["last_access_at"],
      actualizado_en: g["updated_at"]
    }
  end

  # --- Vistas ---------------------------------------------------------------

  def summary_view(s) do
    %{
      codigo: s.code,
      nombres: s.first_name,
      apellidos: s.last_name,
      escuela: s.school,
      ciclo: s.cycle,
      condicion: s.status,
      promedio: s.average,
      creditos_aprobados: s.credits_approved,
      creditos_totales: s.credits_total
    }
  end

  def record_view(r) do
    r
    |> summary_view()
    |> Map.merge(%{
      dni: r.dni,
      correo: r.email,
      telefono: r.phone,
      facultad: r.faculty,
      plan: r.plan,
      anio_ingreso: r.entry_year,
      academico: r.academic,
      modulos: r.modules,
      actualizado: r.updated_at
    })
  end

  defp grant_view(grant) do
    %{
      codigo: grant["code"],
      estado: grant["status"],
      nota: grant["note"],
      concedido_por: grant["granted_by"],
      concedido_en: grant["granted_at"],
      revocado_en: grant["revoked_at"],
      actualizado_en: grant["updated_at"]
    }
  end

  defp actor(conn), do: conn.assigns.current_actor

  defp to_int(nil), do: nil

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp to_int(value) when is_integer(value), do: value

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
