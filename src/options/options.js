/**
 * options.js — Task Flow 1 sobre la interfaz Bootstrap basada en el wireframe:
 * Escribe prompt -> Guardar -> ¿NIP activado? -> Guarda en regla_filtro
 * -> Guarda la regla y actualiza el listado.
 */
let pendingRegla = null;
let bsModalNip = null;
let bsToast = null;
let guardandoRegla = false;

function reglasOpciones() {
  const datos = window.ModerAICuenta?.datos;
  if (!datos) return ModerAIStorage.getReglas().slice().reverse();
  return datos.reglas.map((regla) => ({
    ...regla, prompt: regla.texto_regla,
  }));
}

document.addEventListener("moderai:cuenta", () => {
  renderReglas();
  renderJohnsonBox();
  document.getElementById("btnReset").hidden = Boolean(window.ModerAICuenta?.datos)
    || location.hash === "#mi-cuenta";
});

document.addEventListener("DOMContentLoaded", () => {
  bsModalNip = new bootstrap.Modal(document.getElementById("modalNip"));
  bsToast = new bootstrap.Toast(document.getElementById("toast"), { delay: 4000 });

  wireForm();
  wireModalNip();
  wireTabs();
  const filtroCategoria = document.getElementById("filtroCategoria");
  const categorias = Array.from(document.getElementById("categoria").options);
  filtroCategoria.append(...categorias.map((categoria) => new Option(categoria.text, categoria.value)));
  filtroCategoria.addEventListener("change", renderReglas);
  if (!["http:", "https:"].includes(location.protocol)) {
    renderReglas();
    renderJohnsonBox();
  }
  wireSeguridad();

  if (location.protocol === "chrome-extension:") {
    document.getElementById("btnReset").textContent = "Limpiar datos locales";
    wireExtensionAccount();
  }

  document.getElementById("btnReset").addEventListener("click", () => {
    if (location.protocol === "chrome-extension:" && !confirm("Se limpiarán los datos locales. Las reglas de MySQL se recuperarán al recargar; no se borrarán del servidor.")) return;
    ModerAIStorage.resetAll();
    location.reload();
  });
});

function wireExtensionAccount() {
  const status = document.getElementById("estadoSesionExtension");
  document.getElementById("sesionExtension").hidden = false;

  function show(config) {
    const linked = Boolean(config?.vinculada);
    ModerAIStorage.setCuentaExtension(linked ? config : null);
    status.textContent = linked
      ? `Sesión activa: ${config.nickname}`
      : "Inicia sesión en la cuenta web desde este mismo perfil de Chrome.";
    status.classList.remove("text-danger");
    document.getElementById("btnReset").hidden = linked || location.hash === "#mi-cuenta";
    renderReglas();
    renderJohnsonBox();
  }

  async function refresh() {
    try {
      const response = await chrome.runtime.sendMessage({ type: "cuenta_estado" });
      if (!response?.ok) throw new Error(response?.error || "No se pudo conectar con ModerAI.");
      show(response.data);
    } catch (error) {
      status.textContent = error.message;
      status.classList.add("text-danger");
    }
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !changes.moderai_cuenta_config) return;
    const config = changes.moderai_cuenta_config.newValue;
    show(config ? { ...config, vinculada: true } : { vinculada: false });
  });

  chrome.runtime.sendMessage({ type: "dashboard_url" }).then((url) => {
    if (!url) return;
    const link = document.getElementById("linkCuenta");
    link.href = url;
    link.hidden = false;
  }).catch(() => {});

  refresh().then(async () => {
    if (!ModerAIStorage.getCuentaExtension()) {
      await ModerAIStorage.sincronizarReglas().catch(() => {});
      renderReglas();
      renderJohnsonBox();
    }
  });
  window.addEventListener("focus", refresh);
  document.addEventListener("moderai:pestana", ({ detail }) => {
    if (["cuenta", "prompts"].includes(detail)) refresh();
  });
}

