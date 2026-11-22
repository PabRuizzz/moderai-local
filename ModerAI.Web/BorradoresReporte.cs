using Microsoft.Extensions.Caching.Memory;
using ModerAI.Entidades;

namespace ModerAI.Web;

public sealed class BorradoresReporte : IDisposable
{
    private readonly MemoryCache _cache = new(new MemoryCacheOptions { SizeLimit = 256 });

    public Guid Guardar(ulong usuario, ContextoReporte contexto)
    {
        var id = Guid.NewGuid();
        _cache.Set(id, new BorradorReporte(usuario, contexto),
            new MemoryCacheEntryOptions().SetSize(1).SetAbsoluteExpiration(TimeSpan.FromMinutes(15)));
        if (!_cache.TryGetValue(id, out _))
            throw new InvalidOperationException("El almacenamiento temporal de reportes está lleno.");
        return id;
    }

    public BorradorReporte? Buscar(Guid id, ulong usuario) =>
        _cache.TryGetValue(id, out BorradorReporte? borrador) && borrador?.Usuario == usuario
            ? borrador : null;

    public void Quitar(Guid id) => _cache.Remove(id);
    public void Dispose() => _cache.Dispose();
}

public sealed record BorradorReporte(ulong Usuario, ContextoReporte Contexto)
{
    public bool Enviado { get; set; }
}
