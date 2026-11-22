const periodoActividad = document.querySelector("[data-periodo-actividad]");
periodoActividad?.addEventListener("change", () => periodoActividad.form.requestSubmit());

const graficaActividad = document.querySelector("[data-grafica-actividad]");
if (graficaActividad) {
    const detalle = graficaActividad.querySelector("output");
    const mostrarDetalle = event => {
        const punto = event.target.closest(".grafica-punto");
        if (punto) detalle.textContent = punto.getAttribute("aria-label");
    };
    graficaActividad.addEventListener("pointerover", mostrarDetalle);
    graficaActividad.addEventListener("focusin", mostrarDetalle);
    graficaActividad.addEventListener("click", mostrarDetalle);
}

document.querySelectorAll("[data-confirmacion]").forEach(button =>
    button.addEventListener("click", event => {
        if (!window.confirm(button.dataset.confirmacion)) event.preventDefault();
    }));

const titular = document.querySelector("[data-nip-cuenta]")?.dataset.nipCuenta;
if (titular && window.crypto?.subtle) {
    const llave = "moderai_dashboard_nip_" + titular;
    const estado = document.getElementById("estadoNip");
    const cargar = () => JSON.parse(localStorage.getItem(llave) || "null");
    const huella = async pin => Array.from(new Uint8Array(await crypto.subtle.digest(
        "SHA-256", new TextEncoder().encode("moderai:" + pin)))).join(",");
    const verificar = async config => {
        if (!config) return true;
        if (Math.max(0, config.bloqueo - Date.now())) {
            window.alert("Edición bloqueada durante cinco minutos por intentos fallidos.");
            return false;
        }
        const pin = window.prompt("Escribe tu NIP de 4 dígitos");
        if (pin === null) return false;
        const valido = config.huella === await huella(pin);
        const intentos = valido ? 0 : config.intentos + 1;
        localStorage.setItem(llave, JSON.stringify({
            huella: config.huella, intentos: intentos >= 3 ? 0 : intentos,
            bloqueo: intentos >= 3 ? Date.now() + 300000 : 0
        }));
        if (!valido) window.alert("NIP incorrecto.");
        return valido;
    };
    if (estado) estado.textContent = cargar() ? "NIP activo en este navegador." : "NIP desactivado.";
    document.getElementById("formNip")?.addEventListener("submit", async event => {
        event.preventDefault();
        if (!await verificar(cargar())) return;
        const input = document.getElementById("nuevoNip");
        localStorage.setItem(llave, JSON.stringify({ huella: await huella(input.value), intentos: 0, bloqueo: 0 }));
        input.value = "";
        estado.textContent = "NIP guardado.";
    });
    document.getElementById("quitarNip")?.addEventListener("click", async () => {
        if (!await verificar(cargar())) return;
        localStorage.removeItem(llave);
        estado.textContent = "NIP desactivado.";
    });
    document.querySelectorAll("[data-protegido]").forEach(form => {
        form.addEventListener("submit", async event => {
            const config = cargar();
            if (!config || form.dataset.autorizado) return;
            event.preventDefault();
            if (await verificar(config)) {
                form.dataset.autorizado = "1";
                form.requestSubmit(event.submitter || undefined);
                delete form.dataset.autorizado;
            }
        });
    });
}
