# Nexo · Backend

API en Elixir/Phoenix para el **acceso especial docente** de Nexo.
Diseño y decisiones: [`../nexo/docs/plan-backend-docentes.md`](../nexo/docs/plan-backend-docentes.md).

| | |
|---|---|
| Runtime | Elixir 1.19 · OTP 28 · Phoenix 1.8 |
| Base de datos | MongoDB (Atlas) |
| Despliegue | Release OTP en contenedor (`Dockerfile` multi-stage) |

## Alcance actual (fases F1 y F2)

- **Login docente** verificado contra SIGMA (`Login/SesionV1`). La contraseña
  UPLA **no se almacena**: se usa una sola vez para confirmar identidad y rol.
  Del login se conserva el *token* de sesión de SIGMA, **cifrado con AES-256-GCM**
  (`Nexo.Vault`), que es lo que permite consultar en nombre del docente.
- **Allowlist en dos pasos.** Todo docente nace `pendiente` — puede autenticarse
  pero no ver datos — hasta que un administrador lo pasa a `autorizado`.
  Suspenderlo revoca sus sesiones de inmediato.
- **Tokens propios.** Acceso firmado de 15 minutos y refresh opaco de 30 días
  con rotación: del refresh solo se guarda su hash, y el usado queda revocado.
- **Datos académicos acotados.** Un docente solo alcanza **sus** secciones:
  cada consulta se valida contra su lista de secciones antes de salir a la red
  y los intentos sobre secciones ajenas se rechazan y se registran. No nos
  apoyamos en que SIGMA también lo limite.
- **Auditoría.** Cada acción sensible se registra con actor, IP y fecha; las
  lecturas de datos de un alumno quedan además asociadas a su código
  (requisito de la Ley N.º 29733 de protección de datos personales).

## Puesta en marcha

```bash
cp .env.example .env    # completa MONGODB_URI, MONGODB_URI_TEST y ADMIN_API_KEY
mix setup               # dependencias
mix phx.server          # http://localhost:4000
```

Los índices de MongoDB (unicidad, TTL de refresh tokens, orden de auditoría) se
crean solos al arrancar. No hay migraciones que ejecutar.

```bash
mix test        # suite completa
mix precommit   # compila sin warnings, formatea y corre los tests
```

> Los tests usan la base indicada en `MONGODB_URI_TEST` y un SIGMA simulado:
> **nunca** tocan datos reales ni los servidores de la universidad. La suite
> limpia sus colecciones en cada corrida, así que esa URI debe apuntar a una
> base distinta de la de desarrollo.

## Docker

```bash
docker compose up --build
```

Compose lee las variables de `.env` y exige `SECRET_KEY_BASE`
(`mix phx.gen.secret`). No se levanta ningún motor de base de datos local: la
persistencia vive en Atlas.

## API

| Método | Ruta | Autenticación |
|---|---|---|
| `GET` | `/health` | — |
| `POST` | `/api/v1/auth/teacher/login` · `{usuario, clave}` | — |
| `POST` | `/api/v1/auth/refresh` · `{refresh_token}` | — |
| `GET` | `/api/v1/teacher/me` | `Authorization: Bearer` |
| `GET` | `/api/v1/teacher/sections` | Bearer · autorizado |
| `GET` | `/api/v1/teacher/sections/:cle_auto/students` | Bearer · autorizado |
| `GET` | `/api/v1/teacher/sections/:cle_auto/grades?unidad=1` | Bearer · autorizado |
| `GET` | `/api/v1/teacher/sections/:cle_auto/students/:codigo/grades` | Bearer · autorizado |
| `GET` | `/api/v1/admin/teachers` | `x-admin-key` |
| `PUT` | `/api/v1/admin/teachers/:id/status` · `{estado}` | `x-admin-key` |
| `GET` | `/api/v1/admin/audit?limit=100` | `x-admin-key` |

`estado` ∈ `pendiente` · `autorizado` · `suspendido`.

## Configuración

Ningún secreto se versiona. `.env` está en `.gitignore` y excluido del contexto
de build de Docker; `.env.example` documenta las variables.

| Variable | Uso |
|---|---|
| `MONGODB_URI` | Conexión a MongoDB (obligatoria) |
| `MONGODB_URI_TEST` | Base de pruebas (solo `MIX_ENV=test`) |
| `ADMIN_API_KEY` | Cabecera `x-admin-key` del área de administración |
| `SECRET_KEY_BASE` | Firma de tokens y cookies (solo producción) |
| `SIGMA_BASE_URL` | Sobrescribe el host de SIGMA |
| `PHX_HOST`, `PORT` | Host público y puerto |

En producción el arranque falla si falta `MONGODB_URI`, `ADMIN_API_KEY` o
`SECRET_KEY_BASE`: es preferible no levantar el servicio a levantarlo con
valores por defecto inseguros.

Respuestas de error propias de los datos académicos:

| Estado | `error` | Significado |
|---|---|---|
| `403` | `no_autorizado` | El docente aún no está en la allowlist |
| `403` | `seccion_ajena` | La sección no le pertenece (queda auditado) |
| `401` | `sesion_sigma_expirada` | Caducó el token de SIGMA: reiniciar sesión |

## Siguientes fases

- **F3** — Consentimiento del estudiante desde la app y snapshots de horario,
  pagos y avance académico.
- **F4** — Notificaciones y avisos por sección.
