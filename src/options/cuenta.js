"use strict";

const byId = (id) => document.getElementById(id);
const access = byId("acceso");
const account = byId("cuenta");
const logout = byId("cerrarSesion");
const password = byId("contrasena");
const accessButton = byId("acceder");
const switchButton = byId("alternarAcceso");
const actions = byId("accionesCuenta");
let registering = false;
let dashboard;
let dashboardRequest = 0;
let working = false;
const channel = typeof BroadcastChannel === "function" ? new BroadcastChannel("moderai-cuenta") : null;

async function api(path, method = "GET", body) {
  const options = { method, mode: "same-origin", credentials: "same-origin", cache: "no-store" };
  if (body !== undefined) {
    options.headers = { "Content-Type": "application/json" };
    options.body = JSON.stringify(body);
  }
  const response = await fetch(`/api/cuenta${path}`, options);
  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    const error = new Error(typeof data.detail === "string" ? data.detail : "No se pudo completar la solicitud.");
    error.status = response.status;
    throw error;
  }
  if (response.status !== 204) return response.json();
}

function status(message, error = false) {
  const element = byId("cuentaEstado");
  element.hidden = !message;
  element.classList.toggle("text-danger", error);
  element.textContent = message;
}

function applyCertaintyRange(value) {
  const input = byId("nivelCerteza");
  const { min, max } = byId("rangoCerteza").selectedOptions[0].dataset;
  input.min = min;
  input.max = max;
  input.value = Number.isFinite(value) ? Math.min(Number(max), Math.max(Number(min), value)) : min;
}

function signedOut() {
  dashboardRequest++;
  dashboard = undefined;
  account.hidden = true;
  logout.hidden = true;
  byId("usuarioActual").textContent = "";
  byId("nivelCerteza").value = "";
  byId("feedbackCuenta").hidden = true;
  byId("feedbackSinSesion").hidden = false;
  byId("historialFeedback").replaceChildren();
  byId("historialCoincidencias").replaceChildren();
  byId("totalCoincidencias").textContent = "0";
  byId("coincidenciasCuenta").hidden = true;
  byId("coincidenciasSinSesion").hidden = false;
  access.hidden = false;
  document.dispatchEvent(new Event("moderai:cuenta"));
}

async function refreshDashboard() {
  const request = ++dashboardRequest;
  let current;
  try {
    current = await api("/dashboard");
  } catch (error) {
    if (request !== dashboardRequest) return;
    throw error;
  }
  if (request !== dashboardRequest) return;
  if (dashboard && JSON.stringify(dashboard) === JSON.stringify(current)) return;
  const previousUser = dashboard?.usuario;
  dashboard = current;
  byId("usuarioActual").textContent = dashboard.usuario.nickname;
  if (previousUser?.id_usuario !== dashboard.usuario.id_usuario
      || previousUser?.nivel_certeza !== dashboard.usuario.nivel_certeza) {
    const level = Number(dashboard.usuario.nivel_certeza);
    const selector = byId("rangoCerteza");
    const range = Array.from(selector.options).find(({ dataset }) => level <= Number(dataset.max));
    selector.value = (range ?? selector.options[selector.options.length - 1]).value;
    applyCertaintyRange(level);
  }
  byId("totalCoincidencias").textContent = formatTotal(dashboard.coincidencias.total);
  renderPeriods();
  byId("coincidenciasCuenta").hidden = false;
  byId("coincidenciasSinSesion").hidden = true;
  renderFeedback();
  byId("feedbackCuenta").hidden = false;
  byId("feedbackSinSesion").hidden = true;
  access.hidden = true;
  account.hidden = false;
  logout.hidden = false;
  document.dispatchEvent(new Event("moderai:cuenta"));
}

function refreshInBackground() {
  if (working || accessButton.disabled || logout.disabled) return;
  refreshDashboard().catch((error) => {
    if (error.status === 401) signedOut();
    else status(error.message, true);
  });
}

function formatTotal(value) {
  return BigInt(value).toLocaleString("es-MX");
}

function element(tag, className, value) {
  const node = document.createElement(tag);
  node.className = className;
  node.textContent = value;
  return node;
}

function renderPeriods() {
  if (!dashboard) return;
  const rows = dashboard.coincidencias[byId("periodo").value];
  const table = byId("historialCoincidencias");
  table.replaceChildren();
  for (const row of rows) {
    const tr = document.createElement("tr");
    tr.append(element("td", "", row.fecha), element("td", "", formatTotal(row.total_coincidencias)));
    table.append(tr);
  }
  byId("tablaCoincidencias").hidden = rows.length === 0;
  byId("sinCoincidencias").hidden = rows.length > 0;
}

