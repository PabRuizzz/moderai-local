USE moderai_usuarios;

CREATE TABLE IF NOT EXISTS sesiones_usuarios (
  token_hash BINARY(32) NOT NULL,
  id_usuario BIGINT UNSIGNED NOT NULL,
  vence_en DATETIME NOT NULL,
  PRIMARY KEY (token_hash),
  KEY idx_sesiones_usuario_vencimiento (id_usuario, vence_en),
  CONSTRAINT fk_sesiones_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE CASCADE
) ENGINE = InnoDB;
