const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function pintar() {
  const activas = ModerAIStorage.getReglas().filter((r) => r.activa);
  const cuenta = ModerAIStorage.getCuentaExtension();
  $("estadoCuentaPopup").textContent = cuenta
    ? `Cuenta vinculada: ${cuenta.nickname}`
    : "Abre Dashboard en este navegador para vincular tu cuenta.";
  $("reglasActivas").textContent = activas.length;
  $("bloqueosHoy").textContent = ModerAIStorage.getBloqueosHoy();
  $("bloqueosTitulo").textContent = cuenta ? "coincidencias hoy" : "bloqueos hoy";
  $("nivelAyuda").textContent = cuenta
    ? "Cambia el nivel de certeza en Cuenta, dentro del Dashboard."
    : "Se difuminan los posts con esa certeza del modelo o más.";
  $("nivel").disabled = Boolean(cuenta);
  if (cuenta || document.activeElement !== $("nivel")) {
    const n = cuenta?.nivel_certeza ?? ModerAIStorage.getUsuarioConfig().nivel_sensibilidad;
    $("nivel").value = n; $("nivelVal").textContent = `${n}%`;
  }
  const ultimas = activas.slice(-4).reverse();
  $("listaReglasRapida").innerHTML = ultimas.length
    ? ultimas.map((r) => `<li>${esc(r.prompt)}</li>`).join("")
    : '<li class="vacio">Aún no has creado reglas.</li>';
}

// En la extensión real, el content script guarda el historial en chrome.storage.local
function traerHistorial() {
  if (typeof chrome === "undefined" || !chrome.storage?.local) return;
  chrome.storage.local.get(["historial_moderacion"], (r) => {
    if (r.historial_moderacion) localStorage.setItem("historial_moderacion", JSON.stringify(r.historial_moderacion));
    pintar();
  });
}

document.addEventListener("DOMContentLoaded", () => {
  pintar();
  traerHistorial();
  ModerAIStorage.sincronizarReglas().then(pintar).catch(() => {});
  if (typeof chrome !== "undefined" && chrome.storage?.onChanged) {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== "local") return;
      if (changes.moderai_cuenta_config) {
        ModerAIStorage.setCuentaExtension(changes.moderai_cuenta_config.newValue);
        pintar();
      } else if (changes.historial_moderacion) {
        traerHistorial();
      }
    });
  }
  window.addEventListener("storage", pintar);

  $("nivel").addEventListener("input", () => {
    const cfg = ModerAIStorage.getUsuarioConfig();
    cfg.nivel_sensibilidad = +$("nivel").value;
    ModerAIStorage.setUsuarioConfig(cfg);
    $("nivelVal").textContent = `${cfg.nivel_sensibilidad}%`;
  });

  // Task Flow 1, paso 2: (U) Clic "Gestionar Reglas" -> (S) Abre Options
  $("btnGestionarReglas").addEventListener("click", async () => {
    if (location.protocol === "chrome-extension:") {
      const url = await chrome.runtime.sendMessage({ type: "dashboard_url" });
      if (url) {
        const dashboard = new URL(url);
        dashboard.searchParams.set("seccion", "reglas");
        await chrome.tabs.create({ url: dashboard.href });
        return;
      }
    }
    if (typeof chrome !== "undefined" && chrome.runtime?.openOptionsPage) chrome.runtime.openOptionsPage();
    else window.location.href = "../options/options.html";
  });
});
