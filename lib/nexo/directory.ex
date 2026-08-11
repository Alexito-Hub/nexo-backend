defmodule Nexo.Directory do
  @moduledoc """
  Consulta del directorio de estudiantes (colección `directory_students`).

  **Sobre el origen de los datos.** El directorio definitivo es SIGMA/Intranet;
  el backend solo verifica el acceso. Mientras no haya permiso institucional
  para consultarlo, esta colección hace de fuente: se llena con
  `mix nexo.directory` y tiene exactamente la forma que tendrá lo que devuelva
  la Intranet, para que cambiar el origen sea sustituir estas dos funciones y
  nada más.

  Las consultas están pensadas para no leer de más:

  * la lista devuelve una **proyección** con lo que se ve en pantalla, nunca
    los módulos completos (que son la mayor parte del documento);
  * la búsqueda va contra `terms`, un arreglo de tokens en minúscula con
    índice multiclave, de modo que un prefijo (`"ram"`) se resuelve con el
    índice en vez de recorriendo la colección;
  * la paginación es por `skip`/`limit` con orden estable por apellido.
  """
  alias Nexo.Db

  @collection "directory_students"
  @max_limit 100

  # Lo que necesita una fila de la lista. Todo lo demás (horario, notas,
  # pagos, avance) solo se lee al abrir la ficha.
  @summary %{
    code: 1,
    first_name: 1,
    last_name: 1,
    school: 1,
    cycle: 1,
    status: 1,
    "academic.average": 1,
    "academic.credits_approved": 1,
    "academic.credits_total": 1
  }

  @doc """
  Página del directorio. Opciones: `:query` (prefijo de nombre o código),
  `:school`, `:cycle`, `:page` (1 en adelante) y `:limit`.
  """
  def list(opts \\ []) do
    filter = filter_from(opts)
    limit = opts |> Keyword.get(:limit, 25) |> normalize_limit()
    page = opts |> Keyword.get(:page, 1) |> max(1)

    students =
      Db.conn()
      |> Mongo.find(@collection, filter,
        projection: @summary,
        sort: %{last_name: 1, first_name: 1},
        skip: (page - 1) * limit,
        limit: limit
      )
      |> Enum.map(&summary/1)

    total = Mongo.count_documents!(Db.conn(), @collection, filter)

    %{
      students: students,
      total: total,
      page: page,
      pages: ceil_div(total, limit)
    }
  end

  @doc "Ficha completa de un estudiante, o `nil`."
  def get(code) do
    case Mongo.find_one(Db.conn(), @collection, %{code: code}) do
      nil -> nil
      doc -> record(doc)
    end
  end

  @doc "Escuelas presentes en el directorio, para el filtro de la app."
  def schools do
    Db.conn()
    |> Mongo.distinct!(@collection, "school", %{})
    |> Enum.sort()
  end

  @doc "Cuántos estudiantes hay cargados."
  def count, do: Mongo.count_documents!(Db.conn(), @collection, %{})

  @doc """
  Reemplaza el directorio por el conjunto dado. Se usa desde
  `mix nexo.directory`; en cuanto la fuente sea la Intranet desaparece.
  """
  def replace_all(students) do
    Mongo.delete_many(Db.conn(), @collection, %{})

    students
    |> Enum.chunk_every(200)
    |> Enum.each(&Mongo.insert_many(Db.conn(), @collection, &1))

    :ok
  end

  @doc "Tokens de búsqueda de un estudiante: código y cada parte de su nombre."
  def terms_for(code, first_name, last_name) do
    "#{code} #{first_name} #{last_name}"
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.uniq()
  end

  # --- Interno -------------------------------------------------------------

  defp filter_from(opts) do
    %{}
    |> put_if(:school, Keyword.get(opts, :school))
    |> put_if(:cycle, Keyword.get(opts, :cycle))
    |> put_query(Keyword.get(opts, :query))
  end

  defp put_if(filter, _key, nil), do: filter
  defp put_if(filter, _key, ""), do: filter
  defp put_if(filter, key, value), do: Map.put(filter, key, value)

  defp put_query(filter, nil), do: filter

  defp put_query(filter, query) do
    case String.trim(query) do
      "" ->
        filter

      q ->
        # Anclado al inicio del token para que el índice multiclave sirva:
        # un `$regex` sin ancla obligaría a recorrer la colección entera.
        prefix = "^" <> Regex.escape(String.downcase(q))
        Map.put(filter, :terms, %{"$regex" => prefix})
    end
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0,
    do: min(limit, @max_limit)

  defp normalize_limit(_), do: 25

  defp ceil_div(_total, 0), do: 0
  defp ceil_div(total, limit), do: div(total + limit - 1, limit)

  defp summary(doc) do
    academic = doc["academic"] || %{}

    %{
      code: doc["code"],
      first_name: doc["first_name"],
      last_name: doc["last_name"],
      school: doc["school"],
      cycle: doc["cycle"],
      status: doc["status"],
      average: academic["average"],
      credits_approved: academic["credits_approved"],
      credits_total: academic["credits_total"]
    }
  end

  defp record(doc) do
    doc
    |> summary()
    |> Map.merge(%{
      dni: doc["dni"],
      email: doc["email"],
      phone: doc["phone"],
      faculty: doc["faculty"],
      plan: doc["plan"],
      entry_year: doc["entry_year"],
      academic: doc["academic"] || %{},
      modules: doc["modules"] || %{},
      updated_at: doc["updated_at"]
    })
  end
end
