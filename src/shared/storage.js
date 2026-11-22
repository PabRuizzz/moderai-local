/**
 * storage.js
 * Simula la tabla `regla_filtro` (y `usuario_config`) del esquema db/legado/schema.sql
 * usando localStorage, para que el Task Flow 1 se pueda recorrer sin backend.
 * Cada fila que aquí se guarda es exactamente la que se vería en la tabla real.
 */
const ModerAIStorage = (() => {
  const USER_ID = "usr_local_123";
  let cuentaExtension;

  function get(key, fallback) {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  }
  function set(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
    // En la extensión: espejo en chrome.storage.local, que sí leen el content script y el service worker
    try { if (typeof chrome !== "undefined" && chrome.storage?.local) chrome.storage.local.set({ [key]: value }); } catch (e) {}
  }

  function getUsuarioConfig() {
    return get("usuario_config", {
      id_usuario: USER_ID,
      activo: 1,
      nivel_sensibilidad: 70,
      pin_hash: null,
      nip_activo: 0,
      intentos_fallidos: 0,
      bloqueado_hasta: null
    });
  }
  function setUsuarioConfig(cfg) {
    set("usuario_config", cfg);
  }

  // Fila con EXACTAMENTE las columnas de la tabla regla_filtro (db/legado/schema.sql)
  function getReglas() {
    return cuentaExtension?.reglas ?? get("regla_filtro", []);
  }
  async function reglasRemotas(type, payload, idCuenta) {
    const response = await chrome.runtime.sendMessage({ type, payload, idCuenta });
    if (!response?.ok) throw new Error(response?.error || "No se pudo conectar con el servidor");
    return response.data;
  }
  async function sincronizarReglas() {
    if (location.protocol !== "chrome-extension:") return;
    const data = await reglasRemotas("reglas_listar");
    setCuentaExtension(data.vinculada ? data : null);
    if (data.vinculada) return;
    if (!localStorage.getItem("reglas_locales_respaldo")) {
      localStorage.setItem("reglas_locales_respaldo", JSON.stringify(getReglas()));
    }
    localStorage.setItem("regla_filtro", JSON.stringify(data.reglas));
    const cfg = getUsuarioConfig();
    cfg.id_usuario = data.id_usuario;
    setUsuarioConfig(cfg);
  }

  function setCuentaExtension(config) {
    cuentaExtension = config;
  }

  function getCuentaExtension() {
    return cuentaExtension;
  }
  async function cambiarEstadoRegla(idRegla, activa) {
    if (!cuentaExtension) throw new Error("Inicia sesión en ModerAI para cambiar el estado.");
    const data = await reglasRemotas("reglas_estado", { id_regla: idRegla, activa }, cuentaExtension.id_usuario);
    if (cuentaExtension?.id_usuario === data.id_usuario) setCuentaExtension(data);
  }

  async function guardarRegla(row) {
    const saved = await reglasRemotas("reglas_crear", {
      prompt: row.prompt, categoria: row.categoria, sensibilidad: row.sensibilidad
    }, cuentaExtension?.id_usuario);
    const config = getCuentaExtension();
    if (config?.id_usuario === saved.id_usuario && !config.reglas.some(r => r.id_regla === saved.id_regla)) {
      setCuentaExtension({ ...config, reglas: config.reglas.concat(saved) });
    } else if (config?.id_usuario !== saved.id_usuario) {
      await sincronizarReglas().catch(() => {});
    }
    return saved;
  }

  async function hashPin(pin) {
    const enc = new TextEncoder().encode(`moderai:${pin}`);
    const digest = await crypto.subtle.digest("SHA-256", enc);
    return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  const hoy = () => new Date().toISOString().slice(0, 10);
  function getHistorial() { return get("historial_moderacion", []); }
  function getBloqueosHoy() {
    return cuentaExtension
      ? BigInt(cuentaExtension.coincidencias_hoy).toLocaleString("es-MX")
      : getHistorial().filter((h) => h.fecha_evaluacion === hoy() && h.accion_aplicada === "DIFUMINADO").length;
  }

  function resetAll() {
    try { if (typeof chrome !== "undefined" && chrome.storage?.local) chrome.storage.local.remove(["regla_filtro", "usuario_config", "historial_moderacion", "posts_usuario", "correccion_usuario"]); } catch (e) {}
    localStorage.removeItem("regla_filtro");
    localStorage.removeItem("usuario_config");
    localStorage.removeItem("historial_moderacion");
    localStorage.removeItem("posts_usuario");
    localStorage.removeItem("correccion_usuario");
  }

  return {
    USER_ID, getUsuarioConfig, setUsuarioConfig, getReglas, sincronizarReglas,
    guardarRegla, cambiarEstadoRegla, hashPin, resetAll, getBloqueosHoy, getCuentaExtension, setCuentaExtension,
  };
})();
