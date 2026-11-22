USE moderai_usuarios;

-- Aplicar después de 007. Los reportes anteriores conservan su texto y su regla.
SET @ddl_reportes_feed = IF(
  EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback' AND COLUMN_NAME = 'tipo_reporte'
  ),
  'DO 0',
  'ALTER TABLE feedback
    ADD COLUMN tipo_reporte ENUM(''censura_equivocada'', ''faltaba_censura'') NULL,
    ADD COLUMN texto_publicacion TEXT NULL,
    ADD CONSTRAINT chk_feedback_contexto CHECK (
      (tipo_reporte IS NULL AND texto_publicacion IS NULL) OR
      (tipo_reporte IS NOT NULL AND texto_publicacion IS NOT NULL AND
        CHAR_LENGTH(TRIM(texto_publicacion)) BETWEEN 1 AND 4000)
    )'
);
PREPARE migracion_reportes_feed FROM @ddl_reportes_feed;
EXECUTE migracion_reportes_feed;
DEALLOCATE PREPARE migracion_reportes_feed;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW vw_feedback_reglas AS
SELECT f.id_feedback, r.id_usuario, f.id_regla, r.texto_regla,
       f.texto_feedback, f.fecha_emision, f.tipo_reporte, f.texto_publicacion
FROM feedback f JOIN reglas r ON r.id_regla = f.id_regla;
