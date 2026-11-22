using ModerAI.Entidades;
using MySql.Data.MySqlClient;

namespace ModerAI.Datos;

public sealed class DashboardDatos
{
    public Usuario? UsuarioDeSesion(byte[] huella) => Consultar("""
        SELECT u.id_usuario, u.nickname, u.sensibilidad_activa, u.certeza_baja, u.certeza_normal, u.certeza_alta
        FROM sesiones_usuarios s JOIN usuarios u USING (id_usuario)
        WHERE s.token_hash = @token AND s.vence_en > UTC_TIMESTAMP()
        """, r => new Usuario(r.GetUInt64(0), r.GetString(1), r.GetString(2),
            r.GetInt32(3), r.GetInt32(4), r.GetInt32(5)), ("@token", huella)).SingleOrDefault();

    public void CerrarSesion(byte[] huella) =>
        Ejecutar("DELETE FROM sesiones_usuarios WHERE token_hash = @token", ("@token", huella));

    public void ActualizarUsuario(ulong usuario, string nickname, string activa, int baja, int normal, int alta) => Ejecutar("""
        UPDATE usuarios SET nickname = @nick, sensibilidad_activa = @activa,
            certeza_baja = @baja, certeza_normal = @normal, certeza_alta = @alta
        WHERE id_usuario = @usuario
        """, ("@usuario", usuario), ("@nick", nickname), ("@activa", activa),
        ("@baja", baja), ("@normal", normal), ("@alta", alta));

    public void EliminarUsuario(ulong usuario) =>
        Ejecutar("CALL sp_eliminar_cuenta(@usuario)", ("@usuario", usuario));

    public Resumen ResumenCuenta(ulong usuario) => Consultar("""
        SELECT a.total_activas, COALESCE(d.total_coincidencias, 0)
        FROM vw_reglas_activas a
        LEFT JOIN coincidencias_diarias d ON d.id_usuario = a.id_usuario AND d.fecha = UTC_DATE()
        WHERE a.id_usuario = @usuario
        """, r => new Resumen(r.GetUInt64(0), r.GetUInt64(1)), ("@usuario", usuario)).Single();

