USE moderai_usuarios;

-- Conserva el nivel anterior como perfil activo y usa valores iniciales para los otros dos.
SET @perfiles_existen = EXISTS (
  SELECT 1 FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios'
    AND COLUMN_NAME = 'sensibilidad_activa'
);
SET @ddl_perfiles = IF(@perfiles_existen, 'DO 0',
  'ALTER TABLE usuarios
    ADD certeza_baja TINYINT UNSIGNED NOT NULL DEFAULT 50,
    ADD certeza_normal TINYINT UNSIGNED NOT NULL DEFAULT 70,
    ADD certeza_alta TINYINT UNSIGNED NOT NULL DEFAULT 90,
    ADD sensibilidad_activa ENUM(''Baja'', ''Normal'', ''Alta'') NOT NULL DEFAULT ''Normal'',
    ADD CONSTRAINT chk_usuarios_certeza_baja CHECK (certeza_baja BETWEEN 31 AND 50),
    ADD CONSTRAINT chk_usuarios_certeza_normal CHECK (certeza_normal BETWEEN 51 AND 70),
    ADD CONSTRAINT chk_usuarios_certeza_alta CHECK (certeza_alta BETWEEN 71 AND 90)');
PREPARE migracion_perfiles FROM @ddl_perfiles;
EXECUTE migracion_perfiles;
DEALLOCATE PREPARE migracion_perfiles;

SET @certeza_anterior = EXISTS (
  SELECT 1 FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuarios'
    AND COLUMN_NAME = 'nivel_certeza' AND EXTRA NOT LIKE '%GENERATED%'
);
-- El límite corresponde al número de cuentas existentes y permite SQL_SAFE_UPDATES.
SET @actualizar_perfiles = IF(@certeza_anterior,
  CONCAT('UPDATE usuarios SET sensibilidad_activa = nivel_sensibilidad,
    certeza_baja = IF(nivel_sensibilidad = ''Baja'', GREATEST(31, ROUND(nivel_certeza)), 50),
    certeza_normal = IF(nivel_sensibilidad = ''Normal'', ROUND(nivel_certeza), 70),
    certeza_alta = IF(nivel_sensibilidad = ''Alta'', LEAST(90, ROUND(nivel_certeza)), 90)
    ORDER BY id_usuario LIMIT ', (SELECT COUNT(*) FROM usuarios)), 'DO 0');
PREPARE migracion_perfiles FROM @actualizar_perfiles;
EXECUTE migracion_perfiles;
DEALLOCATE PREPARE migracion_perfiles;

-- Las consultas que leen los nombres anteriores siguen funcionando con valores derivados.
SET @ddl_compatibilidad = IF(@certeza_anterior,
  'ALTER TABLE usuarios
    DROP CHECK chk_usuarios_nivel_certeza,
    DROP COLUMN nivel_sensibilidad,
    DROP COLUMN nivel_certeza,
    ADD nivel_sensibilidad ENUM(''Baja'', ''Normal'', ''Alta'') AS (sensibilidad_activa) VIRTUAL,
    ADD nivel_certeza TINYINT UNSIGNED AS (
      CASE sensibilidad_activa
        WHEN ''Baja'' THEN certeza_baja
        WHEN ''Normal'' THEN certeza_normal
        WHEN ''Alta'' THEN certeza_alta
      END
    ) VIRTUAL', 'DO 0');
PREPARE migracion_perfiles FROM @ddl_compatibilidad;
EXECUTE migracion_perfiles;
DEALLOCATE PREPARE migracion_perfiles;

GRANT UPDATE (certeza_baja, certeza_normal, certeza_alta, sensibilidad_activa)
  ON moderai_usuarios.usuarios TO 'moderai_dashboard'@'127.0.0.1';

DROP FUNCTION IF EXISTS fn_umbral_regla;
CREATE FUNCTION fn_umbral_regla(p_baja TINYINT UNSIGNED, p_normal TINYINT UNSIGNED,
  p_alta TINYINT UNSIGNED, p_sensibilidad VARCHAR(6))
RETURNS TINYINT UNSIGNED DETERMINISTIC NO SQL
RETURN CASE p_sensibilidad WHEN 'Baja' THEN p_baja WHEN 'Normal' THEN p_normal WHEN 'Alta' THEN p_alta END;

GRANT EXECUTE ON FUNCTION moderai_usuarios.fn_umbral_regla TO 'moderai_dashboard'@'127.0.0.1';
