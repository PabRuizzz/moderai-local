using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using ModerAI.Negocios;

namespace ModerAI.Web;

public sealed class ModeloCliente(HttpClient client)
{
    public const string Cookie = "moderai_dashboard_session";
    private const string CookieModelo = "moderai_session";

    public async Task<string> IniciarSesion(string nickname, string password, string? anterior,
        bool registro, CancellationToken cancelacion)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, registro ? "/api/cuenta/registro" : "/api/cuenta/sesion")
        {
            Content = JsonContent.Create(new { nickname, contrasena = password })
        };
        request.Headers.Add("Origin", client.BaseAddress!.GetLeftPart(UriPartial.Authority));
        if (DashboardNegocio.TokenValido(anterior))
            request.Headers.Add("Cookie", $"{CookieModelo}={anterior}");

        using var response = await client.SendAsync(request, cancelacion);
        if (!response.IsSuccessStatusCode)
            throw new ReglaNegocioException(response.StatusCode switch
            {
                HttpStatusCode.Unauthorized => "Nickname o contraseña incorrectos.",
                HttpStatusCode.Conflict => "Ese nickname ya está en uso.",
                HttpStatusCode.TooManyRequests => "Demasiados intentos. Intenta de nuevo en un minuto.",
                HttpStatusCode.UnprocessableEntity => "Revisa el nickname y la contraseña.",
                _ => "El servicio de autenticación no pudo completar la operación."
            });

        if (response.Headers.TryGetValues("Set-Cookie", out var cookies))
        {
            string prefix = CookieModelo + "=";
            foreach (var cookie in cookies)
            {
                var par = cookie.Split(';', 2)[0];
                if (par.StartsWith(prefix, StringComparison.Ordinal) && DashboardNegocio.TokenValido(par[prefix.Length..]))
                    return par[prefix.Length..];
            }
        }
        throw new ReglaNegocioException("El servicio de autenticación no devolvió una sesión válida.");
    }

    public async Task<IResult> PasarSolicitud(HttpContext context, string token)
    {
        var entrada = context.Request;
        using var request = new HttpRequestMessage(new HttpMethod(entrada.Method), entrada.Path.Value);
        request.Headers.Add("Origin", entrada.Headers.Origin.ToString());
        request.Headers.Add("Cookie", $"{CookieModelo}={token}");
        request.Content = new StreamContent(entrada.Body);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        try
        {
            using var response = await client.SendAsync(request, context.RequestAborted);
            context.Response.Headers.CacheControl = "no-store";
            if ((int)response.StatusCode == 204)
                return Results.NoContent();

            var contenido = await response.Content.ReadAsStringAsync(context.RequestAborted);
            return Results.Content(contenido, "application/json", statusCode: (int)response.StatusCode);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException && !context.RequestAborted.IsCancellationRequested)
        {
            return Results.Json(new { detail = "El servicio del modelo no está disponible" }, statusCode: 503);
        }
    }
}
