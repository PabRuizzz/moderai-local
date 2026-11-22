using Microsoft.AspNetCore.Mvc;
using ModerAI.Entidades;
using ModerAI.Negocios;

namespace ModerAI.Web.Pages.Reportes;

public sealed class IndexModel(DashboardNegocio negocio, BorradoresReporte borradores, ILogger<IndexModel> logger)
    : PaginaCuenta(negocio, logger)
{
    public Regla? ReglaReportada { get; private set; }
    public IReadOnlyList<Feedback> Reportes { get; private set; } = [];
    public IReadOnlyList<Regla> ReglasElegibles { get; private set; } = [];
    public ContextoReporte? Contexto { get; private set; }
    public Guid? IdBorrador { get; private set; }
    public string? Comentario { get; private set; }

    public IActionResult OnGet(ulong regla, Guid? borrador)
    {
        try
        {
            LeerCuenta();
            Response.Headers["Referrer-Policy"] = "no-referrer";
            if (Cuenta is null) return RedirectToPage("/Dashboard/Index", new { seccion = "cuenta" });
            if (!ModelState.IsValid) return BadRequest();
            if (borrador is Guid id)
            {
                CargarBorrador(id);
                return Page();
            }
            ReglaReportada = Negocio.Reglas(Cuenta, null, null, false).SingleOrDefault(r => r.Id == regla);
            Reportes = Negocio.Reportes(Cuenta.Id, regla);
            if (ReglaReportada is null && Reportes.Count == 0)
                return NotFound();
        }
        catch (Exception error) when (ErrorEsperado(error)) { MostrarError(error); }
        return Page();
    }

    public IActionResult OnPostCrearDesdeFeed(Guid borrador, ulong regla, string? comentario)
    {
        Comentario = comentario;
        try
        {
            LeerCuenta();
            Response.Headers["Referrer-Policy"] = "no-referrer";
            if (Cuenta is null) return RedirectToPage("/Dashboard/Index", new { seccion = "cuenta" });
            var entrada = CargarBorrador(borrador);
            if (!ModelState.IsValid || regla == 0)
                throw new ReglaNegocioException("Selecciona la regla del reporte.");

            lock (entrada)
            {
                if (entrada.Enviado)
                    throw new ReglaNegocioException("Este reporte ya fue enviado.");
                Negocio.CrearReporteFeed(Cuenta.Id, regla, entrada.Contexto, comentario);
                entrada.Enviado = true;
                borradores.Quitar(borrador);
            }
            Aviso = "Reporte registrado.";
            return RedirectToPage(new { regla });
        }
        catch (Exception error) when (ErrorEsperado(error)) { MostrarError(error); return Page(); }
    }

    private BorradorReporte CargarBorrador(Guid id)
    {
        var borrador = borradores.Buscar(id, Cuenta!.Id)
            ?? throw new ReglaNegocioException("El borrador caducó o no está disponible. Vuelve a abrirlo desde el feed.");
        IdBorrador = id;
        Contexto = borrador.Contexto;
        var reglas = Negocio.Reglas(Cuenta, null, null, false);
        if (Contexto.ReglaAplicada is ulong aplicada)
            ReglaReportada = reglas.SingleOrDefault(r => r.Id == aplicada);
        else
            ReglasElegibles = reglas.Where(r => r.Activa && r.Sensibilidad == Cuenta.Sensibilidad).ToArray();
        return borrador;
    }

    public IActionResult OnPostCrear(ulong regla, string? texto) => Ejecutar(
        id => Negocio.CrearReporte(id, regla, texto), "Reporte registrado.", () => RedirectToPage(new { regla }));

    public IActionResult OnPostEditar(ulong regla, ulong reporte, string? texto) => Ejecutar(
        id => Negocio.EditarReporte(id, reporte, texto), "Reporte actualizado.", () => RedirectToPage(new { regla }));

    public IActionResult OnPostBorrar(ulong regla, ulong reporte) => Ejecutar(
        id => Negocio.EliminarReporte(id, reporte), "Reporte eliminado.", () => RedirectToPage(new { regla }));
}
