using ModerAI.Datos;
namespace ModerAI.Negocios;

public static class ConfiguracionNegocio
{
    public static void Inicializar(string cadena) => Conexion.Configurar(cadena);
}
