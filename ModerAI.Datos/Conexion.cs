using MySql.Data.MySqlClient;

namespace ModerAI.Datos;

public static class Conexion
{
    private static string? _cadenaConexion;

    public static void Configurar(string cadenaConexion)
    {
        var ajustes = new MySqlConnectionStringBuilder(cadenaConexion);
        if (!string.Equals(ajustes.Database, "moderai_usuarios", StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrWhiteSpace(ajustes.UserID)
            || string.Equals(ajustes.UserID, "root", StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrEmpty(ajustes.Password))
            throw new ArgumentException("Configura una cuenta dedicada para moderai_usuarios.");

        bool local = ajustes.Server is "127.0.0.1" or "localhost" or "::1";
        if (ajustes.SslMode != MySqlSslMode.VerifyFull && (!local || ajustes.SslMode != MySqlSslMode.Required))
            throw new ArgumentException("La conexión MySQL requiere TLS y verificación de identidad en servidores remotos.");

        _cadenaConexion = ajustes.ConnectionString;
    }

    public static MySqlConnection Crear() => new(_cadenaConexion ??
        throw new InvalidOperationException("Configura ConnectionStrings:ModerAI para conectar MySQL."));
}
