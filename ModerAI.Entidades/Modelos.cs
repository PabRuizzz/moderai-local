namespace ModerAI.Entidades;

public sealed record Usuario(ulong Id, string Nickname, string Sensibilidad, int CertezaBaja, int CertezaNormal, int CertezaAlta);
public sealed record Regla(ulong Id, string Texto, string Categoria, string Sensibilidad, bool Activa, int Umbral);
public sealed record Feedback(ulong Id, ulong IdRegla, string Regla, string Texto, DateTime Fecha,
    string? Tipo, string? Publicacion);

public sealed record ContextoReporte(string Tipo, string Publicacion, ulong? ReglaAplicada)
{
    public const string CensuraEquivocada = "censura_equivocada";
    public const string FaltabaCensura = "faltaba_censura";

    public static string Etiqueta(string? tipo) => tipo switch
    {
        CensuraEquivocada => "Censura equivocada",
        FaltabaCensura => "Faltaba censurar",
        _ => "Reporte de regla",
    };
}
public sealed record Coincidencia(DateOnly Fecha, ulong Total);
public sealed record Resumen(ulong ReglasActivas, ulong CoincidenciasHoy);
