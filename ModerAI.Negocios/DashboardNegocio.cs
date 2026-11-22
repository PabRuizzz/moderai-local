using System.Security.Cryptography;
using System.Text;
using ModerAI.Datos;
using ModerAI.Entidades;
using MySql.Data.MySqlClient;

namespace ModerAI.Negocios;

public sealed class ReglaNegocioException(string message) : Exception(message);

public sealed class DashboardNegocio
{
    private readonly DashboardDatos _datos = new();
    public static IReadOnlyList<string> Categorias { get; } = ["SPOILER", "SPAM", "HATE_SPEECH", "CUSTOM_PROMPT"];
    public static IReadOnlyList<string> Sensibilidades { get; } = ["Baja", "Normal", "Alta"];

    public static string Etiqueta(string categoria) => categoria switch
    {
        "SPOILER" => "Spoiler", "SPAM" => "Spam", "HATE_SPEECH" => "Odio", _ => "Personalizada"
    };

    public static bool TokenValido(string? token) => token is { Length: 64 } &&
        token.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

    private static byte[] Huella(string token) => SHA256.HashData(Encoding.ASCII.GetBytes(token));

    public Usuario? UsuarioDeSesion(string? token) =>
        TokenValido(token) ? _datos.UsuarioDeSesion(Huella(token!)) : null;

    public void CerrarSesion(string? token)
    {
        if (TokenValido(token)) _datos.CerrarSesion(Huella(token!));
    }

    public void ActualizarUsuario(ulong id, string? nickname, string? activa, int baja, int normal, int alta)
    {
        if (activa is null || !Sensibilidades.Contains(activa))
            throw new ReglaNegocioException("Selecciona un nivel de sensibilidad activo.");
        if (baja is < 31 or > 50 || normal is < 51 or > 70 || alta is < 71 or > 90)
            throw new ReglaNegocioException("Revisa los umbrales de Baja (31–50), Normal (51–70) y Alta (71–90).");
        try { _datos.ActualizarUsuario(id, TextoRequerido(nickname, 50, "nickname"), activa, baja, normal, alta); }
        catch (MySqlException e) when (e.Number == 1062)
        { throw new ReglaNegocioException("Ese nickname ya está en uso."); }
    }

    public void EliminarUsuario(ulong id) => _datos.EliminarUsuario(id);
    public Resumen ResumenCuenta(ulong id) => _datos.ResumenCuenta(id);

    public IReadOnlyList<Regla> Reglas(Usuario usuario, string? texto, string? categoria, bool sinReportes)
    {
        if (categoria is { Length: > 0 } && !Categorias.Contains(categoria))
            throw new ReglaNegocioException("Selecciona una categoría válida.");
        if (texto?.Length > 200)
            throw new ReglaNegocioException("La búsqueda admite hasta 200 caracteres.");
        return _datos.Reglas(usuario, texto?.Trim() ?? "", categoria ?? "", sinReportes);
    }

    public void GuardarRegla(ulong usuario, ulong? regla, string? texto, string? categoria, string? sensibilidad, bool activa)
    {
        var contenido = TextoRequerido(texto, 2000, "texto de la regla");
        if (categoria is null || !Categorias.Contains(categoria)
            || sensibilidad is null || !Sensibilidades.Contains(sensibilidad))
            throw new ReglaNegocioException("Selecciona una categoría y una sensibilidad válidas.");
        if (regla is null)
            _datos.CrearRegla(usuario, contenido, categoria, sensibilidad);
        else if (!_datos.EditarRegla(usuario, regla.Value, contenido, categoria, sensibilidad, activa))
            throw new ReglaNegocioException("La regla no está disponible.");
    }

    public void EliminarRegla(ulong usuario, ulong regla)
    {
        if (!_datos.EliminarRegla(usuario, regla))
            throw new ReglaNegocioException("La regla no está disponible.");
    }

    public IReadOnlyList<Feedback> Reportes(ulong usuario, ulong? regla = null) => _datos.Reportes(usuario, regla);

    public void CrearReporte(ulong usuario, ulong regla, string? texto)
    {
        var contenido = TextoRequerido(texto, 2000, "texto del reporte");
        try { _datos.CrearReporte(usuario, regla, contenido); }
        catch (MySqlException e) when (e.Number == 1644)
        { throw new ReglaNegocioException("La regla reportada no está disponible."); }
    }

    public void CrearReporteFeed(ulong usuario, ulong regla, ContextoReporte contexto, string? comentario)
    {
        if (contexto.ReglaAplicada is ulong aplicada && aplicada != regla)
            throw new ReglaNegocioException("El reporte debe mantener la regla aplicada a la publicación.");
        var texto = ComentarioReporte(comentario);
        if (!_datos.CrearReporteFeed(usuario, regla, contexto, texto))
            throw new ReglaNegocioException("La regla ya no está disponible. Selecciona una regla activa de tu cuenta.");
    }

    public void EditarReporte(ulong usuario, ulong reporte, string? texto)
    {
        if (!_datos.EditarReporte(usuario, reporte, ComentarioReporte(texto)))
            throw new ReglaNegocioException("El reporte no está disponible o requiere un comentario.");
    }

    public void EliminarReporte(ulong usuario, ulong reporte)
    {
        if (!_datos.EliminarReporte(usuario, reporte))
            throw new ReglaNegocioException("El reporte no está disponible.");
    }

    public IReadOnlyList<Coincidencia> Actividad(ulong usuario, string periodo, DateOnly? desde, DateOnly? hasta)
    {
        if (periodo is not ("diario" or "semanal" or "mensual") || desde > hasta)
            throw new ReglaNegocioException("Selecciona un período y un intervalo de fechas válidos.");
        return _datos.Actividad(usuario, periodo, desde, hasta);
    }

    private static string TextoRequerido(string? valor, int maximo, string campo)
    {
        string texto = valor?.Trim() ?? "";
        if (texto.Length == 0 || texto.Length > maximo)
            throw new ReglaNegocioException($"El campo {campo} debe tener entre 1 y {maximo} caracteres.");
        return texto;
    }

    private static string ComentarioReporte(string? valor)
    {
        string comentario = valor?.Trim() ?? "";
        if (comentario.Length > 2000)
            throw new ReglaNegocioException("El comentario admite hasta 2000 caracteres.");
        return comentario;
    }
}