/* -------- Navegación por tabs (sitemap: Dashboard de Opciones) -------- */
function wireTabs() {
  const tabs = document.querySelectorAll("#pestanasConfiguracion .tab-card");
  let previousTab = "prompts";

  function showSelectedTab() {
    const accountSelected = location.hash === "#mi-cuenta";
    const selected = accountSelected ? "cuenta" : previousTab;
    tabs.forEach((button) => {
      const { tab } = button.dataset;
      const active = tab === selected;
      button.classList.toggle("active", active);
      button.setAttribute("aria-pressed", String(active));
      button.setAttribute("aria-controls", `panel-${tab}`);
      document.getElementById(`panel-${tab}`).classList.toggle("d-none", !active);
    });
    if (!accountSelected) document.getElementById("contrasena").value = "";
    document.getElementById("btnReset").hidden = accountSelected
      || Boolean(window.ModerAICuenta?.datos || ModerAIStorage.getCuentaExtension());
    document.dispatchEvent(new CustomEvent("moderai:pestana", { detail: selected }));
  }

  tabs.forEach((button) => {
    button.addEventListener("click", () => {
      if (button.dataset.tab === "cuenta") {
        location.hash = "#mi-cuenta";
      } else {
        previousTab = button.dataset.tab;
        if (location.hash === "#mi-cuenta") location.hash = "";
        else showSelectedTab();
      }
    });
  });
  window.addEventListener("hashchange", showSelectedTab);
  showSelectedTab();
}

/* -------- Johnson Box: resumen escaneable -------- */
function renderJohnsonBox() {
  const datos = window.ModerAICuenta?.datos;
  const reglas = reglasOpciones();
  const activas = reglas.filter((r) => r.activa);
  const cuentaExtension = ModerAIStorage.getCuentaExtension();
  document.getElementById("statReglas").textContent = activas.length;
  document.getElementById("statBloqueosTitulo").textContent = datos || cuentaExtension ? "Coincidencias hoy (UTC)" : "Bloqueos hoy";
  document.getElementById("statBloqueos").textContent = datos
    ? BigInt(datos.coincidencias.hoy).toLocaleString("es-MX")
    : ModerAIStorage.getBloqueosHoy();
}

