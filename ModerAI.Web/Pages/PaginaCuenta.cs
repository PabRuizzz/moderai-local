using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using ModerAI.Entidades;
using ModerAI.Negocios;
using MySql.Data.MySqlClient;

namespace ModerAI.Web.Pages;

public abstract class PaginaCuenta(DashboardNegocio negocio, ILogger logger) : PageModel
{
    protected DashboardNegocio Negocio { get; } = negocio;
    protected string? Token => Request.Cookies[ModeloCliente.Cookie];
    public Usuario? Cuenta { get; protected set; }

    [TempData]
    public string? Aviso { get; set; }

    public string? Error { get; private set; }

    protected void LeerCuenta()
    {
        Response.Headers.CacheControl = "no-store";
        Cuenta = Negocio.UsuarioDeSesion(Token);
    }

    protected void MostrarError(Exception error)
    {
        if (error is ReglaNegocioException)
            Error = error.Message;
        else
        {
            logger.LogWarning("Operación de ModerAI fallida ({Tipo}, MySQL {Numero}).",
                error.GetType().Name, (error as MySqlException)?.Number);
            Error = "El servicio no está disponible. Comprueba MySQL, la instalación con 01_esquema.sql y el servicio del modelo.";
        }
    }

    protected static bool ErrorEsperado(Exception error) =>
        error is ReglaNegocioException or MySqlException or InvalidOperationException or HttpRequestException or TaskCanceledException;

    protected IActionResult Ejecutar(Action<ulong> guardar, string aviso, Func<IActionResult> volver)
    {
        try
        {
            LeerCuenta();
            if (Cuenta is null) return RedirectToPage("/Dashboard/Index", new { seccion = "cuenta" });
            if (!ModelState.IsValid) throw new ReglaNegocioException("Revisa los datos del formulario.");
            guardar(Cuenta.Id);
            Aviso = aviso;
        }
        catch (Exception e) when (ErrorEsperado(e))
        {
            if (e is ReglaNegocioException) Aviso = e.Message;
            else { MostrarError(e); Aviso = Error; }
        }
        return volver();
    }

    protected CookieOptions AjustesCookie() => new()
    {
        HttpOnly = true, IsEssential = true, Secure = Request.IsHttps,
        SameSite = SameSiteMode.Strict, Path = "/",
    };
}
