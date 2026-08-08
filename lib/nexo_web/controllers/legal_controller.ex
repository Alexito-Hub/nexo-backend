defmodule NexoWeb.LegalController do
  use NexoWeb, :controller

  @moduledoc """
  Sirve la política de privacidad como página pública. La Microsoft Store, la
  Play Store y App Store exigen una URL de política de privacidad accesible.
  """

  def privacy(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, privacy_html())
  end

  # El texto describe lo que la app REALMENTE hace: credenciales y datos
  # académicos viven solo en el dispositivo y las peticiones van directas a la
  # UPLA. Debe mantenerse fiel al comportamiento de la app.
  defp privacy_html do
    """
    <!doctype html>
    <html lang="es">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Política de Privacidad — Nexo</title>
      <style>
        :root { color-scheme: light dark; }
        body { font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
               max-width: 760px; margin: 0 auto; padding: 32px 20px 80px;
               line-height: 1.6; }
        h1 { font-size: 1.7rem; letter-spacing: -0.5px; }
        h2 { font-size: 1.15rem; margin-top: 2rem; }
        code { background: rgba(128,128,128,.15); padding: 1px 5px; border-radius: 4px; }
        .muted { opacity: .7; font-size: .9rem; }
        .box { border: 1px solid rgba(128,128,128,.3); border-radius: 12px;
               padding: 14px 18px; margin: 16px 0; }
      </style>
    </head>
    <body>
      <h1>Política de Privacidad de Nexo</h1>
      <p class="muted">Última actualización: agosto de 2026.</p>

      <div class="box">
        Nexo es una aplicación <strong>independiente y no oficial</strong>, creada
        por y para estudiantes. <strong>No está afiliada ni respaldada por la
        Universidad Peruana Los Andes (UPLA)</strong>. La información oficial es
        siempre la de los sistemas de la universidad.
      </div>

      <h2>1. Qué datos usa Nexo y dónde se guardan</h2>
      <p>
        Para mostrarte tu información académica, Nexo usa tus credenciales de la
        UPLA. <strong>Tus credenciales y tus datos académicos se guardan
        únicamente en tu dispositivo.</strong> Nexo no los envía a servidores
        propios ni a terceros: las peticiones van directamente a los servicios
        de la UPLA (SIGMA e Intranet), igual que el portal oficial.
      </p>
      <ul>
        <li>Credenciales de acceso (usuario y contraseña UPLA).</li>
        <li>Datos académicos: horario, notas, pagos, avance y perfil.</li>
      </ul>
      <p>
        Todo esto permanece en el almacenamiento local de tu dispositivo. Al
        cerrar sesión se borran las credenciales y la caché.
      </p>

      <h2>2. Con quién se comparte</h2>
      <p>
        Con nadie. Nexo no vende, alquila ni transfiere tu información a terceros.
        La comunicación ocurre solo entre tu dispositivo y los servidores de la
        UPLA.
      </p>

      <h2>3. Permisos</h2>
      <p>
        Nexo usa el acceso a internet para conectarse a los servicios de la UPLA
        y, opcionalmente, notificaciones locales para recordarte clases y pagos.
        Las notificaciones se generan en tu propio dispositivo.
      </p>

      <h2>4. Seguridad</h2>
      <p>
        La comunicación con la UPLA usa HTTPS. El almacenamiento local no está
        cifrado a nivel de sistema, por lo que te recomendamos usar Nexo solo en
        dispositivos de tu confianza.
      </p>

      <h2>5. Tus derechos</h2>
      <p>
        Como tus datos viven en tu dispositivo, tú tienes el control directo:
        puedes cerrar sesión para borrarlos en cualquier momento. Para cualquier
        duda sobre el tratamiento de tus datos, escríbenos desde la sección de
        soporte de la app.
      </p>

      <h2>6. Menores de edad</h2>
      <p>
        Nexo está dirigida a estudiantes universitarios. Si eres menor de edad,
        usa la aplicación con el conocimiento de tus padres o tutores.
      </p>

      <h2>7. Cambios en esta política</h2>
      <p>
        Si esta política cambia, se actualizará esta página y, cuando el cambio
        sea relevante, se te avisará dentro de la app.
      </p>

      <h2>8. Contacto</h2>
      <p>
        Responsable del proyecto: <strong>equipo de Nexo</strong>.
        Contacto: a través de la sección de soporte de la aplicación.
      </p>

      <p class="muted">
        Nexo · Proyecto estudiantil independiente. No afiliado a la UPLA.
      </p>
    </body>
    </html>
    """
  end
end
