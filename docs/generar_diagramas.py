"""Genera cinco diagramas EER editables del esquema moderai_usuarios."""
from html import escape
from pathlib import Path

ENTIDADES = {
    "usuarios": (680, 150, 430, [
        ("PK", "id_usuario", "BIGINT UNSIGNED"), ("UK", "nickname", "VARCHAR(50)"),
        ("", "hash_contrasena", "VARCHAR(255)"), ("", "nivel_certeza", "DECIMAL(5,2)"),
        ("", "nivel_sensibilidad", "ENUM virtual")]),
    "sesiones_usuarios": (50, 155, 450, [
        ("PK", "token_hash", "BINARY(32)"), ("FK", "id_usuario", "BIGINT UNSIGNED"),
        ("", "vence_en", "DATETIME")]),
    "coincidencias_registradas": (50, 415, 450, [
        ("PK/FK", "id_usuario", "BIGINT UNSIGNED"), ("PK", "fecha", "DATE"),
        ("PK", "huella", "BINARY(32)")]),
    "reglas": (1250, 130, 500, [
        ("PK", "id_regla", "BIGINT UNSIGNED"), ("FK", "id_usuario", "BIGINT UNSIGNED"),
        ("", "texto_regla", "TEXT"), ("", "activa", "BOOLEAN"), ("", "fecha_borrado", "DATETIME NULL"),
        ("", "categoria", "ENUM"), ("", "sensibilidad", "ENUM"), ("", "fecha_creacion", "DATE NULL")]),
    "feedback": (1250, 530, 500, [
        ("PK", "id_feedback", "BIGINT UNSIGNED"), ("FK", "id_regla", "BIGINT UNSIGNED"),
        ("", "texto_feedback", "TEXT"), ("", "fecha_emision", "DATETIME"),
        ("", "tipo_reporte", "ENUM NULL"), ("", "texto_publicacion", "TEXT NULL")]),
    **{nombre: (x, 845, ancho, [
        ("PK/FK", "id_usuario", "BIGINT UNSIGNED"), ("PK", fecha, "DATE"),
        ("", "total_coincidencias", "BIGINT UNSIGNED")])
       for nombre, x, ancho, fecha in [
           ("coincidencias_diarias", 50, 510, "fecha"),
           ("coincidencias_semanales", 650, 510, "fecha_inicio_semana"),
           ("coincidencias_mensuales", 1240, 510, "fecha_inicio_mes")]},
}

# Las coordenadas señalan los puertos de tabla o de columna de una misma relación.
# Los cuatro conteos se identifican con una clave que incluye id_usuario.
RELACIONES = [
    ("inicia sesiones", False, [(680, 220), (500, 220)], [(680, 209), (578, 209), (578, 248), (500, 248)], (520, 192)),
    ("registra textos", True, [(680, 303), (610, 303), (610, 483), (500, 483)],
     [(680, 209), (622, 209), (622, 474), (500, 474)], (620, 455)),
    ("define", False, [(1110, 220), (1250, 220)], [(1110, 209), (1190, 209), (1190, 223), (1250, 223)], (1145, 192)),
    ("recibe reportes", False, [(1500, 444), (1500, 530)], [(1750, 189), (1772, 189), (1772, 623), (1750, 623)], (1515, 479)),
    ("agrupa por día", True, [(778, 362), (778, 645), (305, 645), (305, 845)],
     [(680, 209), (637, 209), (637, 648), (25, 648), (25, 904), (50, 904)], (472, 673)),
    ("agrupa por semana", True, [(893, 362), (893, 845)],
     [(1110, 209), (1135, 209), (1135, 778), (1190, 778), (1190, 904), (1160, 904)], (710, 745)),
    ("agrupa por mes", True, [(1008, 362), (1008, 790), (1495, 790), (1495, 845)],
     [(1110, 209), (1170, 209), (1170, 811), (1780, 811), (1780, 904), (1750, 904)], (1080, 816)),
]
NOTACIONES = {
    "crow-foot": ("Crow’s Foot", "Dos barras indican uno obligatorio. El círculo y la pata indican cero o muchos."),
    "classic": ("Classic", "El rombo identifica la relación. Las etiquetas indican 1 obligatorio y 0..N opcional."),
    "connect-to-columns": ("Connect to Columns", "Cada línea une la PK con la FK marcada. Una PK se vincula con cero o más filas dependientes."),
    "uml": ("UML", "Las multiplicidades 1 y 0..* se leen en los extremos de la asociación."),
    "idef1x": ("IDEF1X", "Línea continua si la FK forma parte de la PK dependiente; discontinua en otro caso."),
}


