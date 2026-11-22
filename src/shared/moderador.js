/** Aplica el umbral del perfil activo. Las instalaciones locales antiguas conservan sus ajustes por regla. */
const ModerAIDecision = (() => {
  const AJUSTE = { Baja: 15, Normal: 0, Alta: -15 }; // Baja = más difícil difuminar; Alta = más fácil
  const ETIQUETA = { SPOILER: "Spoiler", SPAM: "Spam", HATE_SPEECH: "Odio", CUSTOM_PROMPT: "Personalizada" };
  const umbral = (nivel, sens) => Math.min(99, Math.max(5, nivel + (AJUSTE[sens] ?? 0)));
  function decidir(scores, reglas, nivel, sensibilidadActiva) { // scores: { id_regla: certeza }
    let mejor = null;
    for (const r of reglas) {
      if (sensibilidadActiva && r.sensibilidad !== sensibilidadActiva) continue;
      const c = scores[r.id_regla];
      if (c === undefined) continue;
      const u = sensibilidadActiva ? nivel : umbral(nivel, r.sensibilidad);
      const margen = c - u;
      const difuminar = margen >= 0;
      if (!mejor || (difuminar && !mejor.difuminar)
          || (difuminar === mejor.difuminar && c > mejor.certeza)) {
        mejor = { regla: r, certeza: c, umbral: u, margen, difuminar };
      }
    }
    return mejor;
  }
  return { umbral, decidir, ETIQUETA };
})();
if (typeof module !== "undefined") module.exports = ModerAIDecision;
