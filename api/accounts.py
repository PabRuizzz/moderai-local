"""Dashboard web con sesiones privadas y persistencia en MySQL."""

import hashlib
import os
import re
import secrets
import time
from contextlib import contextmanager
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP
from threading import Lock
from typing import Annotated, Literal

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import APIRouter, HTTPException, Path, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from pydantic import BaseModel, ConfigDict, Field, SecretStr, StringConstraints

from api.database import connect_database

COOKIE = "moderai_session"
SESSION_HOURS = 8
MAX_ID = 2**64 - 1
MIN_CERTAINTY = 31
MAX_CERTAINTY = 90
EXTENSION_ID = os.getenv("MODERAI_EXTENSION_ID", "kalifemlanoldmeofgfpnjkeaonadpfe")
if not re.fullmatch(r"[a-p]{32}", EXTENSION_ID):
    raise ValueError("MODERAI_EXTENSION_ID debe contener el ID de Chrome de 32 letras")
EXTENSION_ORIGIN = f"chrome-extension://{EXTENSION_ID}"
EXTENSION_API_PATH = "/api/cuenta/extension"
RuleId = Annotated[int, Path(gt=0, le=MAX_ID)]
passwords = PasswordHasher()
dummy_hash = passwords.hash(secrets.token_urlsafe(32))
attempt_lock = Lock()
attempts = {}
attempt_window = -1
total_attempts = 0


class PrivateRoute(APIRoute):
    def validate_origin(self, request):
        origin = f"{request.url.scheme}://{request.url.netloc}"
        if request.method != "GET" and request.headers.get("origin") != origin:
            raise HTTPException(403, "Origen de solicitud inválido")

    def get_route_handler(self):
        handler = super().get_route_handler()

        async def handle(request):
            try:
                if request.url.scheme != "https" and (
                    request.url.scheme != "http"
                    or request.url.hostname not in {"localhost", "127.0.0.1", "::1"}
                ):
                    raise HTTPException(403, "Abre el dashboard mediante HTTPS")
                self.validate_origin(request)
                response = await handler(request)
            except RequestValidationError:
                # FastAPI puede incluir valores de entrada en el error por defecto.
                raise HTTPException(422, "Revisa los datos del formulario", headers={"Cache-Control": "no-store"}) from None
            except HTTPException as exc:
                exc.headers = {**(exc.headers or {}), "Cache-Control": "no-store"}
                raise
            response.headers["Cache-Control"] = "no-store"
            return response

        return handle


router = APIRouter(prefix="/api/cuenta", route_class=PrivateRoute)


class ExtensionRoute(PrivateRoute):
    def validate_origin(self, request):
        if request.headers.get("origin") != EXTENSION_ORIGIN:
            raise HTTPException(403, "Origen de extensión no autorizado")


extension_router = APIRouter(prefix=EXTENSION_API_PATH, route_class=ExtensionRoute)


class AccountData(BaseModel):
    model_config = ConfigDict(extra="forbid")
    nickname: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)]
    contrasena: SecretStr = Field(min_length=1, max_length=128)


class Settings(BaseModel):
    model_config = ConfigDict(extra="forbid")
    nivel_certeza: int = Field(ge=MIN_CERTAINTY, le=MAX_CERTAINTY, strict=True)


class RuleText(BaseModel):
    model_config = ConfigDict(extra="forbid")
    texto_regla: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]
    categoria: Literal["SPOILER", "SPAM", "HATE_SPEECH", "CUSTOM_PROMPT"] = "CUSTOM_PROMPT"
    sensibilidad: Literal["Baja", "Normal", "Alta"] = "Normal"


class RuleState(BaseModel):
    model_config = ConfigDict(extra="forbid")
    activa: bool


class FeedbackText(BaseModel):
    model_config = ConfigDict(extra="forbid")
    texto_feedback: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]


@contextmanager
def transaction():
    try:
        with connect_database(accounts=True) as connection, connection.cursor(dictionary=True) as cursor:
            try:
                yield cursor
                connection.commit()
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "La base de datos de cuentas no está disponible") from None


