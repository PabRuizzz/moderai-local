using ModerAI.Negocios;
using ModerAI.Web;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages();
builder.Services.AddDataProtection();
builder.Services.AddScoped<DashboardNegocio>();
builder.Services.AddSingleton<BorradoresReporte>();
builder.Services.AddSingleton<SesionesExtension>();
builder.Services.AddHttpClient<ModeloCliente>(client =>
{
    var url = new Uri(builder.Configuration["Modelo:Url"] ?? "http://127.0.0.1:8001");
    if (url.Scheme != "https" && (url.Scheme != "http" || !url.IsLoopback))
        throw new InvalidOperationException("El servicio del modelo debe usar HTTPS si es remoto.");
    client.BaseAddress = url;
    client.Timeout = TimeSpan.FromSeconds(20);
}).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { UseCookies = false, AllowAutoRedirect = false });

var extension = builder.Configuration["Modelo:ExtensionId"] ?? "kalifemlanoldmeofgfpnjkeaonadpfe";
if (extension.Length != 32 || extension.Any(c => c is < 'a' or > 'p'))
    throw new InvalidOperationException("Configura un identificador de extensión de Chrome válido.");
var origenExtension = $"chrome-extension://{extension}";
builder.Services.AddCors(options => options.AddPolicy("Extension", policy => policy
    .WithOrigins(origenExtension).WithMethods("POST", "PATCH").WithHeaders("Content-Type", "Authorization").AllowCredentials()));

var cadena = builder.Configuration.GetConnectionString("ModerAI");
if (!string.IsNullOrWhiteSpace(cadena))
    ConfiguracionNegocio.Inicializar(cadena);

var app = builder.Build();
app.UseExceptionHandler("/Error");
app.UseStaticFiles();
app.UseRouting();
app.UseCors();
app.MapGet("/", () => Results.Redirect("/Dashboard"));
app.MapRazorPages();

app.MapPost("/api/cuenta/vincular-extension", (HttpContext http, DashboardNegocio negocio, SesionesExtension sesiones) =>
{
    var solicitud = http.Request;
    http.Response.Headers.CacheControl = "no-store";
    if (solicitud.Headers.Origin != $"{solicitud.Scheme}://{solicitud.Host}")
        return Results.Json(new { detail = "Origen de Dashboard no autorizado." }, statusCode: 403);

    var token = solicitud.Cookies[ModeloCliente.Cookie];
    if (negocio.UsuarioDeSesion(token) is null)
        return Results.Json(new { detail = "Inicia sesión en Dashboard." }, statusCode: 401);
    return Results.Json(new { ticket = sesiones.Crear(token!) });
});

app.MapPost("/api/cuenta/extension/reportes/borrador",
    (HttpContext http, SolicitudReporte entrada, BorradoresReporte borradores, DashboardNegocio negocio, SesionesExtension sesiones) =>
        ReportesExtension.Crear(http, origenExtension, borradores, negocio, sesiones, entrada))
    .WithMetadata(new Microsoft.AspNetCore.Mvc.RequestSizeLimitAttribute(32768))
    .RequireCors("Extension");

foreach (var (ruta, metodo) in new (string, string)[]
{
    ("/configuracion", "POST"), ("/evaluar", "POST"), ("/reglas", "POST"),
    ("/reglas/{regla}", "PATCH"),
})
{
    app.MapMethods("/api/cuenta/extension" + ruta, [metodo], async (HttpContext context, ModeloCliente modelo, SesionesExtension sesiones) =>
    {
        if (context.Request.Headers.Origin != origenExtension)
            return Results.Json(new { detail = "Origen de extensión no autorizado" }, statusCode: 403);
        var token = sesiones.Leer(context.Request);
        if (token is null)
            return Results.Json(new { detail = "Inicia sesión en Dashboard" }, statusCode: 401);
        if (context.Request.ContentLength is > 2_000_000)
            return Results.Json(new { detail = "Solicitud demasiado grande" }, statusCode: 413);
        return await modelo.PasarSolicitud(context, token);
    }).RequireCors("Extension");
}

app.Run();
