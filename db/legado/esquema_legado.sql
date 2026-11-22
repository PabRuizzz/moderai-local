-- Esquema opcional de la demo anterior.
CREATE DATABASE IF NOT EXISTS moderai CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE moderai;

CREATE TABLE IF NOT EXISTS usuario_config (
  id_usuario          VARCHAR(45)  PRIMARY KEY,
  activo              TINYINT      NOT NULL DEFAULT 1,
  nivel_sensibilidad  INT          NOT NULL DEFAULT 70,
  pin_hash            VARCHAR(64)  NULL,
  nip_activo          TINYINT      NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS regla_filtro (
  id_regla        INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario      VARCHAR(45)  NOT NULL,
  prompt          TEXT         NOT NULL,
  categoria       VARCHAR(45)  NOT NULL, -- SPOILER | SPAM | HATE_SPEECH | CUSTOM_PROMPT
  sensibilidad    VARCHAR(20)  NOT NULL DEFAULT 'Normal', -- Baja | Normal | Alta
  activa          TINYINT      NOT NULL DEFAULT 1,
  fecha_creacion  DATE         NOT NULL DEFAULT (CURRENT_DATE),
  KEY idx_regla_usuario_activa (id_usuario, activa),
  CONSTRAINT fk_regla_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuario_config(id_usuario)
    ON DELETE CASCADE
);

INSERT INTO usuario_config (id_usuario, activo, nivel_sensibilidad, pin_hash, nip_activo)
VALUES ('usr_local_123', 1, 70, NULL, 0)
ON DUPLICATE KEY UPDATE id_usuario = id_usuario;

CREATE TABLE IF NOT EXISTS historial_moderacion (
  id_historial        INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario          VARCHAR(45)  NOT NULL,
  id_regla            INT          NOT NULL,
  hash_contenido      VARCHAR(45)  NOT NULL,
  porcentaje_certeza  FLOAT        NOT NULL,
  accion_aplicada     VARCHAR(30)  NOT NULL, -- DIFUMINADO | VISIBLE | REPORTE_FALSO_POSITIVO
  error_reportado     TINYINT      NOT NULL DEFAULT 0,
  fecha_evaluacion    DATE         NOT NULL,
  FOREIGN KEY (id_usuario) REFERENCES usuario_config(id_usuario),
  FOREIGN KEY (id_regla)   REFERENCES regla_filtro(id_regla)
);

-- Lo que el modelo aprende de los reportes ("Reportar error" = etiqueta 0, "Marcar como ..." = etiqueta 1)
CREATE TABLE IF NOT EXISTS correccion_usuario (
  id_correccion  INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario     VARCHAR(45) NOT NULL,
  id_regla       INT         NOT NULL,
  texto          TEXT        NOT NULL, -- en producción guardar solo el embedding, no el texto (privacidad)
  etiqueta       TINYINT     NOT NULL,
  fecha          DATE        NOT NULL,
  FOREIGN KEY (id_regla) REFERENCES regla_filtro(id_regla) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS identidad_extension (
  token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  id_usuario VARCHAR(45) NOT NULL,
  FOREIGN KEY (id_usuario) REFERENCES usuario_config(id_usuario) ON DELETE CASCADE
);
