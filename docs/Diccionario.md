# Diccionario de datos de ModerAI

Cada columna marcada como PK dentro de una misma clave compuesta identifica la fila en conjunto.

## usuarios

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_usuario | bigint unsigned | No | — | PK · Autoincremental | Identifica la cuenta. |
| nickname | varchar(50) | No | — | Único | Nombre único para iniciar sesión. |
| hash_contrasena | varchar(255) | No | — | — | Hash Argon2id de la contraseña. |
| certeza_baja | tinyint unsigned | No | 50 | CHECK 31–50 | Umbral del perfil Baja. |
| certeza_normal | tinyint unsigned | No | 70 | CHECK 51–70 | Umbral del perfil Normal. |
| certeza_alta | tinyint unsigned | No | 90 | CHECK 71–90 | Umbral del perfil Alta. |
| sensibilidad_activa | enum('Baja','Normal','Alta') | No | Normal | — | Perfil que determina qué reglas se evalúan. |
| nivel_sensibilidad | enum('Baja','Normal','Alta') | Sí | — | Generada virtual | Perfil activo expuesto a consultas anteriores. |
| nivel_certeza | tinyint unsigned | Sí | — | Generada virtual | Umbral del perfil activo expuesto a consultas anteriores. |

## reglas

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_regla | bigint unsigned | No | — | PK · Autoincremental | Identifica la regla. |
| id_usuario | bigint unsigned | No | — | FK a usuarios.id_usuario | Identifica la cuenta. |
| texto_regla | text | No | — | — | Contenido que el usuario desea filtrar, escrito en lenguaje natural. |
| activa | tinyint(1) | No | 1 | — | Indica si se aplica la regla. |
| fecha_borrado | datetime | Sí | NULL | — | Marca del borrado lógico de la regla. |
| categoria | enum('SPOILER','SPAM','HATE_SPEECH','CUSTOM_PROMPT') | No | CUSTOM_PROMPT | — | Clasificación del contenido. |
| sensibilidad | enum('Baja','Normal','Alta') | No | Normal | — | Ajuste del umbral de la regla. |
| fecha_creacion | date | Sí | NULL | — | Día en que se creó la regla. |

## feedback

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_feedback | bigint unsigned | No | — | PK · Autoincremental | Identifica el reporte. |
| id_regla | bigint unsigned | No | — | FK a reglas.id_regla | Identifica la regla. |
| texto_feedback | text | No | — | — | Explicación del usuario sobre la coincidencia. |
| fecha_emision | datetime | No | CURRENT_TIMESTAMP | — | Fecha y hora del reporte. |
| tipo_reporte | enum('censura_equivocada','faltaba_censura') | Sí | NULL | Requerido con texto_publicacion | Clasifica el error reportado desde el feed. |
| texto_publicacion | text | Sí | NULL | De 1 a 4000 caracteres si hay tipo_reporte | Fragmento de texto que el autor del reporte revisó antes de enviarlo. |

## sesiones_usuarios

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| token_hash | binary(32) | No | — | PK | Huella SHA-256 del token de sesión. |
| id_usuario | bigint unsigned | No | — | FK a usuarios.id_usuario | Identifica la cuenta. |
| vence_en | datetime | No | — | — | Vencimiento de la sesión. |

## coincidencias_diarias

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_usuario | bigint unsigned | No | — | PK · FK a usuarios.id_usuario | Identifica la cuenta. |
| fecha | date | No | — | PK | Día de la actividad en UTC. |
| total_coincidencias | bigint unsigned | No | 0 | — | Total registrado durante el período. |

## coincidencias_semanales

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_usuario | bigint unsigned | No | — | PK · FK a usuarios.id_usuario | Identifica la cuenta. |
| fecha_inicio_semana | date | No | — | PK | Lunes de la semana en UTC. |
| total_coincidencias | bigint unsigned | No | 0 | — | Total registrado durante el período. |

## coincidencias_mensuales

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_usuario | bigint unsigned | No | — | PK · FK a usuarios.id_usuario | Identifica la cuenta. |
| fecha_inicio_mes | date | No | — | PK | Primer día del mes en UTC. |
| total_coincidencias | bigint unsigned | No | 0 | — | Total registrado durante el período. |

## coincidencias_registradas

| Atributo | Tipo y longitud | Admite NULL | Predeterminado | Clave o condición | Significado |
|---|---|---|---|---|---|
| id_usuario | bigint unsigned | No | — | PK · FK a usuarios.id_usuario | Identifica la cuenta. |
| fecha | date | No | — | PK | Día de la actividad en UTC. |
| huella | binary(32) | No | — | PK | Huella SHA-256 del texto que coincidió con alguna regla. |

## Restricciones adicionales

- La certeza base admite valores de 0 a 100 en el esquema. Dashboard valida de 31 a 90 al guardar.
- Una regla borrada tiene activa en falso. Un trigger impide reactivarla o cambiar su fecha de borrado.
- Las semanas empiezan el lunes y los meses el día 1.
- Al eliminar una cuenta, sus sesiones se eliminan por cascada. El procedimiento elimina previamente los demás registros dependientes.
- La clave de coincidencias registradas evita repetir la combinación de usuario, fecha y huella.