    public IReadOnlyList<Regla> Reglas(Usuario usuario, string texto = "", string categoria = "", bool sinReportes = false) =>
        Consultar("""
        SELECT r.id_regla, r.texto_regla, r.categoria, r.sensibilidad, r.activa,
               fn_umbral_regla(@baja, @normal, @alta, r.sensibilidad) AS umbral
        FROM reglas r
        WHERE r.id_usuario = @usuario AND r.fecha_borrado IS NULL
          AND (@texto = '' OR LOCATE(@texto, r.texto_regla) > 0)
          AND (@categoria = '' OR r.categoria = @categoria)
          AND (@sinReportes = FALSE OR NOT EXISTS (SELECT 1 FROM feedback f WHERE f.id_regla = r.id_regla))
        ORDER BY r.id_regla DESC
        """, r => new Regla(r.GetUInt64(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetBoolean(4), r.GetInt32(5)),
        ("@usuario", usuario.Id), ("@baja", usuario.CertezaBaja), ("@normal", usuario.CertezaNormal),
        ("@alta", usuario.CertezaAlta), ("@texto", texto),
        ("@categoria", categoria), ("@sinReportes", sinReportes));

    public void CrearRegla(ulong usuario, string texto, string categoria, string sensibilidad) => Ejecutar("""
        INSERT INTO reglas (id_usuario, texto_regla, categoria, sensibilidad, activa, fecha_creacion)
        VALUES (@usuario, @texto, @categoria, @sensibilidad, TRUE, UTC_DATE())
        """, ("@usuario", usuario), ("@texto", texto), ("@categoria", categoria), ("@sensibilidad", sensibilidad));

    public bool EditarRegla(ulong usuario, ulong regla, string texto, string categoria, string sensibilidad, bool activa) =>
        Ejecutar("""
            UPDATE reglas SET texto_regla = @texto, categoria = @categoria, sensibilidad = @sensibilidad, activa = @activa
            WHERE id_usuario = @usuario AND id_regla = @regla AND fecha_borrado IS NULL
            """, ("@usuario", usuario), ("@regla", regla), ("@texto", texto), ("@categoria", categoria),
            ("@sensibilidad", sensibilidad), ("@activa", activa)) > 0;

    public bool EliminarRegla(ulong usuario, ulong regla) => Ejecutar("""
        UPDATE reglas SET activa = FALSE, fecha_borrado = UTC_TIMESTAMP()
        WHERE id_usuario = @usuario AND id_regla = @regla AND fecha_borrado IS NULL
        """, ("@usuario", usuario), ("@regla", regla)) > 0;

    public IReadOnlyList<Feedback> Reportes(ulong usuario, ulong? regla = null) => Consultar("""
        SELECT id_feedback, id_regla, texto_regla, texto_feedback, fecha_emision, tipo_reporte, texto_publicacion
        FROM vw_feedback_reglas WHERE id_usuario = @usuario AND (@regla IS NULL OR id_regla = @regla)
        ORDER BY fecha_emision DESC, id_feedback DESC
        """, r => new Feedback(r.GetUInt64(0), r.GetUInt64(1), r.GetString(2), r.GetString(3), r.GetDateTime(4),
            r.IsDBNull(5) ? null : r.GetString(5), r.IsDBNull(6) ? null : r.GetString(6)),
        ("@usuario", usuario), ("@regla", regla));

    public void CrearReporte(ulong usuario, ulong regla, string texto) => Ejecutar("""
        CALL sp_registrar_feedback(@usuario, @regla, @texto)
        """, ("@usuario", usuario), ("@regla", regla), ("@texto", texto));

    public bool CrearReporteFeed(ulong usuario, ulong regla, ContextoReporte contexto, string comentario) => Ejecutar("""
        INSERT INTO feedback (id_regla, texto_feedback, fecha_emision, tipo_reporte, texto_publicacion)
        SELECT r.id_regla, @comentario, UTC_TIMESTAMP(), @tipo, @publicacion
        FROM reglas r JOIN usuarios u USING (id_usuario)
        WHERE r.id_usuario = @usuario AND id_regla = @regla AND fecha_borrado IS NULL
          AND (@tipo <> 'faltaba_censura' OR (activa = TRUE AND r.sensibilidad = u.sensibilidad_activa))
        """, ("@usuario", usuario), ("@regla", regla), ("@comentario", comentario),
        ("@tipo", contexto.Tipo), ("@publicacion", contexto.Publicacion)) == 1;

    public bool EditarReporte(ulong usuario, ulong reporte, string texto) => Ejecutar("""
        UPDATE feedback f JOIN reglas r USING (id_regla) SET f.texto_feedback = @texto
        WHERE r.id_usuario = @usuario AND f.id_feedback = @reporte
          AND (@texto <> '' OR f.tipo_reporte IS NOT NULL)
        """, ("@usuario", usuario), ("@reporte", reporte), ("@texto", texto)) > 0;

    public bool EliminarReporte(ulong usuario, ulong reporte) => Ejecutar("""
        DELETE f FROM feedback f JOIN reglas r USING (id_regla)
        WHERE r.id_usuario = @usuario AND f.id_feedback = @reporte
        """, ("@usuario", usuario), ("@reporte", reporte)) > 0;

    public IReadOnlyList<Coincidencia> Actividad(ulong usuario, string periodo, DateOnly? desde, DateOnly? hasta)
    {
        var (tabla, columna, limite) = periodo switch
        {
            "semanal" => ("coincidencias_semanales", "fecha_inicio_semana", ">= UTC_DATE() - INTERVAL 1 YEAR"),
            "mensual" => ("coincidencias_mensuales", "fecha_inicio_mes", "> UTC_DATE() - INTERVAL 3 YEAR"),
            _ => ("coincidencias_diarias", "fecha", ">= UTC_DATE() - INTERVAL 29 DAY"),
        };
        return Consultar($"""
            SELECT {columna}, total_coincidencias FROM {tabla}
            WHERE id_usuario = @usuario AND {columna} {limite} AND {columna} <= UTC_DATE()
              AND (@desde IS NULL OR {columna} >= @desde) AND (@hasta IS NULL OR {columna} <= @hasta)
            ORDER BY {columna} DESC
            """, r => new Coincidencia(DateOnly.FromDateTime(r.GetDateTime(0)), r.GetUInt64(1)),
            ("@usuario", usuario), ("@desde", desde?.ToDateTime(TimeOnly.MinValue)),
            ("@hasta", hasta?.ToDateTime(TimeOnly.MinValue)));
    }

    private static List<T> Consultar<T>(string sql, Func<MySqlDataReader, T> mapear,
        params (string Nombre, object? Valor)[] parametros)
    {
        using var cn = Conexion.Crear();
        cn.Open();
        using var cmd = Comando(cn, sql, parametros);
        using var lector = cmd.ExecuteReader();
        var resultado = new List<T>();
        while (lector.Read())
            resultado.Add(mapear(lector));
        return resultado;
    }

    private static int Ejecutar(string sql, params (string Nombre, object? Valor)[] parametros)
    {
        using var cn = Conexion.Crear();
        cn.Open();
        using var cmd = Comando(cn, sql, parametros);
        return cmd.ExecuteNonQuery();
    }

    private static MySqlCommand Comando(MySqlConnection cn, string sql, (string Nombre, object? Valor)[] parametros)
    {
        var cmd = new MySqlCommand(sql, cn);
        foreach (var (nombre, valor) in parametros)
            cmd.Parameters.AddWithValue(nombre, valor ?? DBNull.Value);
        return cmd;
    }
}