def texto(x, y, valor, tamano=17, negrita=False, ancla="start"):
    peso = 700 if negrita else 400
    return f'<text x="{x}" y="{y}" font-size="{tamano}" font-weight="{peso}" text-anchor="{ancla}">{escape(valor)}</text>'


def linea(puntos, extras=""):
    coordenadas = " ".join(f"{x},{y}" for x, y in puntos)
    return f'<polyline points="{coordenadas}" fill="none" stroke="#343434" stroke-width="2" {extras}/>'


def punto(x, y, radio=4, hueco=False):
    relleno = "white" if hueco else "#222"
    return f'<circle cx="{x}" cy="{y}" r="{radio}" fill="{relleno}" stroke="#222" stroke-width="2"/>'


def direccion(a, b):
    return tuple((y > x) - (y < x) for x, y in zip(a, b))


def extremo(borde, interior, muchos, estilo):
    dx, dy = direccion(interior, borde)
    x, y = borde

    def pos(atras, ancho=0):
        return x - dx * atras - dy * ancho, y - dy * atras + dx * ancho

    if estilo == "crow-foot":
        if muchos:
            return (linea([pos(3, -9), pos(17), pos(3, 9)])
                    + punto(*pos(26), 5, hueco=True))
        return "".join(linea([pos(n, -8), pos(n, 8)]) for n in (7, 14))
    if estilo in ("connect-to-columns", "idef1x") and muchos:
        simbolo = punto(*pos(5))
    else:
        simbolo = ""
    if estilo == "connect-to-columns":
        return simbolo
    n = ("0..*" if estilo == "uml" else "0..N") if muchos else "1"
    tx, ty = pos(26, -16)
    return simbolo + texto(tx, ty + 5, n, 17, True, "middle")


def entidad(nombre, x, y, ancho, columnas, estilo):
    alto = 42 + 34 * len(columnas)
    radio = 10 if estilo == "idef1x" and any("PK/FK" == marca for marca, *_ in columnas) else 0
    forma = f'<rect x="{x}" y="{y}" width="{ancho}" height="{alto}" rx="{radio}" fill="white" stroke="#222" stroke-width="2"/>'
    elementos = [forma, texto(x + 15, y + 28, nombre, 22, True)]
    for i, (marca, nombre_columna, tipo) in enumerate(columnas):
        fila = y + 42 + i * 34
        elementos.append(linea([(x, fila), (x + ancho, fila)]))
        elementos.append(texto(x + 13, fila + 23, marca, negrita=True))
        elementos.append(texto(x + 93, fila + 23, nombre_columna))
        elementos.append(texto(x + ancho - 14, fila + 23, tipo, 16, ancla="end"))
    return "".join(elementos)


def dibujar(estilo, titulo, leyenda):
    partes = ['<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1100" viewBox="0 0 1800 1100">',
              '<rect width="1800" height="1100" fill="white"/>',
              '<g fill="#171717" font-family="Segoe UI, Arial, sans-serif">',
              texto(50, 65, f"ModerAI · {titulo}", 37, True),
              texto(50, 99, "Esquema moderai_usuarios", 21)]
    for nombre, identificadora, bases, columnas, (lx, ly) in RELACIONES:
        ruta = columnas if estilo == "connect-to-columns" else bases
        discontinuo = 'stroke-dasharray="9 6"' if estilo == "idef1x" and not identificadora else ""
        partes.append(linea(ruta, discontinuo))
        partes.append(extremo(ruta[0], ruta[1], False, estilo))
        partes.append(extremo(ruta[-1], ruta[-2], True, estilo))
        if estilo == "classic":
            a, b = max(zip(ruta, ruta[1:]), key=lambda ab: abs(ab[0][0] - ab[1][0]) + abs(ab[0][1] - ab[1][1]))
            x, y = (a[0] + b[0]) // 2, (a[1] + b[1]) // 2
            partes.append(f'<polygon points="{x},{y-8} {x+10},{y} {x},{y+8} {x-10},{y}" fill="white" stroke="#222" stroke-width="2"/>')
        if estilo != "connect-to-columns":
            partes.append(texto(lx, ly, nombre))
    for nombre, (x, y, ancho, columnas) in ENTIDADES.items():
        partes.append(entidad(nombre, x, y, ancho, columnas, estilo))
    partes.extend((texto(50, 1037, leyenda, 19),
                   texto(50, 1069, "PK  Clave primaria · FK  Clave foránea · UK  Clave única · 0..N  Cero o muchos", 18),
                   "</g></svg>"))
    return "\n".join(partes)


if __name__ == "__main__":
    carpeta = Path(__file__).with_name("diagramas")
    carpeta.mkdir(exist_ok=True)
    for clave, (titulo, leyenda) in NOTACIONES.items():
        (carpeta / f"{clave}.svg").write_text(dibujar(clave, titulo, leyenda), encoding="utf-8")
