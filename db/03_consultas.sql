USE moderai_usuarios;
-- Sustituye 1 por el id_usuario de la cuenta que quieres consultar.
SET @id_usuario = 1;

-- 1. JOIN: reglas vigentes y su dueño.
SELECT r.id_regla, u.nickname, r.texto_regla, r.activa
FROM reglas r JOIN usuarios u USING (id_usuario)
WHERE r.fecha_borrado IS NULL
ORDER BY u.nickname, r.id_regla;

-- 2. JOIN: historial de reportes con la regla y el usuario asociado.
SELECT f.id_feedback, r.texto_regla, u.nickname, f.texto_feedback
FROM feedback f JOIN reglas r USING (id_regla) JOIN usuarios u USING (id_usuario)
ORDER BY f.fecha_emision DESC, f.id_feedback DESC;

-- 3. JOIN: actividad diaria atribuida a la cuenta.
SELECT u.nickname, d.fecha, d.total_coincidencias
FROM coincidencias_diarias d JOIN usuarios u USING (id_usuario)
WHERE d.fecha >= UTC_DATE() - INTERVAL 29 DAY
ORDER BY d.fecha DESC, u.nickname;

-- 4. Subconsulta EXISTS: cuentas que tienen una regla habilitada.
SELECT u.id_usuario, u.nickname
FROM usuarios u
WHERE EXISTS (SELECT 1 FROM reglas r WHERE r.id_usuario = u.id_usuario AND r.activa AND r.fecha_borrado IS NULL)
ORDER BY u.nickname;

-- 5. Subconsulta NOT EXISTS: reglas vigentes sin reportes de una cuenta.
SELECT r.id_regla, r.texto_regla, r.categoria, r.sensibilidad
FROM reglas r
WHERE r.id_usuario = @id_usuario AND r.fecha_borrado IS NULL
  AND NOT EXISTS (SELECT 1 FROM feedback f WHERE f.id_regla = r.id_regla)
ORDER BY r.id_regla DESC;

-- 6. Agregación: cuentas con tres o más reglas activas.
SELECT u.id_usuario, u.nickname, COUNT(*) AS reglas_activas
FROM usuarios u JOIN reglas r USING (id_usuario)
WHERE r.activa AND r.fecha_borrado IS NULL
GROUP BY u.id_usuario, u.nickname HAVING COUNT(*) >= 3;

-- 7. Agregación: reglas que acumularon dos o más reportes.
SELECT f.id_regla, COUNT(*) AS reportes
FROM feedback f GROUP BY f.id_regla HAVING COUNT(*) >= 2;

-- 8. Agregación: cuentas con al menos diez coincidencias en los últimos 30 días.
SELECT d.id_usuario, SUM(d.total_coincidencias) AS coincidencias
FROM coincidencias_diarias d WHERE d.fecha BETWEEN UTC_DATE() - INTERVAL 29 DAY AND UTC_DATE()
GROUP BY d.id_usuario HAVING SUM(d.total_coincidencias) >= 10;

-- 9. Libre: cambio respecto del mes calendario anterior. NULL indica que no hay comparación.
SELECT actual.fecha_inicio_mes, actual.total_coincidencias,
       CAST(actual.total_coincidencias AS DECIMAL(21,0)) - anterior.total_coincidencias AS variacion
FROM coincidencias_mensuales actual
LEFT JOIN coincidencias_mensuales anterior ON anterior.id_usuario = actual.id_usuario
 AND anterior.fecha_inicio_mes = actual.fecha_inicio_mes - INTERVAL 1 MONTH
WHERE actual.id_usuario = @id_usuario ORDER BY actual.fecha_inicio_mes;

-- 10. Libre: clasificación por número de reportes, con empates.
WITH conteos AS (
    SELECT r.id_regla, r.texto_regla, COUNT(f.id_feedback) AS total
    FROM reglas r LEFT JOIN feedback f USING (id_regla)
    WHERE r.id_usuario = @id_usuario AND r.fecha_borrado IS NULL
    GROUP BY r.id_regla, r.texto_regla
)
SELECT id_regla, texto_regla, total, DENSE_RANK() OVER (ORDER BY total DESC) AS posicion
FROM conteos ORDER BY posicion, id_regla;

-- Vistas consumidas por la aplicación y función utilizada en el listado de reglas.
SELECT * FROM vw_reglas_activas WHERE id_usuario = @id_usuario;
SELECT * FROM vw_feedback_reglas WHERE id_usuario = @id_usuario;
SELECT fn_umbral_regla(47, 63, 82, 'Baja') AS baja,
       fn_umbral_regla(47, 63, 82, 'Normal') AS normal,
       fn_umbral_regla(47, 63, 82, 'Alta') AS alta;
