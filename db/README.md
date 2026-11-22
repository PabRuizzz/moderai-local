# Base de datos de usuarios de ModerAI

| Carpeta | Contenido |
|---|---|
| [esquema](esquema/) | Creación de la base `moderai_usuarios` y sus tablas iniciales. |
| [migraciones](migraciones/) | Sesiones, cuenta de servicio, configuración, sensibilidad, rutinas y reportes del feed. |
| [consultas](consultas/) | Consultas del proyecto final para ejecutar en Workbench. |
| [legado](legado/README.md) | Esquema `moderai` y documentación de la demo anterior. |

## Instalación de la base actual

En una instancia nueva de MySQL Server 8.0.18 o posterior, abre y ejecuta cada archivo completo en Workbench con una cuenta administradora, en este orden.

1. [Esquema inicial](esquema/schema_usuarios.sql)
2. [003_sesiones_usuarios.sql](migraciones/003_sesiones_usuarios.sql)
3. [004_acceso_dashboard_local.sql](migraciones/004_acceso_dashboard_local.sql). Se ejecuta una sola vez y MySQL muestra la contraseña generada para `moderai_dashboard`. Guárdala de forma privada.
4. [005_opciones_cuenta.sql](migraciones/005_opciones_cuenta.sql)
5. [006_sensibilidad_usuario.sql](migraciones/006_sensibilidad_usuario.sql)
6. [007_proyecto_final.sql](migraciones/007_proyecto_final.sql)
7. [011_reportes_feed.sql](migraciones/011_reportes_feed.sql)
8. [012_perfiles_sensibilidad.sql](migraciones/012_perfiles_sensibilidad.sql)

Para actualizar una base existente, aplica en orden las migraciones pendientes. Para configurar la conexión e iniciar el Dashboard y FastAPI, consulta la [guía del proyecto final](../docs/ProyectoFinal.md#instalación-y-ejecución).

## Modelo

- `usuarios` guarda el nickname único, el hash de contraseña y la configuración de sensibilidad. La migración 012 conserva el perfil anterior, redondea y limita su umbral a 31–90, y da a los otros perfiles los valores iniciales 50, 70 o 90 según su rango.
- `usuarios` guarda `certeza_baja` (31–50), `certeza_normal` (51–70), `certeza_alta` (71–90) y `sensibilidad_activa`. Las columnas virtuales `nivel_sensibilidad` y `nivel_certeza` muestran el perfil y umbral activos. Solo se evalúan reglas habilitadas que tienen esa sensibilidad.
- `reglas` guarda el texto y el dueño de cada regla. El borrado lógico registra `fecha_borrado` y establece `activa = FALSE`.
- `feedback` referencia la regla reportada. Su dueño se obtiene a través de la regla. La clave foránea protege el historial de feedback ante un borrado físico.
- Las tablas `coincidencias_diarias`, `coincidencias_semanales` y `coincidencias_mensuales` guardan un total por usuario y período. Las semanas empiezan el lunes y los meses el día 1.

## Conexión y actividad

Cuando User Secrets no contiene la cadena, el lanzador admite los métodos locales anteriores. Busca `%LOCALAPPDATA%\ModerAI\dashboard-password.txt`, después la credencial protegida con DPAPI `%LOCALAPPDATA%\ModerAI\dashboard-mysql.dpapi` y, si faltan ambos archivos, solicita la contraseña en un campo oculto.

FastAPI usa `ACCOUNTS_DB_USER` y `ACCOUNTS_DB_PASSWORD` de su entorno. `ACCOUNTS_DB_HOST` y `ACCOUNTS_DB_PORT` tienen como valores predeterminados `127.0.0.1` y `3306`. Para un MySQL remoto, configura `ACCOUNTS_DB_SSL_CA` con la CA que valida el certificado y el nombre del servidor. En loopback, el usuario dedicado y la API exigen TLS, y se puede omitir la CA cuando MySQL usa su certificado local autogenerado. Para acceso web remoto, sirve el dashboard y la API bajo el mismo origen HTTPS y configura Uvicorn para confiar solo en el proxy HTTPS de tu instalación. El límite de intentos de registro e inicio de sesión funciona por proceso.

Con una sesión activa, **Reglas** administra las reglas de la cuenta. **Feedback** muestra los reportes guardados desde el feed. **Cuenta** reúne el nivel de certeza, el NIP y el resumen de actividad. **Coincidencias** muestra el historial diario, semanal y mensual.

La extensión usa las reglas y el nivel de certeza de la cuenta que inicia sesión en el mismo perfil de Chrome. La API de evaluación contabiliza cada texto una vez por cuenta y día UTC si coincide con alguna regla. Las tres series se actualizan en una transacción. El total del historial usa únicamente la serie mensual. El evento de MySQL elimina registros vencidos una vez al día cuando `event_scheduler` está habilitado.

Las rutas de extensión solo aceptan el origen autorizado de Chrome junto con la sesión web de ModerAI. Al cerrar sesión en el dashboard, la extensión pierde ese acceso. Sin iniciar sesión, el prototipo conserva sus datos de demostración. El NIP sigue siendo una configuración local del navegador.
