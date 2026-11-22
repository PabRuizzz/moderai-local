USE moderai_usuarios;

-- Las reglas anteriores conservan su texto; no se inventa su fecha de creación.
SET @reglas_ampliadas = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = 'moderai_usuarios' AND TABLE_NAME = 'reglas'
    AND COLUMN_NAME IN ('categoria', 'sensibilidad', 'fecha_creacion')
);
SET @ampliar_reglas = IF(@reglas_ampliadas = 3, 'DO 0',
  'ALTER TABLE reglas
     ADD categoria ENUM(''SPOILER'', ''SPAM'', ''HATE_SPEECH'', ''CUSTOM_PROMPT'') NOT NULL DEFAULT ''CUSTOM_PROMPT'',
     ADD sensibilidad ENUM(''Baja'', ''Normal'', ''Alta'') NOT NULL DEFAULT ''Normal'',
     ADD fecha_creacion DATE NULL');
PREPARE migracion_reglas FROM @ampliar_reglas;
EXECUTE migracion_reglas;
DEALLOCATE PREPARE migracion_reglas;

CREATE TABLE IF NOT EXISTS coincidencias_registradas (
  id_usuario BIGINT UNSIGNED NOT NULL,
  fecha DATE NOT NULL,
  huella BINARY(32) NOT NULL,
  PRIMARY KEY (id_usuario, fecha, huella),
  KEY idx_coincidencias_registradas_fecha (fecha),
  CONSTRAINT fk_coincidencias_registradas_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE = InnoDB;

GRANT INSERT ON moderai_usuarios.coincidencias_registradas TO 'moderai_dashboard'@'127.0.0.1';
GRANT INSERT, UPDATE (total_coincidencias)
  ON moderai_usuarios.coincidencias_diarias TO 'moderai_dashboard'@'127.0.0.1';
GRANT INSERT, UPDATE (total_coincidencias)
  ON moderai_usuarios.coincidencias_semanales TO 'moderai_dashboard'@'127.0.0.1';
GRANT INSERT, UPDATE (total_coincidencias)
  ON moderai_usuarios.coincidencias_mensuales TO 'moderai_dashboard'@'127.0.0.1';

DELIMITER //
CREATE EVENT IF NOT EXISTS depurar_coincidencias
  ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 1 DAY
  DO
  BEGIN
    DELETE FROM coincidencias_diarias WHERE fecha < UTC_DATE() - INTERVAL 29 DAY;
    DELETE FROM coincidencias_semanales WHERE fecha_inicio_semana < UTC_DATE() - INTERVAL 1 YEAR;
    DELETE FROM coincidencias_mensuales WHERE fecha_inicio_mes <= UTC_DATE() - INTERVAL 3 YEAR;
    DELETE FROM coincidencias_registradas WHERE fecha < UTC_DATE() - INTERVAL 29 DAY;
  END//
DELIMITER ;
