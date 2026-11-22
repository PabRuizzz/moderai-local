-- Ejecutar como administrador una sola vez. MySQL genera la contraseña.
CREATE USER 'moderai_dashboard'@'127.0.0.1' IDENTIFIED BY RANDOM PASSWORD REQUIRE SSL;

GRANT SELECT, INSERT, UPDATE (nivel_certeza, hash_contrasena)
  ON moderai_usuarios.usuarios TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE (activa, fecha_borrado)
  ON moderai_usuarios.reglas TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT ON moderai_usuarios.feedback TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.coincidencias_diarias TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.coincidencias_semanales TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT ON moderai_usuarios.coincidencias_mensuales TO 'moderai_dashboard'@'127.0.0.1';
GRANT SELECT, INSERT, DELETE ON moderai_usuarios.sesiones_usuarios TO 'moderai_dashboard'@'127.0.0.1';
