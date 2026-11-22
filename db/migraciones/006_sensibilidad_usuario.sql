USE moderai_usuarios;

-- La clasificación sigue el mismo redondeo y los mismos rangos que el dashboard.
SET @sensibilidad_usuario_existe = EXISTS (
  SELECT 1
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'usuarios'
    AND COLUMN_NAME = 'nivel_sensibilidad'
);

SET @sql_sensibilidad_usuario = IF(@sensibilidad_usuario_existe, 'DO 0',
  'ALTER TABLE usuarios
     ADD COLUMN nivel_sensibilidad ENUM(''Baja'', ''Normal'', ''Alta'') GENERATED ALWAYS AS (
       CASE
         WHEN ROUND(nivel_certeza) <= 50 THEN ''Baja''
         WHEN ROUND(nivel_certeza) <= 70 THEN ''Normal''
         ELSE ''Alta''
       END
     ) VIRTUAL');

PREPARE migracion_sensibilidad_usuario FROM @sql_sensibilidad_usuario;
EXECUTE migracion_sensibilidad_usuario;
DEALLOCATE PREPARE migracion_sensibilidad_usuario;