function renderFeedback() {
  const list = byId("historialFeedback");
  list.replaceChildren();
  for (const report of dashboard.feedback) {
    const item = element("li", "list-group-item px-0", "");
    item.append(
      element("p", "mb-1 text-break", report.texto_feedback),
      element("small", "text-secondary text-break", `${report.texto_regla} · ${report.fecha_emision.replace("T", " ")} UTC`),
    );
    list.append(item);
  }
  byId("sinFeedback").hidden = dashboard.feedback.length > 0;
}

async function update(path, method, body, message, { form, notify = status } = {}) {
  if (working) {
    notify("Hay otro cambio guardándose. Intenta de nuevo en un momento.", true);
    return false;
  }
  working = true;
  actions.disabled = true;
  logout.disabled = true;
  let saved = false;
  try {
    await api(path, method, body);
    saved = true;
    form?.reset();
    if (path.startsWith("/reglas")) channel?.postMessage("reglas");
    await refreshDashboard();
    notify(message);
  } catch (error) {
    if (error.status === 401) signedOut();
    if (saved) notify("Cambio guardado. Recarga la página para actualizar el dashboard.", true);
    else if (error.status === 401) notify("Inicia sesión en ModerAI desde Cuenta y vuelve a guardar.", true);
    else notify(error.message, true);
  } finally {
    working = false;
    actions.disabled = false;
    logout.disabled = false;
  }
  return saved;
}

function initializeAccountDashboard() {
  switchButton.addEventListener("click", () => {
    registering = !registering;
    password.value = "";
    password.autocomplete = registering ? "new-password" : "current-password";
    password.minLength = registering ? 12 : 1;
    byId("ayudaContrasena").hidden = !registering;
    accessButton.textContent = registering ? "Crear cuenta" : "Iniciar sesión";
    byId("accesoTitulo").textContent = accessButton.textContent;
    switchButton.textContent = registering ? "Volver a iniciar sesión" : "Crear cuenta";
  });

  byId("formAcceso").addEventListener("submit", async (event) => {
    event.preventDefault();
    accessButton.disabled = switchButton.disabled = true;
    let signedIn = false;
    try {
      await api(registering ? "/registro" : "/sesion", "POST", {
        nickname: byId("nickname").value,
        contrasena: password.value,
      });
      signedIn = true;
      channel?.postMessage("sesion");
      await refreshDashboard();
      status("");
    } catch (error) {
      status(signedIn ? "Sesión iniciada. Recarga la página para abrir el dashboard." : error.message, true);
    } finally {
      password.value = "";
      accessButton.disabled = switchButton.disabled = false;
    }
  });

  logout.addEventListener("click", async () => {
    logout.disabled = actions.disabled = true;
    try {
      await api("/sesion", "DELETE");
      signedOut();
      channel?.postMessage("sesion");
      status("Sesión cerrada.");
    } catch (error) {
      status(error.message, true);
    } finally {
      logout.disabled = actions.disabled = false;
    }
  });

  byId("periodo").addEventListener("change", renderPeriods);
  byId("rangoCerteza").addEventListener("change", () => {
    applyCertaintyRange(byId("nivelCerteza").valueAsNumber);
  });
  byId("formCerteza").addEventListener("submit", (event) => {
    event.preventDefault();
    update("/configuracion", "PATCH", { nivel_certeza: byId("nivelCerteza").valueAsNumber }, "Nivel guardado.");
  });
  return refreshDashboard().then(() => status("")).catch((error) => {
    if (error.status === 401) signedOut();
    status(error.status === 401 ? "" : error.message, error.status !== 401);
  });
}

if (["http:", "https:"].includes(location.protocol)) {
  byId("configuracionCuenta").hidden = false;
  window.ModerAICuenta = {
    get datos() { return dashboard; },
    listo: initializeAccountDashboard(),
    update,
  };

  channel?.addEventListener("message", ({ data }) => {
    if (data === "sesion" || data === "reglas") refreshInBackground();
  });
  window.addEventListener("focus", refreshInBackground);
  document.addEventListener("moderai:pestana", ({ detail }) => {
    if (dashboard && ["cuenta", "prompts", "coincidencias"].includes(detail)) refreshInBackground();
  });
  setInterval(() => {
    if (dashboard && !document.hidden) refreshInBackground();
  }, 15000);
}