/* -------- Listado de reglas (tabla desktop/tablet + tarjetas apiladas en móvil) -------- */
function renderReglas() {
  const todas = reglasOpciones();
  const categoria = document.getElementById("filtroCategoria").value;
  const reglas = categoria ? todas.filter((regla) => regla.categoria === categoria) : todas;
  const nombresCategorias = new Map(Array.from(
    document.getElementById("categoria").options, (opcion) => [opcion.value, opcion.text],
  ));
  const cuentaWeb = Boolean(window.ModerAICuenta?.datos);
  const puedeCambiarEstado = cuentaWeb || Boolean(ModerAIStorage.getCuentaExtension());
  const tbody = document.getElementById("tablaReglasBody");
  const mobile = document.getElementById("listaReglasMobile");
  tbody.innerHTML = "";
  mobile.innerHTML = "";
  document.getElementById("accionesReglaTitulo").hidden = !puedeCambiarEstado;
  const vacio = document.getElementById("reglasVacio");
  vacio.classList.toggle("d-none", reglas.length > 0);
  vacio.textContent = todas.length && categoria
    ? "No hay reglas en esta categoría."
    : "Aún no hay reglas registradas.";

  reglas.forEach((r) => {
    const nombreCategoria = escapeHtml(nombresCategorias.get(r.categoria) ?? r.categoria);
    const estado = r.activa ? '<span class="badge text-bg-light border">Activa</span>' : '<span class="badge text-bg-light border">Inactiva</span>';
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${escapeHtml(r.prompt)}</td><td>${nombreCategoria}</td><td>${escapeHtml(r.sensibilidad)}</td><td>${estado}</td>`;
    tbody.appendChild(tr);

    const card = document.createElement("div");
    card.className = "regla-mobile-card";
    card.innerHTML = `<div>${escapeHtml(r.prompt)}</div><div class="meta">${nombreCategoria} · Sensibilidad ${escapeHtml(r.sensibilidad)} · ${r.activa ? "Activa" : "Inactiva"}</div>`;
    if (puedeCambiarEstado) {
      tr.insertCell().append(reglaAcciones(r, cuentaWeb));
      card.append(reglaAcciones(r, cuentaWeb));
    }
    mobile.appendChild(card);
  });
}

function reglaAcciones(regla, cuentaWeb) {
  const actions = document.createElement("div");
  actions.className = "d-flex flex-wrap gap-2 mt-2";
  const toggle = document.createElement("button");
  toggle.type = "button";
  toggle.className = "btn btn-sm btn-outline-dark";
  toggle.textContent = regla.activa ? "Desactivar" : "Activar";
  toggle.addEventListener("click", async () => {
    const activa = !regla.activa;
    const message = activa ? "Regla activada." : "Regla desactivada.";
    toggle.disabled = true;
    try {
      if (cuentaWeb) {
        await window.ModerAICuenta.update(`/reglas/${regla.id_regla}`, "PATCH", { activa }, message);
      } else {
        await ModerAIStorage.cambiarEstadoRegla(regla.id_regla, activa);
        renderReglas();
        renderJohnsonBox();
        showToast(message);
      }
    } catch (error) {
      showToast(error.message, true);
    } finally {
      toggle.disabled = false;
    }
  });
  actions.append(toggle);
  if (!cuentaWeb) return actions;
  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "btn btn-sm btn-outline-danger";
  remove.textContent = "Borrar";
  remove.addEventListener("click", () => {
    if (window.confirm("¿Borrar esta regla? Sus reportes se conservarán.")) {
      window.ModerAICuenta.update(`/reglas/${regla.id_regla}`, "DELETE", undefined, "Regla borrada.");
    }
  });
  actions.append(remove);
  return actions;
}

/* -------- NIP en la pestaña Cuenta -------- */
function wireSeguridad() {
  const cfg = ModerAIStorage.getUsuarioConfig();
  const toggle = document.getElementById("nipActivoToggle");
  const setBlock = document.getElementById("setNipBlock");
  toggle.checked = !!cfg.nip_activo;
  setBlock.classList.toggle("d-none", !(cfg.nip_activo && !cfg.pin_hash));

  toggle.addEventListener("change", () => {
    const c = ModerAIStorage.getUsuarioConfig();
    c.nip_activo = toggle.checked ? 1 : 0;
    ModerAIStorage.setUsuarioConfig(c);
    setBlock.classList.toggle("d-none", !(toggle.checked && !c.pin_hash));
  });

  document.getElementById("btnGuardarNip").addEventListener("click", async () => {
    const nip = document.getElementById("nuevoNip").value.trim();
    if (!/^\d{4}$/.test(nip)) return showToast("El NIP debe tener 4 dígitos.", true);
    const c = ModerAIStorage.getUsuarioConfig();
    c.pin_hash = await ModerAIStorage.hashPin(nip);
    c.nip_activo = 1;
    c.intentos_fallidos = 0;
    c.bloqueado_hasta = null;
    ModerAIStorage.setUsuarioConfig(c);
    document.getElementById("setNipBlock").classList.add("d-none");
    showToast("NIP configurado. Se solicitará al guardar reglas.");
  });
}

/* -------- Formulario "Crear nueva regla personalizada": paso central del Task Flow 1 -------- */
function wireForm() {
  const prompt = document.getElementById("promptTexto");
  const formError = document.getElementById("formError");

  document.getElementById("formRegla").addEventListener("submit", (e) => {
    e.preventDefault();
    formError.classList.add("d-none");
    const texto = prompt.value.trim();
    if (!texto) {
      mostrarErrorRegla("Escribe un prompt para guardar la regla.");
      prompt.focus();
      return;
    }

    const cfg = ModerAIStorage.getUsuarioConfig();
    if (cfg.bloqueado_hasta && Date.now() < cfg.bloqueado_hasta) {
      const mins = Math.ceil((cfg.bloqueado_hasta - Date.now()) / 60000);
      mostrarErrorRegla(`Edición bloqueada por NIP fallido. Intenta en ${mins} min.`);
      return;
    }

    const regla = {
      prompt: texto,
      categoria: document.getElementById("categoria").value,
      sensibilidad: document.getElementById("sensibilidad").value,
    };

    if (cfg.nip_activo && cfg.pin_hash) {
      pendingRegla = regla;
      openModalNip();
    } else {
      commitRegla(regla);
    }
  });
}

function mostrarErrorRegla(message) {
  const error = document.getElementById("formError");
  error.textContent = message;
  error.classList.remove("d-none");
}

/* -------- Modal NIP (rama "SÍ") -------- */
function wireModalNip() {
  document.getElementById("btnConfirmarNip").addEventListener("click", async () => {
    const nipError = document.getElementById("nipError");
    const nip = document.getElementById("inputNip").value.trim();
    const cfg = ModerAIStorage.getUsuarioConfig();
    const hash = await ModerAIStorage.hashPin(nip);

    if (hash === cfg.pin_hash) {
      cfg.intentos_fallidos = 0;
      cfg.bloqueado_hasta = null;
      ModerAIStorage.setUsuarioConfig(cfg);
      bsModalNip.hide();
      commitRegla(pendingRegla);
      pendingRegla = null;
    } else {
      cfg.intentos_fallidos = (cfg.intentos_fallidos || 0) + 1;
      if (cfg.intentos_fallidos >= 3) {
        cfg.bloqueado_hasta = Date.now() + 5 * 60 * 1000;
        cfg.intentos_fallidos = 0;
        ModerAIStorage.setUsuarioConfig(cfg);
        bsModalNip.hide();
        showToast("NIP incorrecto 3 veces. Edición bloqueada 5 minutos.", true);
        pendingRegla = null;
        return;
      }
      ModerAIStorage.setUsuarioConfig(cfg);
      nipError.textContent = `NIP incorrecto (${cfg.intentos_fallidos}/3).`;
      nipError.classList.remove("d-none");
    }
  });
}
function openModalNip() {
  document.getElementById("inputNip").value = "";
  document.getElementById("nipError").classList.add("d-none");
  bsModalNip.show();
  setTimeout(() => document.getElementById("inputNip").focus(), 300);
}

/* -------- Guarda en la "BD", sincroniza con la API, notifica y refresca todo -------- */
async function commitRegla(regla) {
  if (guardandoRegla) return;
  guardandoRegla = true;
  const boton = document.getElementById("btnGuardar");
  const formulario = document.getElementById("formRegla");
  boton.disabled = true;
  const notify = (message, error) => {
    if (error) {
      mostrarErrorRegla(message);
      return;
    }
    const filtro = document.getElementById("filtroCategoria");
    if (filtro.value && filtro.value !== regla.categoria) filtro.value = regla.categoria;
    renderReglas();
    renderJohnsonBox();
    showToast(message);
  };
  try {
    const cuenta = window.ModerAICuenta;
    if (cuenta) {
      await cuenta.listo;
      await cuenta.update("/reglas", "POST", {
        texto_regla: regla.prompt,
        categoria: regla.categoria,
        sensibilidad: regla.sensibilidad,
      }, "Regla guardada en tu cuenta.", { form: formulario, notify });
    } else if (location.protocol === "chrome-extension:") {
      await ModerAIStorage.guardarRegla(regla);
      formulario.reset();
      notify("Regla guardada en tu cuenta.");
    } else {
      mostrarErrorRegla("Abre el dashboard de ModerAI en 127.0.0.1:8001 para guardar la regla en tu cuenta.");
    }
  } catch (error) {
    mostrarErrorRegla(error.message);
  } finally {
    guardandoRegla = false;
    boton.disabled = false;
  }
}

function showToast(msg, isError = false) {
  const toastEl = document.getElementById("toast");
  document.getElementById("toastBody").textContent = msg;
  toastEl.classList.toggle("bg-danger", isError);
  toastEl.classList.toggle("bg-dark", !isError);
  bsToast.show();
}
function escapeHtml(str) {
  return String(str ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
