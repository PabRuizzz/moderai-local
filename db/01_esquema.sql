-- Instalación inicial de ModerAI en MySQL 8.0.29 o posterior.
-- Ejecutar en Workbench como administrador en el servidor local.

CREATE DATABASE IF NOT EXISTS moderai_usuarios
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE moderai_usuarios;

CREATE TABLE IF NOT EXISTS usuarios (
  id_usuario BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nickname VARCHAR(50) NOT NULL,
  hash_contrasena VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  certeza_baja TINYINT UNSIGNED NOT NULL DEFAULT 50,
  certeza_normal TINYINT UNSIGNED NOT NULL DEFAULT 70,
  certeza_alta TINYINT UNSIGNED NOT NULL DEFAULT 90,
  sensibilidad_activa ENUM('Baja', 'Normal', 'Alta') NOT NULL DEFAULT 'Normal',
  nivel_sensibilidad ENUM('Baja', 'Normal', 'Alta') AS (sensibilidad_activa) VIRTUAL,
  nivel_certeza TINYINT UNSIGNED AS (
    CASE sensibilidad_activa
      WHEN 'Baja' THEN certeza_baja
      WHEN 'Normal' THEN certeza_normal
      WHEN 'Alta' THEN certeza_alta
    END
  ) VIRTUAL,
  PRIMARY KEY (id_usuario),
  UNIQUE KEY uq_usuarios_nickname (nickname),
  CONSTRAINT chk_usuarios_certeza_baja CHECK (certeza_baja BETWEEN 31 AND 50),
  CONSTRAINT chk_usuarios_certeza_normal CHECK (certeza_normal BETWEEN 51 AND 70),
  CONSTRAINT chk_usuarios_certeza_alta CHECK (certeza_alta BETWEEN 71 AND 90)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS reglas (
  id_regla BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_usuario BIGINT UNSIGNED NOT NULL,
  texto_regla TEXT NOT NULL,
  activa BOOLEAN NOT NULL DEFAULT TRUE,
  fecha_borrado DATETIME NULL,
  categoria ENUM('SPOILER', 'SPAM', 'HATE_SPEECH', 'CUSTOM_PROMPT') NOT NULL DEFAULT 'CUSTOM_PROMPT',
  sensibilidad ENUM('Baja', 'Normal', 'Alta') NOT NULL DEFAULT 'Normal',
  fecha_creacion DATE NULL,
  PRIMARY KEY (id_regla),
  CONSTRAINT fk_reglas_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
  CONSTRAINT chk_reglas_activa CHECK (activa IN (FALSE, TRUE)),
  CONSTRAINT chk_reglas_borrado CHECK (fecha_borrado IS NULL OR activa = FALSE)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS feedback (
  id_feedback BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_regla BIGINT UNSIGNED NOT NULL,
  texto_feedback TEXT NOT NULL,
  fecha_emision DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  tipo_reporte ENUM('censura_equivocada', 'faltaba_censura') NULL,
  texto_publicacion TEXT NULL,
  PRIMARY KEY (id_feedback),
  CONSTRAINT fk_feedback_regla
    FOREIGN KEY (id_regla) REFERENCES reglas (id_regla) ON DELETE RESTRICT,
  CONSTRAINT chk_feedback_contexto CHECK (
    (tipo_reporte IS NULL AND texto_publicacion IS NULL) OR
    (tipo_reporte IS NOT NULL AND texto_publicacion IS NOT NULL AND
      CHAR_LENGTH(TRIM(texto_publicacion)) BETWEEN 1 AND 4000)
  )
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS coincidencias_diarias (
  id_usuario BIGINT UNSIGNED NOT NULL,
  fecha DATE NOT NULL,
  total_coincidencias BIGINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (id_usuario, fecha),
  CONSTRAINT fk_coincidencias_diarias_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS coincidencias_semanales (
  id_usuario BIGINT UNSIGNED NOT NULL,
  fecha_inicio_semana DATE NOT NULL,
  total_coincidencias BIGINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (id_usuario, fecha_inicio_semana),
  CONSTRAINT fk_coincidencias_semanales_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
  CONSTRAINT chk_coincidencias_inicio_semana CHECK (WEEKDAY(fecha_inicio_semana) = 0)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS coincidencias_mensuales (
  id_usuario BIGINT UNSIGNED NOT NULL,
  fecha_inicio_mes DATE NOT NULL,
  total_coincidencias BIGINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (id_usuario, fecha_inicio_mes),
  CONSTRAINT fk_coincidencias_mensuales_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
  CONSTRAINT chk_coincidencias_inicio_mes CHECK (DAYOFMONTH(fecha_inicio_mes) = 1)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS sesiones_usuarios (
  token_hash BINARY(32) NOT NULL,
  id_usuario BIGINT UNSIGNED NOT NULL,
  vence_en DATETIME NOT NULL,
  PRIMARY KEY (token_hash),
  KEY idx_sesiones_usuario_vencimiento (id_usuario, vence_en),
  CONSTRAINT fk_sesiones_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS coincidencias_registradas (
  id_usuario BIGINT UNSIGNED NOT NULL,
  fecha DATE NOT NULL,
  huella BINARY(32) NOT NULL,
  PRIMARY KEY (id_usuario, fecha, huella),
  KEY idx_coincidencias_registradas_fecha (fecha),
  CONSTRAINT fk_coincidencias_registradas_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE = InnoDB;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW vw_feedback_reglas AS
SELECT f.id_feedback, r.id_usuario, f.id_regla, r.texto_regla,
       f.texto_feedback, f.fecha_emision, f.tipo_reporte, f.texto_publicacion
FROM feedback f JOIN reglas r ON r.id_regla = f.id_regla;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW vw_reglas_activas AS
SELECT u.id_usuario, COUNT(r.id_regla) AS total_activas
FROM usuarios u
LEFT JOIN reglas r ON r.id_usuario = u.id_usuario
  AND r.activa = TRUE AND r.fecha_borrado IS NULL
GROUP BY u.id_usuario;

DELIMITER //

CREATE TRIGGER IF NOT EXISTS trg_regla_borrado BEFORE UPDATE ON reglas FOR EACH ROW
BEGIN
  IF OLD.fecha_borrado IS NOT NULL
     AND (NEW.activa OR NOT (NEW.fecha_borrado <=> OLD.fecha_borrado)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Una regla borrada no se puede reactivar';
  END IF;
END//

CREATE TRIGGER IF NOT EXISTS trg_feedback_regla_disponible BEFORE INSERT ON feedback FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM reglas WHERE id_regla = NEW.id_regla AND fecha_borrado IS NOT NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La regla reportada ya fue borrada';
  END IF;
END//

CREATE FUNCTION IF NOT EXISTS fn_umbral_regla(p_baja TINYINT UNSIGNED, p_normal TINYINT UNSIGNED,
  p_alta TINYINT UNSIGNED, p_sensibilidad VARCHAR(6))
RETURNS TINYINT UNSIGNED DETERMINISTIC NO SQL
RETURN CASE p_sensibilidad WHEN 'Baja' THEN p_baja WHEN 'Normal' THEN p_normal WHEN 'Alta' THEN p_alta END//

CREATE PROCEDURE IF NOT EXISTS sp_registrar_feedback(
  IN p_usuario BIGINT UNSIGNED, IN p_regla BIGINT UNSIGNED, IN p_texto TEXT
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_regla BIGINT UNSIGNED DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT id_regla INTO v_regla FROM reglas
    WHERE id_regla = p_regla AND id_usuario = p_usuario AND fecha_borrado IS NULL
    FOR UPDATE;
  IF v_regla IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Regla no disponible';
  END IF;
  IF p_texto IS NULL OR CHAR_LENGTH(TRIM(p_texto)) NOT BETWEEN 1 AND 2000 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Texto de reporte no válido';
  END IF;
  INSERT INTO feedback (id_regla, texto_feedback, fecha_emision)
  VALUES (v_regla, TRIM(p_texto), UTC_TIMESTAMP());
  COMMIT;
END//

CREATE PROCEDURE IF NOT EXISTS sp_eliminar_cuenta(IN p_usuario BIGINT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_usuario BIGINT UNSIGNED DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT id_usuario INTO v_usuario FROM usuarios WHERE id_usuario = p_usuario FOR UPDATE;
  IF v_usuario IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cuenta no disponible';
  END IF;
  DELETE f FROM feedback f JOIN reglas r ON r.id_regla = f.id_regla
    WHERE r.id_usuario = v_usuario;
  DELETE FROM reglas WHERE id_usuario = v_usuario;
  DELETE FROM coincidencias_registradas WHERE id_usuario = v_usuario;
  DELETE FROM coincidencias_diarias WHERE id_usuario = v_usuario;
  DELETE FROM coincidencias_semanales WHERE id_usuario = v_usuario;
  DELETE FROM coincidencias_mensuales WHERE id_usuario = v_usuario;
  DELETE FROM usuarios WHERE id_usuario = v_usuario;
  COMMIT;
END//

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

-- MySQL muestra la contraseña generada la primera vez que crea esta cuenta.
CREATE USER IF NOT EXISTS 'moderai_dashboard'@'127.0.0.1'
  IDENTIFIED BY RANDOM PASSWORD REQUIRE SSL;

GRANT SELECT, INSERT, UPDATE (nickname, hash_contrasena, certeza_baja, certeza_normal, certeza_alta, sensibilidad_activa)
  ON moderai_usuarios.usuarios TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE (texto_regla, categoria, sensibilidad, activa, fecha_borrado)
  ON moderai_usuarios.reglas TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE (texto_feedback), DELETE
  ON moderai_usuarios.feedback TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, DELETE
  ON moderai_usuarios.sesiones_usuarios TO 'moderai_dashboard'@'127.0.0.1';
GRANT INSERT
  ON moderai_usuarios.coincidencias_registradas TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE (total_coincidencias)
  ON moderai_usuarios.coincidencias_diarias TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE (total_coincidencias)
  ON moderai_usuarios.coincidencias_semanales TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE (total_coincidencias)
  ON moderai_usuarios.coincidencias_mensuales TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.vw_feedback_reglas TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.vw_reglas_activas TO 'moderai_dashboard'@'127.0.0.1';
GRANT EXECUTE ON FUNCTION moderai_usuarios.fn_umbral_regla TO 'moderai_dashboard'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE moderai_usuarios.sp_registrar_feedback TO 'moderai_dashboard'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE moderai_usuarios.sp_eliminar_cuenta TO 'moderai_dashboard'@'127.0.0.1';
