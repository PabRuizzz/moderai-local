CREATE DATABASE IF NOT EXISTS moderai_usuarios
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE moderai_usuarios;

CREATE TABLE IF NOT EXISTS usuarios (
  id_usuario BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nickname VARCHAR(50) NOT NULL,
  hash_contrasena VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  nivel_certeza DECIMAL(5,2) NOT NULL,
  nivel_sensibilidad ENUM('Baja', 'Normal', 'Alta') GENERATED ALWAYS AS (
    CASE
      WHEN ROUND(nivel_certeza) <= 50 THEN 'Baja'
      WHEN ROUND(nivel_certeza) <= 70 THEN 'Normal'
      ELSE 'Alta'
    END
  ) VIRTUAL,
  PRIMARY KEY (id_usuario),
  UNIQUE KEY uq_usuarios_nickname (nickname),
  CONSTRAINT chk_usuarios_nivel_certeza CHECK (nivel_certeza BETWEEN 0 AND 100)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS reglas (
  id_regla BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_usuario BIGINT UNSIGNED NOT NULL,
  texto_regla TEXT NOT NULL,
  activa BOOLEAN NOT NULL DEFAULT TRUE,
  fecha_borrado DATETIME NULL,
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
  PRIMARY KEY (id_feedback),
  CONSTRAINT fk_feedback_regla
    FOREIGN KEY (id_regla) REFERENCES reglas (id_regla) ON DELETE RESTRICT
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
