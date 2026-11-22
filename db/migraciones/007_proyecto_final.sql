USE moderai_usuarios;

-- Ejecutar después de 005 y 006 con una cuenta administradora.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW vw_feedback_reglas AS
SELECT f.id_feedback, r.id_usuario, f.id_regla, r.texto_regla,
       f.texto_feedback, f.fecha_emision
FROM feedback f JOIN reglas r ON r.id_regla = f.id_regla;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW vw_reglas_activas AS
SELECT u.id_usuario, COUNT(r.id_regla) AS total_activas
FROM usuarios u
LEFT JOIN reglas r ON r.id_usuario = u.id_usuario
  AND r.activa = TRUE AND r.fecha_borrado IS NULL
GROUP BY u.id_usuario;

DROP TRIGGER IF EXISTS trg_regla_borrado;
DROP TRIGGER IF EXISTS trg_feedback_regla_disponible;
DROP FUNCTION IF EXISTS fn_umbral_regla;
DROP PROCEDURE IF EXISTS sp_registrar_feedback;
DROP PROCEDURE IF EXISTS sp_eliminar_cuenta;

DELIMITER //

CREATE TRIGGER trg_regla_borrado BEFORE UPDATE ON reglas FOR EACH ROW
BEGIN
  IF OLD.fecha_borrado IS NOT NULL
     AND (NEW.activa OR NOT (NEW.fecha_borrado <=> OLD.fecha_borrado)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Una regla borrada no se puede reactivar';
  END IF;
END//

CREATE TRIGGER trg_feedback_regla_disponible BEFORE INSERT ON feedback FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM reglas WHERE id_regla = NEW.id_regla AND fecha_borrado IS NOT NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La regla reportada ya fue borrada';
  END IF;
END//

CREATE FUNCTION fn_umbral_regla(p_certeza DECIMAL(5,2), p_sensibilidad VARCHAR(6))
RETURNS INT DETERMINISTIC NO SQL SQL SECURITY INVOKER
RETURN LEAST(99, GREATEST(5, LEAST(90, GREATEST(31, ROUND(p_certeza))) +
  CASE p_sensibilidad WHEN 'Baja' THEN 15 WHEN 'Alta' THEN -15 ELSE 0 END))//

CREATE PROCEDURE sp_registrar_feedback(
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

CREATE PROCEDURE sp_eliminar_cuenta(IN p_usuario BIGINT UNSIGNED)
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

DELIMITER ;

GRANT UPDATE (nickname) ON moderai_usuarios.usuarios TO 'moderai_dashboard'@'127.0.0.1';
GRANT UPDATE (texto_regla, categoria, sensibilidad) ON moderai_usuarios.reglas TO 'moderai_dashboard'@'127.0.0.1';
GRANT UPDATE (texto_feedback), DELETE ON moderai_usuarios.feedback TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.vw_feedback_reglas TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.vw_reglas_activas TO 'moderai_dashboard'@'127.0.0.1';
GRANT EXECUTE ON FUNCTION moderai_usuarios.fn_umbral_regla TO 'moderai_dashboard'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE moderai_usuarios.sp_registrar_feedback TO 'moderai_dashboard'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE moderai_usuarios.sp_eliminar_cuenta TO 'moderai_dashboard'@'127.0.0.1';
