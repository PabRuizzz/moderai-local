if (location.origin === "http://127.0.0.1:5180" && /^\/Dashboard\/?$/i.test(location.pathname)) {
  (async () => {
    try {
      const respuesta = await fetch("/api/cuenta/vincular-extension", {
        method: "POST", credentials: "same-origin", cache: "no-store",
      });
      if (respuesta.status === 401) {
        await chrome.runtime.sendMessage({ type: "vincular_cuenta", ticket: null });
      } else if (respuesta.ok) {
        const { ticket } = await respuesta.json();
        await chrome.runtime.sendMessage({ type: "vincular_cuenta", ticket });
      }
    } catch (error) {
      console.warn("[ModerAI] No se pudo vincular el Dashboard:", error.message);
    }
  })();
}
