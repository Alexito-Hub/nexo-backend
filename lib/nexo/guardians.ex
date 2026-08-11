defmodule Nexo.Guardians do
  @moduledoc """
  Apoderados: padres, madres o tutores que consultan la ficha de su hijo o hija
  (colección `guardians`).

  No tienen cuenta en SIGMA, así que no pueden entrar por el camino normal. La
  llave es **DNI + PIN**: el DNI identifica y el PIN autentica. El DNI solo no
  basta a propósito —lo conoce cualquiera que tenga el documento delante y al
  otro lado hay notas y deudas de un estudiante—, y por eso también existe el
  bloqueo por intentos fallidos: seis dígitos se adivinan a fuerza bruta en
  minutos si nadie lo impide.

  El PIN se guarda derivado con PBKDF2-SHA256 y sal propia; en claro solo
  existe en el momento en que un administrador crea el vínculo y se lo entrega
  al apoderado.

  Un documento por DNI, con la lista de estudiantes que puede ver: un padre con
  dos hijos entra una vez y elige.
  """
  alias Nexo.{Audit, Db}

  @collection "guardians"
  @iterations 120_000
  @pin_digits 6
  @max_attempts 5
  @lock_minutes 15

  def collection, do: @collection

  def get(id) when is_binary(id) do
    case Db.parse_id(id) do
      {:ok, oid} -> Mongo.find_one(Db.conn(), @collection, %{_id: oid})
      :error -> nil
    end
  end

  def get_by_dni(dni), do: Mongo.find_one(Db.conn(), @collection, %{dni: dni})

  def list do
    Db.conn()
    |> Mongo.find(@collection, %{}, sort: %{updated_at: -1})
    |> Enum.to_list()
  end

  def students(guardian), do: guardian["students"] || []

  def linked?(guardian, code), do: code in students(guardian)

  def active?(%{"status" => "activo"}), do: true
  def active?(_), do: false

  @doc """
  Crea o actualiza el vínculo de un apoderado con uno o más estudiantes.

  Devuelve `{:ok, doc, pin}` con el PIN **en claro** cuando se genera uno
  nuevo (alta o restablecimiento), y `{:ok, doc, nil}` cuando solo se cambió la
  lista de estudiantes. Es la única vez que ese PIN es legible.
  """
  def link(dni, student_codes, opts \\ [])

  def link(dni, student_codes, opts) when is_binary(dni) and dni != "" do
    codes = student_codes |> List.wrap() |> Enum.map(&String.trim/1) |> Enum.uniq()
    existing = get_by_dni(dni)
    reset? = existing == nil or Keyword.get(opts, :reset_pin, false)
    pin = if reset?, do: generate_pin(), else: nil
    now = Db.now()

    updates =
      %{
        "students" => codes,
        "name" => Keyword.get(opts, :name) || (existing && existing["name"]),
        "status" => "activo",
        "updated_at" => now,
        "updated_by" => Keyword.get(opts, :actor)
      }
      |> Map.merge(if(reset?, do: pin_fields(pin, now), else: %{}))

    {:ok, _} =
      Mongo.update_one(
        Db.conn(),
        @collection,
        %{dni: dni},
        %{
          "$set" => updates,
          "$setOnInsert" => %{"dni" => dni, "inserted_at" => now}
        },
        upsert: true
      )

    Audit.log(:guardian_linked, %{
      actor_type: "admin",
      actor_id: Keyword.get(opts, :actor),
      detail: %{dni: dni, estudiantes: codes, pin_nuevo: reset?},
      ip: Keyword.get(opts, :ip)
    })

    {:ok, get_by_dni(dni), pin}
  end

  def link(_dni, _codes, _opts), do: {:error, :invalid_dni}

  def revoke(dni, opts \\ []) do
    now = Db.now()

    {:ok, _} =
      Mongo.update_one(Db.conn(), @collection, %{dni: dni}, %{
        "$set" => %{
          "status" => "revocado",
          "revoked_at" => now,
          "updated_at" => now,
          "updated_by" => Keyword.get(opts, :actor)
        }
      })

    Audit.log(:guardian_revoked, %{
      actor_type: "admin",
      actor_id: Keyword.get(opts, :actor),
      detail: %{dni: dni},
      ip: Keyword.get(opts, :ip)
    })

    {:ok, get_by_dni(dni)}
  end

  @doc """
  Verifica DNI + PIN.

  Devuelve `{:error, :locked}` cuando la cuenta está bloqueada por intentos
  fallidos, y `{:error, :invalid}` tanto si el DNI no existe como si el PIN es
  incorrecto: distinguirlos permitiría averiguar qué DNIs están registrados.
  """
  def verify(dni, pin) when is_binary(dni) and is_binary(pin) do
    case get_by_dni(dni) do
      nil ->
        {:error, :invalid}

      guardian ->
        cond do
          not active?(guardian) -> {:error, :invalid}
          locked?(guardian) -> {:error, :locked}
          correct_pin?(guardian, pin) -> {:ok, on_success(guardian)}
          true -> on_failure(guardian)
        end
    end
  end

  def verify(_dni, _pin), do: {:error, :invalid}

  def locked?(%{"locked_until" => %DateTime{} = until}) do
    DateTime.compare(until, Db.now()) == :gt
  end

  def locked?(_guardian), do: false

  # --- Interno -------------------------------------------------------------

  defp correct_pin?(%{"pin_hash" => %BSON.Binary{binary: stored}} = guardian, pin) do
    %BSON.Binary{binary: salt} = guardian["pin_salt"]
    iterations = guardian["pin_iterations"] || @iterations
    :crypto.hash_equals(stored, derive(pin, salt, iterations))
  end

  defp correct_pin?(_guardian, _pin), do: false

  defp on_success(%{"_id" => id} = guardian) do
    now = Db.now()

    Mongo.update_one(Db.conn(), @collection, %{_id: id}, %{
      "$set" => %{"failed_attempts" => 0, "last_access_at" => now},
      "$unset" => %{"locked_until" => ""}
    })

    Map.merge(guardian, %{"failed_attempts" => 0, "last_access_at" => now})
  end

  defp on_failure(%{"_id" => id} = guardian) do
    attempts = (guardian["failed_attempts"] || 0) + 1
    locked = attempts >= @max_attempts

    updates = %{"failed_attempts" => attempts, "updated_at" => Db.now()}

    updates =
      if locked,
        do:
          Map.put(
            updates,
            "locked_until",
            DateTime.add(Db.now(), @lock_minutes * 60, :second)
          ),
        else: updates

    Mongo.update_one(Db.conn(), @collection, %{_id: id}, %{"$set" => updates})

    if locked, do: {:error, :locked}, else: {:error, :invalid}
  end

  defp pin_fields(pin, now) do
    salt = :crypto.strong_rand_bytes(16)

    %{
      "pin_hash" => %BSON.Binary{binary: derive(pin, salt, @iterations)},
      "pin_salt" => %BSON.Binary{binary: salt},
      "pin_iterations" => @iterations,
      "pin_set_at" => now,
      "failed_attempts" => 0,
      "locked_until" => nil
    }
  end

  defp derive(pin, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, pin, salt, iterations, 32)
  end

  # Aleatoriedad criptográfica y sin sesgo (se descartan los bytes que no
  # reparten los diez dígitos por igual). Se genera como cadena para no perder
  # los ceros a la izquierda.
  defp generate_pin do
    Enum.map_join(1..@pin_digits, fn _ -> Integer.to_string(random_digit()) end)
  end

  defp random_digit do
    <<byte>> = :crypto.strong_rand_bytes(1)
    if byte < 250, do: rem(byte, 10), else: random_digit()
  end
end
