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
  # UPLA (o a Microsoft 365 si el usuario conecta esa integración opcional).
  # Debe mantenerse fiel al comportamiento de la app.
  defp privacy_html do
    """
    <!doctype html>
    <html lang="es">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Política de Privacidad — Nexo</title>
      <style>
        :root { color-scheme: light dark; --line: rgba(128,128,128,.28); }
        * { box-sizing: border-box; }
        body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
               max-width: 780px; margin: 0 auto; padding: 40px 22px 96px;
               line-height: 1.65; font-size: 16px; }
        header { border-bottom: 1px solid var(--line); padding-bottom: 20px; margin-bottom: 8px; }
        h1 { font-size: 1.9rem; letter-spacing: -0.6px; margin: 0 0 6px; }
        h2 { font-size: 1.2rem; margin: 2.4rem 0 .4rem; letter-spacing: -0.3px; }
        h3 { font-size: 1rem; margin: 1.4rem 0 .3rem; }
        p, li { margin: .5rem 0; }
        ul { padding-left: 1.3rem; }
        a { color: inherit; text-decoration: underline; text-underline-offset: 2px; }
        code { background: rgba(128,128,128,.15); padding: 1px 6px; border-radius: 5px;
               font-size: .92em; }
        .muted { opacity: .68; font-size: .9rem; }
        .box { border: 1px solid var(--line); border-radius: 14px; padding: 16px 20px;
               margin: 20px 0; }
        .toc a { display: inline-block; margin: 2px 10px 2px 0; font-size: .92rem; }
        table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: .95rem; }
        th, td { border: 1px solid var(--line); padding: 8px 10px; text-align: left;
                 vertical-align: top; }
        th { background: rgba(128,128,128,.08); }
        footer { margin-top: 3rem; padding-top: 18px; border-top: 1px solid var(--line); }
      </style>
    </head>
    <body>
      <header>
        <h1>Política de Privacidad de Nexo</h1>
        <p class="muted">Versión 3 · Vigente desde el 10 de agosto de 2026.</p>
      </header>

      <div class="box">
        <strong>Nexo es una aplicación independiente y no oficial</strong>, creada
        por y para estudiantes. <strong>No está afiliada, patrocinada ni
        respaldada por la Universidad Peruana Los Andes (UPLA)</strong>, ni por
        Microsoft. Las marcas mencionadas pertenecen a sus respectivos titulares
        y se usan solo con fines descriptivos. La información oficial es siempre
        la que publican los sistemas de la universidad.
      </div>

      <p>
        Esta Política explica qué datos personales trata la aplicación Nexo
        (la «App»), con qué finalidad, sobre qué base legal y qué derechos tienes.
        Se rige por la Ley N.º 29733, Ley de Protección de Datos Personales del
        Perú, y su Reglamento. Al usar la App aceptas lo aquí descrito.
      </p>

      <nav class="toc">
        <a href="#responsable">1. Responsable</a>
        <a href="#modelo">2. Cómo funciona la App</a>
        <a href="#datos">3. Datos que se tratan</a>
        <a href="#finalidad">4. Finalidad y base legal</a>
        <a href="#terceros">5. Terceros y transferencias</a>
        <a href="#conservacion">6. Conservación y borrado</a>
        <a href="#seguridad">7. Seguridad</a>
        <a href="#permisos">8. Permisos</a>
        <a href="#derechos">9. Tus derechos</a>
        <a href="#menores">10. Menores</a>
        <a href="#cambios">11. Cambios</a>
        <a href="#contacto">12. Contacto</a>
      </nav>

      <h2 id="responsable">1. Responsable del tratamiento</h2>
      <p>
        El responsable del proyecto y del tratamiento de los datos es el equipo
        desarrollador de Nexo, con domicilio en Huancayo, Perú. Puedes contactarlo
        en <a href="mailto:alessandrovillogas@outlook.es">alessandrovillogas@outlook.es</a>
        o por WhatsApp al <strong>+51 907 924 307</strong>, así como desde la
        sección «Soporte» dentro de la App.
      </p>

      <h2 id="modelo">2. Cómo funciona la App (principio de diseño)</h2>
      <p>
        Nexo es, en esencia, un <strong>cliente que reorganiza tu propia
        información</strong> de los sistemas de la UPLA de forma más clara.
        <strong>Tus credenciales y tus datos académicos se guardan únicamente en
        tu dispositivo</strong> y las peticiones viajan directamente entre tu
        dispositivo y los servidores de la UPLA, igual que lo haría el portal
        oficial.
      </p>
      <p>
        Hay <strong>dos excepciones</strong>, y conviene que las conozcas:
      </p>
      <ul>
        <li>
          El apartado <strong>«Estudiantes»</strong>, un directorio al que solo
          entran las cuentas autorizadas. Para comprobar esa autorización, tu
          usuario y tu contraseña viajan <em>una sola vez</em> al servidor de
          Nexo, que los verifica contra SIGMA y <strong>no los almacena</strong>;
          a partir de ahí se usa una sesión temporal. Cada consulta a la ficha
          de un estudiante queda registrada (ver sección 4).
        </li>
        <li>
          La integración con <strong>Microsoft 365</strong>, si tú decides
          conectarla (ver sección 5).
        </li>
      </ul>
      <p>
        Fuera de esos dos casos, la App no envía tu información a servidores
        propios de Nexo ni a terceros.
      </p>

      <h2 id="datos">3. Datos que se tratan</h2>
      <table>
        <tr><th>Categoría</th><th>Ejemplos</th><th>Dónde se guarda</th></tr>
        <tr>
          <td>Credenciales de acceso</td>
          <td>Usuario/código o DNI y contraseña de la UPLA</td>
          <td>Solo en tu dispositivo (almacenamiento local de la App)</td>
        </tr>
        <tr>
          <td>Datos académicos</td>
          <td>Perfil, horario, notas, avance curricular, asistencia</td>
          <td>Solo en tu dispositivo (caché local)</td>
        </tr>
        <tr>
          <td>Datos económicos</td>
          <td>Cuotas, pagos, tasas e historial de pagos</td>
          <td>Solo en tu dispositivo (caché local)</td>
        </tr>
        <tr>
          <td>Sesión de Microsoft 365 <em>(opcional)</em></td>
          <td>Token de acceso, tus clases y tareas de Teams</td>
          <td>Token en tu dispositivo; los datos los provee Microsoft</td>
        </tr>
        <tr>
          <td>Preferencias de la App</td>
          <td>Idioma, tema, ajustes de notificaciones</td>
          <td>Solo en tu dispositivo</td>
        </tr>
        <tr>
          <td>Acceso al directorio <em>(solo cuentas autorizadas)</em></td>
          <td>Tu código, quién te autorizó y desde cuándo</td>
          <td>Servidor de Nexo (MongoDB)</td>
        </tr>
        <tr>
          <td>Registro de consultas <em>(solo cuentas autorizadas)</em></td>
          <td>Quién abrió qué ficha, cuándo y desde qué IP</td>
          <td>Servidor de Nexo (MongoDB)</td>
        </tr>
      </table>
      <p>
        Nexo <strong>no recopila</strong> identificadores publicitarios, tu
        ubicación, tus contactos ni datos de uso con fines de analítica o
        publicidad. La App no incluye rastreadores de terceros.
      </p>

      <h2 id="finalidad">4. Finalidad y base legal</h2>
      <p>Tus datos se tratan exclusivamente para:</p>
      <ul>
        <li>Autenticarte ante los servicios de la UPLA y mostrarte tu propia
            información académica y económica.</li>
        <li>Mantener tu sesión iniciada para que no tengas que ingresar tus
            credenciales cada vez.</li>
        <li>Generar, en tu dispositivo, recordatorios de clases y pagos si
            activas las notificaciones.</li>
        <li>Verificar si tu cuenta está autorizada al directorio de estudiantes
            y, en ese caso, dejar constancia de cada consulta que hagas.</li>
      </ul>
      <p>
        La base legal es tu <strong>consentimiento</strong> al iniciar sesión y
        usar la App, y la <strong>ejecución de la relación</strong> que tú mismo
        tienes con la universidad.
      </p>
      <p>
        El <strong>registro de consultas</strong> del directorio existe
        precisamente para protegerte: si alguien mira tu ficha, queda escrito
        quién y cuándo. Puedes solicitarlo por los medios de contacto de la
        sección 1. Ese registro no se borra a petición de quien consultó, porque
        su razón de ser es poder demostrar lo ocurrido.
      </p>

      <h2 id="terceros">5. Terceros y transferencias internacionales</h2>
      <p>Nexo <strong>no vende ni cede</strong> tus datos. Los únicos destinos de
         tus datos son:</p>
      <ul>
        <li><strong>Servicios de la UPLA</strong> (SIGMA e Intranet): reciben tus
            credenciales y devuelven tu información, igual que el portal oficial.</li>
        <li><strong>Microsoft 365 / Teams</strong> — <em>solo si tú lo conectas</em>.
            En ese caso te autenticas ante Microsoft con tu cuenta institucional y
            la App consulta tus clases y tareas. Ese tratamiento se rige por la
            política de privacidad de Microsoft. Puedes desconectar la cuenta en
            cualquier momento desde la App. Al ser un servicio en la nube, puede
            implicar una transferencia internacional de datos a la que consientes
            al conectarlo.</li>
      </ul>
      <p>
        La versión de la App descargada desde la Microsoft Store se actualiza a
        través de la propia Store; la App no se actualiza por su cuenta ni
        contacta servidores de distribución de Nexo.
      </p>

      <h2 id="conservacion">6. Conservación y borrado</h2>
      <p>
        Como tus datos residen en tu dispositivo, se conservan mientras mantengas
        la sesión iniciada. Al <strong>cerrar sesión</strong> se eliminan tus
        credenciales y la caché de datos. Al <strong>desinstalar</strong> la App
        se elimina todo lo que guardó en tu dispositivo.
      </p>

      <h2 id="seguridad">7. Seguridad</h2>
      <p>
        Toda la comunicación con la UPLA y con Microsoft usa conexiones cifradas
        (HTTPS/TLS). Ten en cuenta que el almacenamiento local de la App no está
        cifrado a nivel de sistema; por eso te recomendamos usar Nexo solo en
        dispositivos de tu confianza y con bloqueo de pantalla activo. Ninguna
        medida de seguridad es infalible, pero aplicamos prácticas razonables
        acordes a la naturaleza de los datos.
      </p>

      <h2 id="permisos">8. Permisos del sistema</h2>
      <ul>
        <li><strong>Internet / red:</strong> imprescindible para conectarse a la
            UPLA.</li>
        <li><strong>Notificaciones:</strong> opcional, para recordatorios de
            clases y pagos generados en tu dispositivo.</li>
        <li><strong>Widgets de pantalla de inicio</strong> (Android): opcional,
            para mostrar tu próxima clase o pago.</li>
      </ul>

      <h2 id="derechos">9. Tus derechos</h2>
      <p>
        Conforme a la Ley N.º 29733 tienes derecho a acceder, rectificar,
        cancelar (suprimir) y oponerte al tratamiento de tus datos personales
        (derechos ARCO), así como a revocar tu consentimiento. Como la App guarda
        tus datos en tu dispositivo, puedes ejercerlos directamente cerrando
        sesión o desinstalando la App. Para cualquier consulta, solicitud o
        reclamo sobre tus datos, escríbenos a
        <a href="mailto:alessandrovillogas@outlook.es">alessandrovillogas@outlook.es</a>;
        atenderemos tu solicitud en los plazos que fija la ley. También puedes
        presentar un reclamo ante la Autoridad Nacional de Protección de Datos
        Personales del Perú.
      </p>

      <h2 id="menores">10. Menores de edad</h2>
      <p>
        Nexo está dirigida a estudiantes universitarios. Algunos ingresantes
        pueden ser menores de 18 años; si es tu caso, usa la App con el
        conocimiento y autorización de tus padres, madres o tutores. No recogemos
        conscientemente datos de menores más allá de la información académica que
        el propio estudiante consulta sobre sí mismo.
      </p>

      <h2 id="cambios">11. Cambios en esta Política</h2>
      <p>
        Podemos actualizar esta Política para reflejar mejoras o cambios legales.
        La versión vigente estará siempre en esta página con su fecha. Si el
        cambio es relevante, te lo avisaremos dentro de la App.
      </p>

      <h2 id="contacto">12. Contacto</h2>
      <p>
        <strong>Responsable:</strong> equipo desarrollador de Nexo — Huancayo, Perú.<br>
        <strong>Correo:</strong>
        <a href="mailto:alessandrovillogas@outlook.es">alessandrovillogas@outlook.es</a><br>
        <strong>WhatsApp:</strong> +51 907 924 307<br>
        <strong>Dentro de la App:</strong> menú «Perfil» → «Soporte».
      </p>

      <footer class="muted">
        Nexo · Proyecto estudiantil independiente. No afiliado a la UPLA ni a
        Microsoft. Documento disponible también en
        <a href="/privacy">/privacy</a>.
      </footer>
    </body>
    </html>
    """
  end
end