def rate_limit(request):
    global attempt_window, total_attempts
    address = request.client.host if request.client else ""
    window = int(time.monotonic() // 60)
    with attempt_lock:
        if window != attempt_window:
            attempts.clear()
            total_attempts = 0
            attempt_window = window
        if total_attempts >= 40 or attempts.get(address, 0) >= 8:
            raise HTTPException(429, "Demasiados intentos. Espera un minuto.", headers={"Retry-After": "60"})
        attempts[address] = attempts.get(address, 0) + 1
        total_attempts += 1


def cookie_digest(request):
    token = request.cookies.get(COOKIE, "")
    if len(token) == 64 and all(char in "0123456789abcdef" for char in token):
        return hashlib.sha256(token.encode("ascii")).digest()
    return None


def effective_certainty(value):
    rounded = int(Decimal(value).to_integral_value(rounding=ROUND_HALF_UP))
    return min(MAX_CERTAINTY, max(MIN_CERTAINTY, rounded))


def user_from_session(cursor, digest):
    if digest is not None:
        cursor.execute(
            """SELECT u.id_usuario, u.nickname, u.nivel_certeza, u.sensibilidad_activa
               FROM sesiones_usuarios AS s JOIN usuarios AS u USING (id_usuario)
               WHERE s.token_hash = %s AND s.vence_en > UTC_TIMESTAMP()""",
            (digest,),
        )
        user = cursor.fetchone()
        if user:
            user["nivel_certeza"] = effective_certainty(user["nivel_certeza"])
            return user
    raise HTTPException(401, "Inicia sesión para continuar")


def current_user(cursor, request):
    return user_from_session(cursor, cookie_digest(request))


def require_session(request):
    digest = cookie_digest(request)
    if digest is None:
        raise HTTPException(401, "Inicia sesión para continuar")
    return digest


def new_session(cursor, request, user_id):
    token = secrets.token_hex(32)
    cursor.execute(
        "DELETE FROM sesiones_usuarios WHERE id_usuario = %s AND vence_en <= UTC_TIMESTAMP()",
        (user_id,),
    )
    old_digest = cookie_digest(request)
    if old_digest is not None:
        cursor.execute("DELETE FROM sesiones_usuarios WHERE token_hash = %s", (old_digest,))
    cursor.execute(
        """INSERT INTO sesiones_usuarios (token_hash, id_usuario, vence_en)
           VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL %s HOUR))""",
        (hashlib.sha256(token.encode("ascii")).digest(), user_id, SESSION_HOURS),
    )
    return token


def set_session(response, request, token):
    response.set_cookie(
        COOKIE, token, max_age=SESSION_HOURS * 3600, path="/api/cuenta",
        secure=request.url.scheme == "https", httponly=True, samesite="strict",
    )


@router.post("/registro", status_code=201)
def register(data: AccountData, request: Request, response: Response):
    from mysql.connector.errors import IntegrityError

    rate_limit(request)
    password = data.contrasena.get_secret_value()
    if len(password) < 12:
        raise HTTPException(422, "La contraseña debe tener al menos 12 caracteres")
    password_hash = passwords.hash(password)
    with transaction() as cursor:
        try:
            cursor.execute(
                "INSERT INTO usuarios (nickname, hash_contrasena) VALUES (%s, %s)",
                (data.nickname, password_hash),
            )
        except IntegrityError as exc:
            if exc.errno == 1062:
                raise HTTPException(409, "Ese nickname no está disponible") from None
            raise
        token = new_session(cursor, request, cursor.lastrowid)
    set_session(response, request, token)
    return {"ok": True}


@router.post("/sesion")
def login(data: AccountData, request: Request, response: Response):
    rate_limit(request)
    with transaction() as cursor:
        cursor.execute(
            "SELECT id_usuario, hash_contrasena FROM usuarios WHERE nickname = %s",
            (data.nickname,),
        )
        user = cursor.fetchone()
        stored_hash = user["hash_contrasena"] if user else dummy_hash
        password = data.contrasena.get_secret_value()
        try:
            passwords.verify(stored_hash, password)
        except (VerificationError, InvalidHashError):
            raise HTTPException(401, "Nickname o contraseña incorrectos") from None
        if not user:
            raise HTTPException(401, "Nickname o contraseña incorrectos")
        if passwords.check_needs_rehash(stored_hash):
            cursor.execute(
                "UPDATE usuarios SET hash_contrasena = %s WHERE id_usuario = %s AND hash_contrasena = %s",
                (passwords.hash(password), user["id_usuario"], stored_hash),
            )
        token = new_session(cursor, request, user["id_usuario"])
    set_session(response, request, token)
    return {"ok": True}


@router.delete("/sesion", status_code=204)
def logout(request: Request, response: Response):
    digest = cookie_digest(request)
    if digest is not None:
        with transaction() as cursor:
            cursor.execute("DELETE FROM sesiones_usuarios WHERE token_hash = %s", (digest,))
    response.delete_cookie(
        COOKIE, path="/api/cuenta", secure=request.url.scheme == "https", httponly=True, samesite="strict",
    )


@extension_router.post("/configuracion")
def linked_settings(request: Request):
    digest = require_session(request)
    with transaction() as cursor:
        user = user_from_session(cursor, digest)
        user_id = user["id_usuario"]
        cursor.execute(
            """SELECT CAST(id_regla AS CHAR) AS id_regla, texto_regla AS prompt, activa, categoria, sensibilidad
               FROM reglas WHERE id_usuario = %s AND fecha_borrado IS NULL ORDER BY reglas.id_regla""",
            (user_id,),
        )
        rules = cursor.fetchall()
        cursor.execute(
            """SELECT CAST(total_coincidencias AS CHAR) AS total
               FROM coincidencias_diarias WHERE id_usuario = %s AND fecha = UTC_DATE()""",
            (user_id,),
        )
        today = cursor.fetchone()
    return {
        "id_usuario": str(user_id), "nickname": user["nickname"], "nivel_certeza": user["nivel_certeza"],
        "sensibilidad_activa": user["sensibilidad_activa"],
        "reglas": rules, "coincidencias_hoy": today["total"] if today else "0",
    }


@router.get("/dashboard")
def dashboard(request: Request):
    require_session(request)
    with transaction() as cursor:
        user = current_user(cursor, request)
        user_id = user["id_usuario"]
        cursor.execute(
            """SELECT CAST(id_regla AS CHAR) AS id_regla, texto_regla, activa, categoria, sensibilidad, fecha_creacion
               FROM reglas WHERE id_usuario = %s AND fecha_borrado IS NULL ORDER BY reglas.id_regla DESC""",
            (user_id,),
        )
        rules = cursor.fetchall()
        cursor.execute(
            """SELECT f.texto_feedback, f.fecha_emision, r.texto_regla
               FROM feedback AS f JOIN reglas AS r USING (id_regla)
               WHERE r.id_usuario = %s ORDER BY f.fecha_emision DESC, f.id_feedback DESC LIMIT 50""",
            (user_id,),
        )
        reports = cursor.fetchall()
        cursor.execute("SELECT UTC_DATE() AS hoy")
        today = cursor.fetchone()["hoy"]
        periods = {}
        for period, date_column, condition in (
            ("diarias", "fecha", ">= %s - INTERVAL 29 DAY"),
            ("semanales", "fecha_inicio_semana", ">= %s - INTERVAL 1 YEAR"),
            ("mensuales", "fecha_inicio_mes", "> %s - INTERVAL 3 YEAR"),
        ):
            # Los identificadores y expresiones proceden de las constantes de arriba.
            cursor.execute(
                f"""SELECT {date_column} AS fecha, CAST(total_coincidencias AS CHAR) AS total_coincidencias
                    FROM coincidencias_{period} WHERE id_usuario = %s AND {date_column} {condition}
                    AND {date_column} <= %s ORDER BY {date_column} DESC""",
                (user_id, today, today),
            )
            periods[period] = cursor.fetchall()
    return {
        "usuario": {"id_usuario": str(user_id), "nickname": user["nickname"], "nivel_certeza": user["nivel_certeza"]},
        "reglas": rules,
        "feedback": reports,
        "coincidencias": {
            "hoy": next((row["total_coincidencias"] for row in periods["diarias"] if row["fecha"] == today), "0"),
            "total": str(sum(int(row["total_coincidencias"]) for row in periods["mensuales"])),
            **periods,
        },
    }


@router.patch("/configuracion", status_code=204)
def update_settings(data: Settings, request: Request):
    with transaction() as cursor:
        user = current_user(cursor, request)
        nivel = data.nivel_certeza
        if nivel <= 50:
            perfil, columna = "Baja", "certeza_baja"
        elif nivel <= 70:
            perfil, columna = "Normal", "certeza_normal"
        else:
            perfil, columna = "Alta", "certeza_alta"
        cursor.execute(
            f"UPDATE usuarios SET sensibilidad_activa = %s, {columna} = %s WHERE id_usuario = %s",
            (perfil, nivel, user["id_usuario"]),
        )


@router.post("/reglas", status_code=201)
@extension_router.post("/reglas", status_code=201)
def create_rule(data: RuleText, request: Request):
    with transaction() as cursor:
        user = current_user(cursor, request)
        cursor.execute(
            """INSERT INTO reglas (id_usuario, texto_regla, categoria, sensibilidad, fecha_creacion)
               VALUES (%s, %s, %s, %s, UTC_DATE())""",
            (user["id_usuario"], data.texto_regla, data.categoria, data.sensibilidad),
        )
        return {"id_regla": str(cursor.lastrowid), "id_usuario": str(user["id_usuario"])}


def lock_rule(cursor, user_id, rule_id):
    cursor.execute(
        """SELECT id_regla FROM reglas
           WHERE id_regla = %s AND id_usuario = %s AND fecha_borrado IS NULL FOR UPDATE""",
        (rule_id, user_id),
    )
    if cursor.fetchone() is None:
        raise HTTPException(404, "Regla no encontrada")


@router.patch("/reglas/{rule_id}", status_code=204)
@extension_router.patch("/reglas/{rule_id}", status_code=204)
def set_rule_state(rule_id: RuleId, data: RuleState, request: Request):
    with transaction() as cursor:
        user = current_user(cursor, request)
        lock_rule(cursor, user["id_usuario"], rule_id)
        cursor.execute(
            "UPDATE reglas SET activa = %s WHERE id_regla = %s AND id_usuario = %s",
            (data.activa, rule_id, user["id_usuario"]),
        )


@router.delete("/reglas/{rule_id}", status_code=204)
def delete_rule(rule_id: RuleId, request: Request):
    with transaction() as cursor:
        user = current_user(cursor, request)
        lock_rule(cursor, user["id_usuario"], rule_id)
        cursor.execute(
            "UPDATE reglas SET activa = FALSE, fecha_borrado = UTC_TIMESTAMP() WHERE id_regla = %s AND id_usuario = %s",
            (rule_id, user["id_usuario"]),
        )


@router.post("/reglas/{rule_id}/feedback", status_code=204)
def add_feedback(rule_id: RuleId, data: FeedbackText, request: Request):
    with transaction() as cursor:
        user = current_user(cursor, request)
        lock_rule(cursor, user["id_usuario"], rule_id)
        cursor.execute(
            "INSERT INTO feedback (id_regla, texto_feedback, fecha_emision) VALUES (%s, %s, UTC_TIMESTAMP())",
            (rule_id, data.texto_feedback),
        )


def moderation_settings(digest):
    with transaction() as cursor:
        user = user_from_session(cursor, digest)
        cursor.execute(
            """SELECT id_regla, texto_regla AS prompt, categoria, sensibilidad
               FROM reglas WHERE id_usuario = %s AND activa = TRUE AND fecha_borrado IS NULL
                 AND sensibilidad = %s
               ORDER BY id_regla""",
            (user["id_usuario"], user["sensibilidad_activa"]),
        )
        return user, cursor.fetchall()


def record_matches(digest, user_id, fingerprints):
    if not fingerprints:
        return
    with transaction() as cursor:
        user = user_from_session(cursor, digest)
        if user["id_usuario"] != user_id:
            raise HTTPException(401, "Inicia sesión para continuar")
        # Serializa los conteos de una cuenta cuando llegan varias evaluaciones a la vez.
        cursor.execute("SELECT id_usuario FROM usuarios WHERE id_usuario = %s FOR UPDATE", (user_id,))
        cursor.fetchone()
        cursor.execute("SELECT UTC_DATE() AS hoy")
        today = cursor.fetchone()["hoy"]
        cursor.executemany(
            "INSERT IGNORE INTO coincidencias_registradas (id_usuario, fecha, huella) VALUES (%s, %s, %s)",
            [(user_id, today, fingerprint) for fingerprint in sorted(fingerprints)],
        )
        new_matches = cursor.rowcount
        if new_matches <= 0:
            return
        for period, column, date in (
            ("diarias", "fecha", today),
            ("semanales", "fecha_inicio_semana", today - timedelta(days=today.weekday())),
            ("mensuales", "fecha_inicio_mes", today.replace(day=1)),
        ):
            cursor.execute(
                f"""INSERT INTO coincidencias_{period} (id_usuario, {column}, total_coincidencias)
                    VALUES (%s, %s, %s) ON DUPLICATE KEY UPDATE total_coincidencias = total_coincidencias + %s""",
                (user_id, date, new_matches, new_matches),
            )
