-- Datos ficticios para demostrar ModerAI en una base local.
-- Ejecutar completo en Workbench con una cuenta administradora después de la migración 012.
-- Los tres usuarios tienen una contraseña de demostración y hashes Argon2id distintos.
-- Si algún nickname ya existe, se cancela la carga completa sin modificar cuentas existentes.
USE moderai_usuarios;

DROP PROCEDURE IF EXISTS cargar_demostracion_moderai;

DELIMITER //
CREATE PROCEDURE cargar_demostracion_moderai()
carga: BEGIN
  DECLARE v_hoy DATE;
  DECLARE v_ana BIGINT UNSIGNED;
  DECLARE v_bruno BIGINT UNSIGNED;
  DECLARE v_carla BIGINT UNSIGNED;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    DROP TEMPORARY TABLE IF EXISTS tmp_moderai_demo_actividad;
    RESIGNAL;
  END;

  SET v_hoy = UTC_DATE();

  START TRANSACTION;

  IF EXISTS (
    SELECT 1 FROM usuarios WHERE nickname IN ('demo_ana', 'demo_bruno', 'demo_carla')
  ) THEN
    ROLLBACK;
    SELECT 'Ya existe al menos una cuenta demo. Se omitió la carga.' AS aviso;
    LEAVE carga;
  END IF;

  INSERT INTO usuarios (nickname, hash_contrasena, sensibilidad_activa, certeza_alta)
  VALUES ('demo_ana',
    '$argon2id$v=19$m=65536,t=3,p=4$vLY2gLP/Yuud/aRoBQlDRA$t2FJn2I0NL9slq3hmkXdDCbuA00o/nHMx2+CKkO6Mok', 'Alta', 80);
  SET v_ana = LAST_INSERT_ID();

  INSERT INTO usuarios (nickname, hash_contrasena, sensibilidad_activa, certeza_normal)
  VALUES ('demo_bruno',
    '$argon2id$v=19$m=65536,t=3,p=4$kHAIVGrbuBwi1X/qKeBQig$A6W0c51ZgOHU0j1XFN+NOOO+u12oV50JiytqK1BT9RY', 'Normal', 62);
  SET v_bruno = LAST_INSERT_ID();

  INSERT INTO usuarios (nickname, hash_contrasena, sensibilidad_activa, certeza_baja)
  VALUES ('demo_carla',
    '$argon2id$v=19$m=65536,t=3,p=4$fhnOaKuKzYWZISoBv4IpgA$BOzcDsaqrcJKdW5rWvUF3joLB0jYxbMxEKku0TjDGwM', 'Baja', 45);
  SET v_carla = LAST_INSERT_ID();

  INSERT INTO reglas (id_usuario, texto_regla, categoria, sensibilidad, activa, fecha_creacion)
  VALUES
    (v_ana, 'Ocultar publicaciones que revelen marcadores de fútbol.', 'SPOILER', 'Alta', TRUE, v_hoy - INTERVAL 119 DAY),
    (v_ana, 'Ocultar rumores sobre fichajes de fútbol.', 'CUSTOM_PROMPT', 'Normal', FALSE, v_hoy - INTERVAL 42 DAY),
    (v_bruno, 'Ocultar promociones que prometan premios a cambio de hacer clic.', 'SPAM', 'Normal', TRUE, v_hoy - INTERVAL 119 DAY),
    (v_bruno, 'Ocultar anuncios de cupones para videojuegos.', 'CUSTOM_PROMPT', 'Baja', FALSE, v_hoy - INTERVAL 36 DAY),
    (v_carla, 'Ocultar publicaciones que revelen el final de una película.', 'SPOILER', 'Baja', TRUE, v_hoy - INTERVAL 119 DAY),
    (v_carla, 'Ocultar anuncios de estrenos de películas.', 'CUSTOM_PROMPT', 'Baja', FALSE, v_hoy - INTERVAL 31 DAY);

  INSERT INTO feedback (id_regla, texto_feedback, fecha_emision, tipo_reporte, texto_publicacion)
  SELECT
    id_regla,
    CASE id_usuario
      WHEN v_ana THEN 'Solo anunciaba la hora del partido.'
      WHEN v_bruno THEN 'Era un anuncio informativo sin premios ni enlaces.'
      ELSE 'Mencionaba el reparto, sin revelar la trama.'
    END,
    TIMESTAMP(v_hoy - INTERVAL 12 DAY, '18:05:00'),
    'censura_equivocada',
    CASE id_usuario
      WHEN v_ana THEN 'El partido empieza mañana a las 20:00.'
      WHEN v_bruno THEN 'Este viernes habrá una charla abierta sobre videojuegos.'
      ELSE 'La película cuenta con un elenco internacional.'
    END
  FROM reglas
  WHERE id_usuario IN (v_ana, v_bruno, v_carla) AND activa = TRUE;

  INSERT INTO feedback (id_regla, texto_feedback, fecha_emision, tipo_reporte, texto_publicacion)
  SELECT
    id_regla,
    CASE id_usuario
      WHEN v_ana THEN 'La publicación revelaba el marcador final.'
      WHEN v_bruno THEN 'El mensaje prometía un premio a cambio de abrir un enlace.'
      ELSE 'El texto revelaba el desenlace.'
    END,
    TIMESTAMP(v_hoy - INTERVAL 4 DAY, '16:30:00'),
    'faltaba_censura',
    CASE id_usuario
      WHEN v_ana THEN 'El Atlético ganó 3-1 en la final de anoche.'
      WHEN v_bruno THEN 'Haz clic en nuestro enlace para reclamar tu consola gratis.'
      ELSE 'Al final de la película la protagonista descubre que su hermana sigue viva.'
    END
  FROM reglas
  WHERE id_usuario IN (v_ana, v_bruno, v_carla) AND activa = TRUE;

  CREATE TEMPORARY TABLE tmp_moderai_demo_actividad (
    id_usuario BIGINT UNSIGNED NOT NULL,
    fecha DATE NOT NULL,
    total BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (id_usuario, fecha)
  ) ENGINE = InnoDB;

  INSERT INTO tmp_moderai_demo_actividad (id_usuario, fecha, total)
  WITH RECURSIVE dias (numero) AS (
    SELECT 0
    UNION ALL
    SELECT numero + 1 FROM dias WHERE numero < 119
  )
  SELECT demo.id_usuario,
         DATE_SUB(v_hoy, INTERVAL dias.numero DAY),
         1 + MOD(dias.numero * 7 + (dias.numero DIV 3) + demo.perfil * 5, 15)
  FROM dias
  CROSS JOIN (
    SELECT v_ana AS id_usuario, 1 AS perfil
    UNION ALL SELECT v_bruno, 2
    UNION ALL SELECT v_carla, 3
  ) AS demo;

  INSERT INTO coincidencias_diarias (id_usuario, fecha, total_coincidencias)
  SELECT id_usuario, fecha, total
  FROM tmp_moderai_demo_actividad
  WHERE fecha >= v_hoy - INTERVAL 29 DAY;

  INSERT INTO coincidencias_semanales (id_usuario, fecha_inicio_semana, total_coincidencias)
  SELECT id_usuario, DATE_SUB(fecha, INTERVAL WEEKDAY(fecha) DAY), SUM(total)
  FROM tmp_moderai_demo_actividad
  GROUP BY id_usuario, DATE_SUB(fecha, INTERVAL WEEKDAY(fecha) DAY);

  INSERT INTO coincidencias_mensuales (id_usuario, fecha_inicio_mes, total_coincidencias)
  SELECT id_usuario, DATE_SUB(fecha, INTERVAL (DAYOFMONTH(fecha) - 1) DAY), SUM(total)
  FROM tmp_moderai_demo_actividad
  GROUP BY id_usuario, DATE_SUB(fecha, INTERVAL (DAYOFMONTH(fecha) - 1) DAY);

  INSERT INTO coincidencias_registradas (id_usuario, fecha, huella)
  WITH RECURSIVE secuencia (numero) AS (
    SELECT 1
    UNION ALL
    SELECT numero + 1 FROM secuencia WHERE numero < 15
  )
  SELECT actividad.id_usuario,
         actividad.fecha,
         UNHEX(SHA2(CONCAT('moderai-demo:', actividad.id_usuario, ':', actividad.fecha, ':', secuencia.numero), 256))
  FROM tmp_moderai_demo_actividad AS actividad
  JOIN secuencia ON secuencia.numero <= actividad.total
  WHERE actividad.fecha >= v_hoy - INTERVAL 29 DAY;

  DROP TEMPORARY TABLE tmp_moderai_demo_actividad;

  COMMIT;
END//
DELIMITER ;

CALL cargar_demostracion_moderai();
DROP PROCEDURE cargar_demostracion_moderai;

-- Resumen sin hashes para comprobar la carga.
SELECT u.id_usuario, u.nickname, u.nivel_certeza, u.nivel_sensibilidad,
       a.total_activas AS reglas_activas,
       (SELECT COUNT(*) FROM vw_feedback_reglas f WHERE f.id_usuario = u.id_usuario) AS reportes,
       (SELECT COUNT(*) FROM coincidencias_diarias d WHERE d.id_usuario = u.id_usuario) AS dias,
       (SELECT COUNT(*) FROM coincidencias_semanales s WHERE s.id_usuario = u.id_usuario) AS semanas,
       (SELECT COUNT(*) FROM coincidencias_mensuales m WHERE m.id_usuario = u.id_usuario) AS meses
FROM usuarios u
JOIN vw_reglas_activas a ON a.id_usuario = u.id_usuario
WHERE u.nickname IN ('demo_ana', 'demo_bruno', 'demo_carla')
ORDER BY u.nickname;
