using System.Security.Cryptography;
using Microsoft.AspNetCore.DataProtection;
using ModerAI.Negocios;

namespace ModerAI.Web;

public sealed class SesionesExtension(IDataProtectionProvider proveedor)
{
    private readonly ITimeLimitedDataProtector _protector = proveedor
        .CreateProtector("ModerAI.Extension.v1").ToTimeLimitedDataProtector();

    public string Crear(string token) => _protector.Protect(token, TimeSpan.FromHours(8));

    public string? Leer(HttpRequest solicitud)
    {
        var autorizacion = solicitud.Headers.Authorization.ToString();
        const string esquema = "Bearer ";
        if (autorizacion.Length == 0)
        {
            var cookie = solicitud.Cookies[ModeloCliente.Cookie];
            return DashboardNegocio.TokenValido(cookie) ? cookie : null;
        }
        if (autorizacion.Length > 1024 || !autorizacion.StartsWith(esquema, StringComparison.OrdinalIgnoreCase))
            return null;
        try
        {
            var token = _protector.Unprotect(autorizacion[esquema.Length..]);
            return DashboardNegocio.TokenValido(token) ? token : null;
        }
        catch (CryptographicException) { return null; }
    }
}
