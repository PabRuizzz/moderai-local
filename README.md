# ModerAI

Extensión de Chrome para filtrar publicaciones en X mediante reglas en lenguaje natural. Dashboard administra cuentas, reglas y actividad en MySQL. FastAPI conserva el servicio de evaluación en Python.

## Proyecto final en Visual Studio

Abre **ModerAI.slnx** y selecciona **ModerAI.Web** como proyecto de inicio. La solución usa .NET 10, Razor Pages y MySql.Data 26.10.0. El sitio abre en [Dashboard](http://127.0.0.1:5180/Dashboard).

README.me explica la instalación de MySQL, User Secrets y los scripts SQL.

| Ruta | Contenido |
|---|---|
| ModerAI.Entidades | Modelos de datos. |
| ModerAI.Datos | Conexión y consultas parametrizadas de MySQL. |
| ModerAI.Negocios | Validación y operaciones de la aplicación. |
| ModerAI.Web | Dashboard y formulario de reportes en Razor Pages. |
| api | Autenticación compatible con cuentas existentes, modelo y API FastAPI. |
| src | Extensión Manifest V3, popup y opciones locales del navegador. |
| [db](db/README.md) | Esquema, datos de demostración y consultas. |
| docs | Guía técnica, diccionario de datos y diagramas. |

## Modelo y extensión

1. Instala las dependencias de `api/requirements.txt` en el entorno Python e inicia el servicio con `.\scripts\Iniciar-Dashboard.ps1 -Modelo embeddings`. `-Modelo keywords` permite probar la integración con coincidencia de palabras.
2. Desde el mismo perfil de Chrome o Brave, recarga la extensión descomprimida desde la carpeta que contiene `manifest.json` y [abre Cuenta](http://127.0.0.1:5180/Dashboard?seccion=cuenta). Al iniciar sesión o recargar Dashboard con una sesión activa, la extensión vincula esa cuenta para el feed.
3. Abre o recarga X. El servicio evalúa las publicaciones con las reglas activas y registra coincidencias. Las publicaciones visibles permiten **Reportar contenido sin censurar**. Al revelar una publicación ocultada puedes **Reportar censura equivocada**.

En un servidor remoto, configura HTTPS, la conexión MySQL privada y la URL de la API. Actualiza `ACCOUNT_API_BASE` en `src/background.js` y el origen correspondiente en `manifest.json`. Si cambia el identificador de la extensión, actualiza `Modelo:ExtensionId` en .NET y `MODERAI_EXTENSION_ID` en Python.

Los parámetros `EMB_CENTRO` y `EMB_PENDIENTE` en `api/main.py` convierten la similitud del modelo en un porcentaje. Se pueden calibrar con datos de prueba representativos.

## Ultima vista

Hice las pruebas finales y puedo confirmar que funciona a la perfección
0 errores