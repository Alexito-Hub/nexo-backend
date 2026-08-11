defmodule Nexo.Directory.Prototype do
  @moduledoc """
  Generador del directorio de prototipo.

  Existe porque todavía no hay permiso institucional para leer el directorio
  real de la Intranet. Los estudiantes son inventados —ningún dato de persona
  real— pero **con la forma exacta** de lo que devuelve SIGMA: los mismos
  campos, los mismos nombres de curso, unidades con sus evidencias, cuotas con
  mora. Así la app se construye contra la estructura definitiva y el día que
  llegue el permiso se cambia el origen sin tocar pantallas.

  La generación es determinista: la misma semilla produce el mismo directorio,
  de modo que las capturas y las pruebas no cambian entre corridas.
  """
  alias Nexo.{Db, Directory}

  @nombres_m ~w(Diego Luis Jorge Carlos Andre Miguel Renzo Fabricio Sebastian Marco
                Alonso Cristian Kevin Piero Gonzalo Rodrigo Bruno Elmer Yerson Jhon)
  @nombres_f ~w(Ana Maria Lucia Rosa Kiara Valeria Milagros Yesenia Fiorella Camila
                Nayeli Brenda Katherine Roxana Dayana Estefany Jazmin Karol Shirley Elizabeth)
  @segundos ~w(Lucia Isabel Antonio Manuel Jose Alejandra Fernanda Enrique Beatriz Raul)
  @apellidos ~w(Huaman Quispe Ramirez Castro Espinoza Chuquillanqui Meza Ortega Salazar
                Paucar Rojas Flores Vilcahuaman Camarena Ccanto Aliaga Bendezu Poma
                Zarate Lazo Ninahuanca Munarriz Taipe Yupanqui Arroyo Bastidas)

  @escuelas [
    {"Ingeniería de Sistemas y Computación", "Facultad de Ingeniería"},
    {"Ingeniería Civil", "Facultad de Ingeniería"},
    {"Administración y Sistemas", "Facultad de Ciencias Administrativas y Contables"},
    {"Contabilidad", "Facultad de Ciencias Administrativas y Contables"},
    {"Enfermería", "Facultad de Ciencias de la Salud"},
    {"Psicología", "Facultad de Ciencias de la Salud"},
    {"Derecho", "Facultad de Derecho y Ciencias Políticas"}
  ]

  # {código, nombre, créditos, ciclo}
  @cursos [
    {"331101", "MATEMÁTICA BÁSICA", 4.0, 1},
    {"331102", "COMUNICACIÓN", 3.0, 1},
    {"331103", "MÉTODOS DE ESTUDIO", 2.0, 1},
    {"331131", "ANTROPOLOGÍA", 2.0, 2},
    {"331133", "FILOSOFÍA", 2.0, 2},
    {"332123", "ALGEBRA LINEAL", 2.0, 2},
    {"332124", "ANÁLISIS MATEMÁTICO II", 4.0, 3},
    {"332125", "FÍSICA GENERAL", 4.0, 3},
    {"332126", "QUÍMICA GENERAL", 3.0, 3},
    {"332132", "ECONOMÍA Y DESARROLLO", 3.0, 4},
    {"332133", "ESTADÍSTICA GENERAL", 3.0, 4},
    {"332136", "PROGRAMACIÓN II", 4.0, 4},
    {"332137", "SISTEMAS DIGITALES", 3.0, 5},
    {"33213A", "TEORÍA DE SISTEMAS", 3.0, 5},
    {"332135", "PLANEAMIENTO INFORMÁTICO", 3.0, 5},
    {"333141", "BASE DE DATOS I", 4.0, 6},
    {"333142", "REDES Y COMUNICACIONES", 3.0, 6},
    {"333143", "INVESTIGACIÓN OPERATIVA", 3.0, 6},
    {"334138", "TALLER V: DESARROLLO DE APPS I", 4.0, 7},
    {"334144", "INGENIERÍA DE SOFTWARE", 4.0, 7},
    {"334145", "GESTIÓN DE PROYECTOS", 3.0, 7},
    {"334139", "TALLER VI: DESARROLLO DE APPS II", 4.0, 8},
    {"334146", "SEGURIDAD INFORMÁTICA", 3.0, 8},
    {"334147", "INTELIGENCIA DE NEGOCIOS", 3.0, 8}
  ]

  @docentes [
    "MENDOZA CARRION ELSA BEATRIZ",
    "ORTEGA SALAZAR VICTOR HUGO",
    "MEZA VARGAS ZENAIDA",
    "PAREDES CAMARENA JULIO CESAR",
    "SOTO AVILA MARIBEL",
    "QUINTO ANCIETA RAUL",
    "LAZO BALTAZAR GIOVANA"
  ]

  @aulas ["I 302", "I 304", "I 401", "II 105", "II 208", "III 301", "LAB 02", "LAB 05"]
  @horas [
    {"07:00", "08:30"},
    {"08:30", "10:00"},
    {"10:00", "11:30"},
    {"13:00", "14:30"},
    {"14:30", "16:00"},
    {"16:00", "17:30"},
    {"18:00", "19:30"}
  ]
  @dias [
    {"Lunes", 1},
    {"Martes", 2},
    {"Miércoles", 3},
    {"Jueves", 4},
    {"Viernes", 5},
    {"Sábado", 6}
  ]

  @periodo "2026-1"
  @secciones ~w(A1 B1 C1 U1)

  @doc """
  Genera `count` estudiantes listos para insertar. `seed` fija el resultado.
  """
  def generate(count, seed \\ 20_260_809) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    Enum.map(1..count, &student(&1))
  end

  defp student(index) do
    {school, faculty} = Enum.random(@escuelas)
    cycle = Enum.random(1..8)
    female? = rem(index, 2) == 0

    first_name =
      "#{Enum.random(if female?, do: @nombres_f, else: @nombres_m)} #{Enum.random(@segundos)}"

    last_name = "#{Enum.random(@apellidos)} #{Enum.random(@apellidos)}"
    code = code_for(index, cycle)
    courses = courses_for(cycle)
    grades = Enum.map(courses, &course_grades/1)

    average = mean(Enum.map(grades, & &1["promedio"]))
    approved = Enum.count(grades, &(&1["promedio"] >= 10.5))
    credits_total = round(cycle * 20 + Enum.random(-6..6))
    credits_approved = round(credits_total * Enum.random(70..98) / 100)

    %{
      "code" => code,
      "first_name" => first_name,
      "last_name" => last_name,
      "terms" => Directory.terms_for(code, first_name, last_name),
      "dni" => "#{Enum.random(40_000_000..79_999_999)}",
      "email" => email_for(first_name, last_name),
      "phone" => "9#{Enum.random(10_000_000..99_999_999)}",
      "school" => school,
      "faculty" => faculty,
      "cycle" => cycle,
      "plan" => if(cycle > 6, do: "2018", else: "2022"),
      "entry_year" => 2026 - div(cycle + 1, 2),
      "status" => if(average < 10.5, do: "observado", else: "regular"),
      "academic" => %{
        "average" => average,
        "credits_approved" => credits_approved,
        "credits_total" => credits_total,
        "courses_taken" => length(courses),
        "courses_approved" => approved
      },
      "modules" => %{
        "notas" => %{"periodo" => @periodo, "cursos" => grades},
        "horario" => %{"periodo" => @periodo, "clases" => schedule_for(courses)},
        "pagos" => payments(),
        "avance" => progress(cycle, average, credits_total, credits_approved)
      },
      "updated_at" => Db.now()
    }
  end

  # Códigos con la forma real de UPLA: U0 + año de ingreso abreviado + correlativo.
  defp code_for(index, cycle) do
    year = rem(2026 - div(cycle + 1, 2), 100)
    letra = Enum.at(~w(A B C D E F G H), rem(index, 8))
    "U#{String.pad_leading("#{year}", 2, "0")}#{String.pad_leading("#{index}", 3, "0")}#{letra}"
  end

  defp email_for(first_name, last_name) do
    [nombre | _] = String.split(first_name, " ")
    [apellido | _] = String.split(last_name, " ")

    "#{String.downcase(nombre)}.#{String.downcase(apellido)}@upla.edu.pe"
    |> String.replace("é", "e")
    |> String.replace("í", "i")
  end

  defp courses_for(cycle) do
    del_ciclo = Enum.filter(@cursos, fn {_, _, _, c} -> c == cycle end)
    vecinos = Enum.filter(@cursos, fn {_, _, _, c} -> abs(c - cycle) == 1 end)

    (del_ciclo ++ Enum.take_random(vecinos, 3))
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp course_grades({code, name, credits, _cycle}) do
    base = Enum.random(85..175) / 10
    unidades = Enum.map(1..4, &unit("UNIDAD #{&1}", base))
    integral = unit("INTEGRAL", base)
    todas = unidades ++ [integral]
    promedio = mean(Enum.map(todas, & &1["promedio"]))

    %{
      "codigo" => code,
      "nombre" => name,
      "seccion" => Enum.random(@secciones),
      "creditos" => credits,
      "asistencia" => Enum.random(60..100),
      "promedio" => promedio,
      "estado" => if(promedio >= 10.5, do: "Apr.", else: "Des."),
      "detalle" => %{
        "unidades" => todas,
        "sustitutorio" => nil,
        "promedio_final" => promedio,
        "estado" => if(promedio >= 10.5, do: "Apr.", else: "Des.")
      }
    }
  end

  defp unit(nombre, base) do
    conocimiento = clamp(base + Enum.random(-20..20) / 10)
    desempeno = clamp(base + Enum.random(-20..20) / 10)

    %{
      "nombre" => nombre,
      "peso" => 20.0,
      "promedio" => mean([conocimiento, desempeno]),
      "evidencias" => [
        %{"tipo" => "EVIDENCIA DE CONOCIMIENTO", "nota" => conocimiento},
        %{"tipo" => "EVIDENCIA DE DESEMPEÑO", "nota" => desempeno}
      ]
    }
  end

  defp schedule_for(courses) do
    courses
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_code, name, _credits, _cycle}, i} ->
      {dia, dia_num} = Enum.at(@dias, rem(i, length(@dias)))
      {inicio, fin} = Enum.at(@horas, rem(i, length(@horas)))
      aula = Enum.random(@aulas)
      docente = Enum.random(@docentes)
      seccion = Enum.random(@secciones)

      for tipo <- ["Teoria", "Practica"] do
        %{
          "curso" => name,
          "seccion" => seccion,
          "dia" => dia,
          "dia_num" => dia_num,
          "inicio" => if(tipo == "Teoria", do: inicio, else: fin),
          "fin" => if(tipo == "Teoria", do: fin, else: siguiente_hora(fin)),
          "aula" => "PABELLON I - #{aula} - AFORO: 50",
          "sede" => "CAMPUS UNIVERSITARIO",
          "tipo" => tipo,
          "docente" => docente
        }
      end
    end)
  end

  defp siguiente_hora(fin) do
    case Enum.find_index(@horas, fn {inicio, _} -> inicio == fin end) do
      nil -> fin
      idx -> @horas |> Enum.at(idx) |> elem(1)
    end
  end

  defp payments do
    vencidas =
      for n <- 1..Enum.random(0..2)//1 do
        monto = Enum.random(1200..1600) / 10

        %{
          "descripcion" => "CUOTA 0#{n} Periodo #{@periodo}",
          "vencimiento" => "#{String.pad_leading("#{Enum.random(1..28)}", 2, "0")}-06-2026",
          "moneda" => "S/.",
          "monto" => monto,
          "mora" => Enum.random(0..40) / 100,
          "total" => monto
        }
      end

    pendientes =
      for n <- 3..(3 + Enum.random(0..2)) do
        monto = Enum.random(1200..1600) / 10

        %{
          "descripcion" => "CUOTA 0#{n} Periodo #{@periodo}",
          "vencimiento" =>
            "#{String.pad_leading("#{Enum.random(1..28)}", 2, "0")}-#{Enum.random(8..11)}-2026",
          "moneda" => "S/.",
          "monto" => monto,
          "mora" => 0.0,
          "total" => monto
        }
      end

    %{"vencidas" => vencidas, "pendientes" => pendientes, "tasas" => []}
  end

  defp progress(cycle, average, credits_total, credits_approved) do
    ciclos =
      for n <- 1..cycle do
        %{
          "anio" => 2026 - div(cycle - n + 1, 2),
          "periodo" => if(rem(n, 2) == 1, do: 1, else: 2),
          "promedio" => clamp(average + Enum.random(-25..25) / 10)
        }
      end

    %{
      "promedios_por_ciclo" => ciclos,
      "promedio_acumulado" => mean(Enum.map(ciclos, & &1["promedio"])),
      "cursos_llevados" => credits_total,
      "cursos_aprobados" => credits_approved
    }
  end

  defp clamp(value), do: value |> max(2.0) |> min(20.0) |> Float.round(2)

  defp mean([]), do: 0.0
  defp mean(values), do: Float.round(Enum.sum(values) / length(values), 2)
end
