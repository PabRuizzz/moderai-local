using Microsoft.AspNetCore.Mvc;
using ModerAI.Entidades;
using ModerAI.Negocios;

namespace ModerAI.Web.Pages.Dashboard;

public sealed class IndexModel(DashboardNegocio negocio, ModeloCliente modelo, ILogger<IndexModel> logger)
    : PaginaCuenta(negocio, logger)
{
    public string Seccion { get; private set; } = "reglas";
    public string? Texto { get; private set; }
    public string? Categoria { get; private set; }
    public bool SinReportes { get; private set; }
    public string Periodo { get; private set; } = "diario";
    public DateOnly? Desde { get; private set; }
    public DateOnly? Hasta { get; private set; }
    public Resumen? Estado { get; private set; }
    public IReadOnlyList<Regla> Reglas { get; private set; } = [];
    public IReadOnlyList<Feedback> Reportes { get; private set; } = [];
    public IReadOnlyList<Coincidencia> Actividad { get; private set; } = [];

    public IActionResult OnGet(string? seccion, string? texto, string? categoria, bool sinReportes,
        string? periodo, DateOnly? desde, DateOnly? hasta)
    {
        Seccion = seccion is "cuenta" or "feedback" or "coincidencias" ? seccion : "reglas";
        (Texto, Categoria, SinReportes, Periodo, Desde, Hasta) = (texto, categoria, sinReportes, periodo ?? "diario", desde, hasta);
        try
        {
            LeerCuenta();
            if (Cuenta is null) { Seccion = "cuenta"; return Page(); }
            if (!ModelState.IsValid) throw new ReglaNegocioException("Revisa los filtros del formulario.");
            switch (Seccion)
            {
                case "reglas": Reglas = Negocio.Reglas(Cuenta, Texto, Categoria, SinReportes); break;
                case "cuenta": Estado = Negocio.ResumenCuenta(Cuenta.Id); break;
                case "feedback": Reportes = Negocio.Reportes(Cuenta.Id); break;
                case "coincidencias": Actividad = Negocio.Actividad(Cuenta.Id, Periodo, Desde, Hasta); break;
            }
        }
        catch (Exception e) when (ErrorEsperado(e)) { MostrarError(e); }
        return Page();
    }

    public async Task<IActionResult> OnPostAccesoAsync(string? nickname, string? password, bool crear)
    {
        Seccion = "cuenta";
        Response.Headers.CacheControl = "no-store";
        try
        {
            if (string.IsNullOrWhiteSpace(nickname) || nickname.Trim().Length > 50 ||
                string.IsNullOrEmpty(password) || password.Length > 128 || (crear && password.Length < 12))
                throw new ReglaNegocioException("Revisa tu nickname. Para registrar una cuenta, la contraseña debe tener entre 12 y 128 caracteres.");
            var token = await modelo.IniciarSesion(nickname.Trim(), password, Token, crear, HttpContext.RequestAborted);
            var opciones = AjustesCookie();
            opciones.MaxAge = TimeSpan.FromHours(8);
            Response.Cookies.Append(ModeloCliente.Cookie, token, opciones);
            Aviso = crear ? "Cuenta creada." : "Sesión iniciada.";
            return RedirectToPage(new { seccion = "cuenta" });
        }
        catch (Exception e) when (ErrorEsperado(e)) { MostrarError(e); return Page(); }
    }

    public IActionResult OnPostSalir() => Ejecutar(_ =>
    {
        Negocio.CerrarSesion(Token);
        Response.Cookies.Delete(ModeloCliente.Cookie, AjustesCookie());
    }, "Sesión cerrada.", () => RedirectToPage(new { seccion = "cuenta" }));

    public IActionResult OnPostConfigurar(string? nickname, string? sensibilidadActiva, int certezaBaja, int certezaNormal, int certezaAlta) =>
        Ejecutar(id => Negocio.ActualizarUsuario(id, nickname, sensibilidadActiva, certezaBaja, certezaNormal, certezaAlta), "Configuración guardada.",
            () => RedirectToPage(new { seccion = "cuenta" }));

    public IActionResult OnPostEliminarCuenta(string? confirmacion) => Ejecutar(usuario =>
    {
        if (confirmacion != "ELIMINAR") throw new ReglaNegocioException("Escribe ELIMINAR para confirmar.");
        Negocio.EliminarUsuario(usuario);
        Response.Cookies.Delete(ModeloCliente.Cookie, AjustesCookie());
    }, "Cuenta eliminada.", () => RedirectToPage(new { seccion = "cuenta" }));

    public IActionResult OnPostGuardarRegla(ulong? regla, string? texto, string? categoria, string? sensibilidad, bool activa) =>
        Ejecutar(id => Negocio.GuardarRegla(id, regla, texto, categoria, sensibilidad, activa),
            regla is null ? "Regla creada y activada." : "Regla actualizada.", () => RedirectToPage());

    public IActionResult OnPostBorrarRegla(ulong regla) =>
        Ejecutar(id => Negocio.EliminarRegla(id, regla), "Regla borrada.", () => RedirectToPage());
}
