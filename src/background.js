// Service worker: único lugar que habla con la API (el content script queda sujeto al CORS de la página).
const ACCOUNT_API_BASE = "http://127.0.0.1:5180";
const LEGACY_API_BASE = "http://localhost:8000";
const ACCOUNT_CONFIG_KEY = "moderai_cuenta_config";
const ACCOUNT_TICKET_KEY = "moderai_vinculo_dashboard";
let identityPromise;
let rulesQueue = Promise.resolve();

async function request(base, path, method, payload, { token, credentials = "omit" } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    credentials,
    cache: "no-store",
    redirect: "error",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    signal: AbortSignal.timeout(25000),
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) })
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    const error = new Error(typeof body.detail === "string" ? body.detail : `API ${response.status}: no se pudo completar la operación`);
    error.status = response.status;
    throw error;
  }
  return response.status === 204 ? undefined : response.json();
}

async function accountRequest(path, payload = {}, method = "POST") {
  const { [ACCOUNT_TICKET_KEY]: ticket } = await chrome.storage.session.get(ACCOUNT_TICKET_KEY);
  try {
    return await request(ACCOUNT_API_BASE, `/api/cuenta/extension${path}`, method, payload, {
      token: ticket, credentials: ticket ? "omit" : "include",
    });
  } catch (error) {
    if (error.status === 401) {
      const actual = await chrome.storage.session.get(ACCOUNT_TICKET_KEY);
      if (actual[ACCOUNT_TICKET_KEY] === ticket) {
        await chrome.storage.session.remove(ACCOUNT_TICKET_KEY);
        await chrome.storage.local.remove(ACCOUNT_CONFIG_KEY);
      }
    }
    throw error;
  }
}

async function linkedConfiguration() {
  let config;
  try {
    config = await accountRequest("/configuracion");
  } catch (error) {
    if (error.status === 401) return { vinculada: false };
    throw error;
  }
  const saved = await chrome.storage.local.get(ACCOUNT_CONFIG_KEY);
  if (JSON.stringify(saved[ACCOUNT_CONFIG_KEY]) !== JSON.stringify(config)) {
    await chrome.storage.local.set({ [ACCOUNT_CONFIG_KEY]: config });
  }
  return { ...config, vinculada: true };
}

function identity() {
  if (!identityPromise) identityPromise = (async () => {
    let { moderai_token } = await chrome.storage.local.get("moderai_token");
    if (!moderai_token) {
      moderai_token = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, "0")).join("");
      await chrome.storage.local.set({ moderai_token });
    }
    await request(LEGACY_API_BASE, "/api/instalacion", "POST", undefined, { token: moderai_token });
    return moderai_token;
  })().catch(error => { identityPromise = null; throw error; });
  return identityPromise;
}

async function rulesMessage(msg) {
  const session = await linkedConfiguration().catch(async (error) => {
    const cached = await chrome.storage.local.get(ACCOUNT_CONFIG_KEY);
    if (msg.type === "reglas_crear" || cached[ACCOUNT_CONFIG_KEY] || error.status) throw error;
    return { vinculada: false };
  });
  if (msg.type !== "reglas_listar" && msg.idCuenta && session.id_usuario !== msg.idCuenta) {
    throw new Error("Tu sesión cambió. Abre Cuenta y vuelve a intentarlo.");
  }
  if (msg.type === "reglas_estado") {
    if (!session.vinculada) throw new Error("Inicia sesión en ModerAI para cambiar el estado.");
    const { id_regla, activa } = msg.payload;
    await accountRequest(`/reglas/${encodeURIComponent(id_regla)}`, { activa }, "PATCH");
    const { vinculada, ...config } = session;
    config.reglas = config.reglas.map(regla => regla.id_regla === id_regla ? { ...regla, activa } : regla);
    await chrome.storage.local.set({ [ACCOUNT_CONFIG_KEY]: config }).catch(() => {});
    return { ...config, vinculada };
  }
  if (session.vinculada) {
    if (msg.type !== "reglas_crear") return session;
    const { prompt, categoria, sensibilidad } = msg.payload;
    const saved = await accountRequest("/reglas", { texto_regla: prompt, categoria, sensibilidad });
    const rule = { ...saved, prompt: prompt.trim(), categoria, sensibilidad, activa: true };
    if (rule.id_usuario === session.id_usuario) {
      const { vinculada, ...config } = session;
      await chrome.storage.local.set({
        [ACCOUNT_CONFIG_KEY]: { ...config, reglas: config.reglas.concat(rule) },
      }).catch(() => {});
    }
    return { ...rule, vinculada: true };
  }
  if (msg.type === "reglas_crear") {
    throw new Error("Inicia sesión en ModerAI desde Cuenta y vuelve a guardar.");
  }
  const token = await identity();
  const data = await request(LEGACY_API_BASE, "/api/reglas", "GET", undefined, { token });
  const previous = await chrome.storage.local.get(["regla_filtro", "reglas_locales_respaldo"]);
  if (!previous.reglas_locales_respaldo && previous.regla_filtro?.some(r => r.id_usuario === "usr_local_123")) {
    await chrome.storage.local.set({ reglas_locales_respaldo: previous.regla_filtro });
  }
  await chrome.storage.local.set({ regla_filtro: data.reglas });
  return data;
}

