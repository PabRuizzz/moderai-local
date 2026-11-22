using System.Text;
using ModerAI.Entidades;
using ModerAI.Negocios;
using MySql.Data.MySqlClient;

namespace ModerAI.Web;

public static class ReportesExtension
{
    public static IResult Crear(HttpContext http, string origen, BorradoresReporte borradores,
        DashboardNegocio negocio, SesionesExtension sesiones, SolicitudReporte entrada)
    {
        if (http.Request.Headers.Origin != origen)
            return Resultados(403, "Origen de extensión no autorizado.");
        var publicacion = entrada.Publicacion?.Trim() ?? "";
        bool esCensura = entrada.Tipo == ContextoReporte.CensuraEquivocada;
        bool esOmision = entrada.Tipo == ContextoReporte.FaltabaCensura;
        ulong? regla = null;
        if (esCensura && ulong.TryParse(entrada.IdRegla, out var id) && id != 0)
            regla = id;
        if (publicacion.Length is 0 or > 8000 || publicacion.EnumerateRunes().Count() > 4000
            || !(esCensura && regla is not null || esOmision && entrada.IdRegla is null)
            || !ulong.TryParse(entrada.IdCuenta, out var cuentaEsperada))
            return Resultados(400, "La publicación o el tipo de reporte no son válidos.");

        try
        {
            var usuario = negocio.UsuarioDeSesion(sesiones.Leer(http.Request));
            if (usuario is null)
                return Resultados(401, "Inicia sesión en Dashboard para reportar.");
            if (usuario.Id != cuentaEsperada)
                return Resultados(409, "Tu sesión cambió. Recarga el feed antes de reportar.");
            var idBorrador = borradores.Guardar(usuario.Id, new ContextoReporte(entrada.Tipo!, publicacion, regla));
            http.Response.Headers.CacheControl = "no-store";
            return Results.Json(new { borrador = idBorrador.ToString("N") });
        }
        catch (Exception error) when (error is MySqlException or InvalidOperationException)
        {
            return Resultados(503, "No se pudo preparar el reporte. Comprueba la conexión con MySQL.");
        }
    }

    private static IResult Resultados(int estado, string detalle) =>
        Results.Json(new { detail = detalle }, statusCode: estado);
}

public sealed record SolicitudReporte(string? Tipo, string? Publicacion, string? IdRegla, string? IdCuenta);
