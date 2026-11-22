/**
 * Content script para X (x.com): detecta los posts del timeline, los difumina al instante, pide el dictamen
 * a la API (vía service worker) y deja el post difuminado, visible o con opción de reportar.
 * Los selectores de X cambian sin aviso: si dejan de funcionar, revísalos con las herramientas de desarrollo.
 */
(() => {
  // MODO PRUEBA: difumina sin reglas ni API, para comprobar que el difuminado funciona en X.
  // PALABRA_PRUEBA vacía = difumina todos los posts con texto; con una palabra = solo los que la contienen.
  // Cuando quieras conectar el modelo: MODO_PRUEBA = false.
  const MODO_PRUEBA = false;
  const PALABRA_PRUEBA = "";

  const SEL_POST = 'article[data-testid="tweet"]';
  const SEL_TEXTO = '[data-testid="tweetText"]';
  const ETQ = ModerAIDecision.ETIQUETA;
  const CSS = `
    :host{font-family:system-ui,-apple-system,"Segoe UI",sans-serif}
    .card{color:#1a1a1a;background:#fff;border:1.5px solid #1a1a1a;border-radius:8px;padding:10px 14px;max-width:270px;width:calc(100% - 16px);text-align:center;box-shadow:3px 3px 0 #1a1a1a}
    h3{font-size:13.5px;margin:4px 0 2px} p{font-size:11.5px;color:#666;margin:0 0 8px}
    .badge{display:inline-block;font-size:12px;font-weight:600;background:#1a1a1a;color:#fff;padding:2px 9px;border-radius:999px}
    button{font:inherit;font-size:12.5px;padding:6px 12px;border-radius:6px;cursor:pointer;border:1.5px solid #1a1a1a;background:#fff;color:#1a1a1a}
    button.p{background:#1a1a1a;color:#fff;width:100%}
    .reporte{position:relative;display:flex;justify-content:flex-end;padding:2px 8px 4px;font-size:12px}
    .accion{display:inline-flex;align-items:center;justify-content:center;gap:5px;min-height:32px;padding:3px 9px;border:1px solid rgba(29,155,240,.28);border-radius:999px;background:rgba(29,155,240,.08);color:inherit}
    .accion:hover,.accion:focus-visible{background:rgba(29,155,240,.18)}
    .accion:focus-visible{outline:2px solid currentColor;outline-offset:2px}
    .accion:disabled{cursor:wait;opacity:.55}
    .bandera{font-size:19px;line-height:1}
    .fallo{position:absolute;top:100%;right:0;z-index:10;width:max-content;max-width:230px;padding:5px 8px;border-radius:6px;background:#842222;color:#fff;text-wrap:wrap}
    .solo-lectores{position:absolute;width:1px;height:1px;padding:0;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
    @media (max-width:340px){.card{padding:8px 10px}p{display:none}}`;

  const posts = new Map();                  // article -> { id, texto, scores, revelado, reportado, host }
  let reglas = [], nivel = 70, seq = 0, cola = new Set(), timer = null;
  let cuenta = null, sensibilidadActiva = null, versionConfig = 0;

  const hashNum = (t) => { let h = 5381; for (const c of t) h = ((h << 5) + h + c.charCodeAt(0)) >>> 0; return h; };
  const activas = () => reglas.filter((r) => r.activa && (!sensibilidadActiva || r.sensibilidad === sensibilidadActiva));

  async function cargarConfig() {
    const c = await chrome.storage.local.get(["moderai_cuenta_config", "regla_filtro", "usuario_config"]);
    cuenta = c.moderai_cuenta_config ?? null;
    reglas = cuenta?.reglas ?? c.regla_filtro ?? [];
    sensibilidadActiva = cuenta?.sensibilidad_activa ?? null;
    nivel = cuenta?.nivel_certeza ?? c.usuario_config?.nivel_sensibilidad ?? 70;
  }

  /* ---- detección ---- */
  function escanear() {
    for (const a of posts.keys()) {
      if (!a.isConnected) { posts.delete(a); cola.delete(a); }
    }
    if (!MODO_PRUEBA && !activas().length) return;
    document.querySelectorAll(SEL_POST).forEach((a) => {
      const texto = a.querySelector(SEL_TEXTO)?.innerText.trim();
      if (!texto) return;                                   // posts sin texto: por ahora no se evalúan
      const p = posts.get(a);
      if (p && p.texto === texto) {
        if (p.host && !p.host.isConnected && (p.estado === "visible" || p.estado === "barra")) a.appendChild(p.host);
        return;
      }
      if (p) limpiar(a, p);                                 // X reutiliza nodos: el contenido cambió
      posts.set(a, { id: ++seq, texto, scores: null, revelado: false, reportado: false, host: null, reglaAplicada: null });
      if (MODO_PRUEBA) {
        const np = posts.get(a);
        np.scores = {};
        np.d = { difuminar: true, certeza: 91, regla: { id_regla: 0, prompt: "Modo prueba (sin API)", categoria: "SPOILER" } };
        if (!PALABRA_PRUEBA || texto.toLowerCase().includes(PALABRA_PRUEBA.toLowerCase())) pintar(a, "cartel");
        return;
      }
      pintar(a, "analizando");                              // se difumina ANTES de saber el resultado
      cola.add(a);
    });
    if (cola.size && !timer) timer = setTimeout(enviar, 200);
  }

  async function enviar() {
    timer = null;
    const arts = [...cola].slice(0, 100);
    arts.forEach((article) => cola.delete(article));
    if (cola.size) timer = setTimeout(enviar, 200);
    const config = versionConfig;
    if (!arts.length) return;
    let espera;
    const lote = new Map(arts.map(a => [a, posts.get(a)]).filter(([a, p]) => a.isConnected && p));
    const liberar = () => {
      for (const [a, p] of lote) {
        if (posts.get(a) !== p) continue;
        p.scores = null;
        mostrarDisponible(a, p);
      }
    };
    try {
    const rs = activas();
    if (!rs.length) { liberar(); return; }
    const ids = new Set(rs.map((r) => r.id_regla));
    const corr = cuenta ? [] : ((await chrome.storage.local.get("correccion_usuario")).correccion_usuario || []).filter((c) => ids.has(c.id_regla));
    const payload = {
      posts: Array.from(lote.values(), ({ id, texto }) => ({ id, texto })),
      reglas: rs.map(({ id_regla, prompt, categoria }) => ({ id_regla, prompt, categoria })),
      correcciones: corr.map(({ id_regla, texto, etiqueta }) => ({ id_regla, texto, etiqueta }))
    };
    if (config !== versionConfig || !payload.posts.length) return;
    let res;
    try {
      res = await Promise.race([
        chrome.runtime.sendMessage({ type: "evaluar", payload }),
        new Promise((_, reject) => {
          espera = setTimeout(() => reject(new Error("El modelo no respondió en 30 segundos")), 30000);
        })
      ]);
    } catch (error) {
      res = { ok: false, error: error.message };
    }
    if (config !== versionConfig) return;
    if (!res?.ok) { console.warn("[ModerAI] sin modelo:", res?.error); liberar(); return; }
    if (!Array.isArray(res.data?.resultados)) throw new Error("Respuesta de evaluación inválida");
    let candidatas = rs;
    if (cuenta && Array.isArray(res.data.reglas)) {
      candidatas = res.data.reglas;
      nivel = res.data.nivel_certeza;
      sensibilidadActiva = res.data.sensibilidad_activa ?? null;
    }
    const porId = {};
    res.data.resultados.forEach((r) => { (porId[r.id_post] ||= {})[r.id_regla] = r.certeza; });
    for (const [a, p] of lote) {
      if (posts.get(a) !== p) continue;
      p.scores = porId[p.id] || {};
      decidir(a, candidatas);
    }
    if (!cuenta) await guardarHistorial();
    } catch (error) {
      console.error("[ModerAI] error al evaluar publicaciones:", error);
      if (config === versionConfig) liberar();
    } finally {
      clearTimeout(espera);
    }
  }

  /* ---- decisión y pintado ---- */
  function decidir(a, candidatas = activas()) {
    const p = posts.get(a);
    if (!p?.scores) return;
    if (MODO_PRUEBA) return p.reportado ? limpiar(a, p) : pintar(a, p.revelado ? "barra" : "cartel");
    const d = ModerAIDecision.decidir(p.scores, candidatas, nivel, sensibilidadActiva);
    p.d = d;
    if (p.revelado || !d?.difuminar || p.reportado) return mostrarDisponible(a, p);
    pintar(a, "cartel");
  }

  function mostrarDisponible(a, p) {
    if (p.revelado && p.reglaAplicada && (cuenta || p.d?.difuminar) && !p.reportado) pintar(a, "barra");
    else if (cuenta && activas().length) pintar(a, "visible");
    else limpiar(a, p);
  }

  function limpiar(a, p) {
    const inner = a.firstElementChild;
    if (inner) { inner.style.filter = ""; inner.style.pointerEvents = ""; }
    p.host?.remove(); p.host = null;
  }

  function pintar(a, estado) {
    const p = posts.get(a), inner = a.firstElementChild, d = p.d;
    if (!inner) return;
    if (!p.host) {
      const host = document.createElement("div");
      host.addEventListener("click", (e) => e.stopPropagation());   // que X no abra el post al hacer clic en el cartel
      const root = host.attachShadow({ mode: "open" });
      const sheet = new CSSStyleSheet(); sheet.replaceSync(CSS);    // no depende del CSP de la página
      root.adoptedStyleSheets = [sheet];
      if (getComputedStyle(a).position === "static") a.style.position = "relative";
      a.appendChild(host);
      p.host = host;
    }
    p.estado = estado;
    const root = p.host.shadowRoot, barra = estado === "barra", visible = estado === "visible";
    inner.style.filter = barra || visible ? "" : "blur(10px)";
    inner.style.pointerEvents = barra || visible ? "" : "none";
    p.host.style.cssText = barra || visible ? "display:block"
      : "position:absolute;inset:0;z-index:9;display:grid;place-items:center";
    const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
    if (estado === "analizando") root.innerHTML = `<div class="card"><h3>Analizando con ModerAI…</h3></div>`;
    else if (barra || visible) {
      const accion = barra ? "Reportar censura equivocada" : "Reportar contenido sin censurar";
      const resultado = barra ? "ModerAI había ocultado esta publicación."
        : p.scores === null ? "Análisis no disponible" : "Analizado por ModerAI";
      root.innerHTML = `<div class="reporte">
        <button type="button" class="accion" id="rep" aria-label="${accion}" aria-describedby="estado" title="${accion} · ${resultado}">
          <span class="bandera" aria-hidden="true">⚐</span><span aria-hidden="true">Reportar</span>
        </button>
        <span id="estado" class="solo-lectores">${resultado}</span>
        <span id="fallo" class="fallo" role="status" hidden></span>
      </div>`;
    }
    else root.innerHTML = `<div class="card"><span class="badge">${Math.round(d.certeza)}% ${ETQ[d.regla.categoria] || "Regla"}</span><h3>Contenido difuminado</h3><p>Coincide con tu regla: "${esc(d.regla.prompt)}"</p><button class="p" id="show">Mostrar contenido</button></div>`;
    root.getElementById("show")?.addEventListener("click", (event) => {
      p.revelado = true;
      p.reglaAplicada = d.regla;
      decidir(a);
      if (event.detail === 0) p.host?.shadowRoot.getElementById("rep")?.focus({ preventScroll: true });
    });
    root.getElementById("rep")?.addEventListener("click", (event) => reportar(a, event.currentTarget, root.getElementById("fallo")));
  }

  /* ---- aprendizaje: "Reportar error" = corrección con etiqueta 0 ---- */
  async function reportar(a, boton, fallo) {
    const p = posts.get(a);
    if (cuenta) {
      boton.disabled = true;
      fallo.hidden = true;
      try {
        const regla = p.revelado ? p.reglaAplicada : null;
        const resultado = await chrome.runtime.sendMessage({
          type: "abrir_reporte", texto: p.texto, idCuenta: String(cuenta.id_usuario),
          tipo: regla ? "censura_equivocada" : "faltaba_censura", idRegla: regla ? String(regla.id_regla) : null,
        });
        if (!resultado?.ok) throw new Error(resultado?.error || "No se pudo abrir el reporte.");
      } catch (error) {
        fallo.textContent = error.message;
        fallo.hidden = false;
      } finally {
        boton.disabled = false;
      }
      return;
    }
    p.reportado = true; decidir(a);
    if (MODO_PRUEBA) return;                                 // en modo prueba no se guarda ni se llama a la API
    const { correccion_usuario = [] } = await chrome.storage.local.get("correccion_usuario");
    const regla = p.reglaAplicada;
    const resto = correccion_usuario.filter((c) => !(c.id_regla === regla.id_regla && c.texto === p.texto));
    await chrome.storage.local.set({ correccion_usuario: resto.concat({ id_regla: regla.id_regla, id_post: hashNum(p.texto), texto: p.texto, etiqueta: 0, fecha: new Date().toISOString().slice(0, 10) }) });
    posts.forEach((_, art) => cola.add(art));                // la API vuelve a puntuar todo con la corrección
    if (!timer) timer = setTimeout(enviar, 50);
  }

  async function guardarHistorial() {
    const hoy = new Date().toISOString().slice(0, 10);
    const filas = [];
    posts.forEach((p) => {
      if (!p.d) return;
      const dif = p.d.difuminar && !p.reportado;
      filas.push({ id_historial: hashNum(p.texto), id_usuario: "usr_local_123", id_regla: p.d.regla.id_regla, id_post: hashNum(p.texto),
        hash_contenido: hashNum(p.texto).toString(16), porcentaje_certeza: p.d.certeza,
        accion_aplicada: p.reportado ? "REPORTE_FALSO_POSITIVO" : dif ? "DIFUMINADO" : "VISIBLE", error_reportado: p.reportado ? 1 : 0, fecha_evaluacion: hoy });
    });
    const claves = new Set(filas.map((f) => f.id_post));
    const { historial_moderacion = [] } = await chrome.storage.local.get("historial_moderacion");
    await chrome.storage.local.set({ historial_moderacion: historial_moderacion.filter((h) => !claves.has(h.id_post)).concat(filas) });
  }

  /* ---- arranque ---- */
  function reevaluar() {
    if (!activas().length) {
      posts.forEach((p, a) => {
        if (cuenta && p.revelado && p.reglaAplicada && a.isConnected) pintar(a, "barra");
        else { limpiar(a, p); posts.delete(a); }
      });
      cola.clear();
      return;
    }
    posts.forEach((_, a) => { if (a.isConnected) cola.add(a); });
    escanear();
    if (cola.size && !timer) timer = setTimeout(enviar, 50);
  }

  chrome.storage.onChanged.addListener(async (cambios, area) => {
    if (MODO_PRUEBA || area !== "local") return;
    if (cambios.moderai_cuenta_config) {
      const anterior = cuenta;
      await cargarConfig();
      if (anterior?.id_usuario !== cuenta?.id_usuario) {
        posts.forEach((p, a) => limpiar(a, p));
        posts.clear();
        cola.clear();
      } else if (anterior?.nivel_certeza === cuenta?.nivel_certeza
          && anterior?.sensibilidad_activa === cuenta?.sensibilidad_activa
          && JSON.stringify(anterior?.reglas) === JSON.stringify(cuenta?.reglas)) {
        return;
      }
      versionConfig++;
      reevaluar();
      return;
    }
    if (cuenta) return;
    if (cambios.regla_filtro) {
      reglas = cambios.regla_filtro.newValue || [];
      versionConfig++;
      reevaluar();
    }
    if (cambios.usuario_config) { nivel = cambios.usuario_config.newValue?.nivel_sensibilidad ?? 70; posts.forEach((_, a) => decidir(a)); }
  });

  async function iniciar() {
    try {
      const result = await chrome.runtime.sendMessage({ type: "reglas_listar" });
      if (!result?.ok) console.warn("[ModerAI] usando reglas locales: servidor no disponible");
    } catch (error) {
      console.warn("[ModerAI] usando reglas locales:", error.message);
    }
    await cargarConfig();
    escanear();
    setInterval(() => {
      if (!document.hidden) chrome.runtime.sendMessage({ type: "cuenta_estado" }).catch(() => {});
    }, 30000);
    let debounce;
    new MutationObserver(() => { clearTimeout(debounce); debounce = setTimeout(escanear, 250); })
      .observe(document.body, { childList: true, subtree: true });
  }
  iniciar();
})();