async function evaluatePosts(payload) {
  const cached = await chrome.storage.local.get(ACCOUNT_CONFIG_KEY);
  if (!cached[ACCOUNT_CONFIG_KEY]) return request(LEGACY_API_BASE, "/api/evaluar", "POST", payload);
  return accountRequest("/evaluar", {
    posts: payload.posts.map(({ id, texto }) => ({ id, texto: Array.from(texto).slice(0, 4000).join("") })),
  });
}

async function abrirReporte({ tipo, texto, idRegla, idCuenta }) {
  const { borrador } = await accountRequest("/reportes/borrador", {
    tipo, publicacion: Array.from(texto).slice(0, 4000).join(""), idRegla, idCuenta,
  });
  const url = new URL("/Reportes", ACCOUNT_API_BASE);
  url.searchParams.set("borrador", borrador);
  await chrome.tabs.create({ url: url.href });
}

function respond(operation, sendResponse) {
  operation.then(data => sendResponse({ ok: true, data }))
    .catch(error => sendResponse({ ok: false, error: error.message }));
  return true;
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const senderUrl = (sender.url || "").split(/[?#]/, 1)[0];
  const ownOptions = senderUrl === chrome.runtime.getURL("src/options/options.html");
  const ownPopup = senderUrl === chrome.runtime.getURL("src/popup/popup.html");
  const xPage = /^https:\/\/(x\.com|twitter\.com)\//.test(senderUrl);
  if (msg?.type === "vincular_cuenta"
      && sender.frameId === 0
      && senderUrl.replace(/\/$/, "").toLowerCase() === new URL("/Dashboard", ACCOUNT_API_BASE).href.toLowerCase()) {
    const operation = rulesQueue.then(async () => {
      if (msg.ticket === null) {
        await chrome.storage.session.remove(ACCOUNT_TICKET_KEY);
        await chrome.storage.local.remove(ACCOUNT_CONFIG_KEY);
        return { vinculada: false };
      }
      if (typeof msg.ticket !== "string" || !/^[A-Za-z0-9_-]{20,1000}$/.test(msg.ticket)) {
        throw new Error("Vínculo de Dashboard inválido.");
      }
      await chrome.storage.session.set({ [ACCOUNT_TICKET_KEY]: msg.ticket });
      return linkedConfiguration();
    });
    rulesQueue = operation.catch(() => {});
    return respond(operation, sendResponse);
  }
  if (msg?.type === "dashboard_url") {
    if (ownOptions || ownPopup) sendResponse(new URL("/Dashboard?seccion=cuenta", ACCOUNT_API_BASE).href);
    return;
  }
  if (msg?.type === "cuenta_estado") {
    if (!ownOptions && !ownPopup && !xPage) return;
    const operation = rulesQueue.then(linkedConfiguration);
    rulesQueue = operation.catch(() => {});
    return respond(operation, sendResponse);
  }
  if (["reglas_listar", "reglas_crear", "reglas_estado"].includes(msg?.type)) {
    if (msg.type !== "reglas_listar" && !ownOptions) return;
    const operation = rulesQueue.then(() => rulesMessage(msg));
    rulesQueue = operation.catch(() => {});
    return respond(operation, sendResponse);
  }
  if (msg?.type === "evaluar" && xPage) return respond(evaluatePosts(msg.payload), sendResponse);
  if (msg?.type === "abrir_reporte" && xPage && typeof msg.texto === "string") {
    return respond(abrirReporte(msg), sendResponse);
  }
});
