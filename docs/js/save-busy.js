/**
 * Global busy indicator — spinner bar for saves, uploads, and panel loads.
 */
(function () {
    let inFlight = 0;
    let saveInFlight = 0;
    let message = "Saving — please wait";
    let barEl = null;

    function ensureBar() {
        if (barEl) return barEl;
        barEl = document.createElement("div");
        barEl.id = "oplix-save-busy";
        barEl.className = "oplix-save-busy";
        barEl.hidden = true;
        barEl.setAttribute("role", "status");
        barEl.setAttribute("aria-live", "polite");
        barEl.innerHTML =
            '<span class="oplix-save-busy-spinner" aria-hidden="true"></span><span class="oplix-save-busy-text"></span>';
        const anchor = document.getElementById("app-content") || document.body;
        anchor.insertBefore(barEl, anchor.firstChild);
        return barEl;
    }

    function syncBar() {
        const el = ensureBar();
        const textEl = el.querySelector(".oplix-save-busy-text");
        if (textEl) textEl.textContent = message;
        el.hidden = inFlight <= 0;
        document.body.classList.toggle("oplix-save-busy-active", saveInFlight > 0);
        document.body.classList.toggle("oplix-app-loading-active", inFlight > saveInFlight);
    }

    function begin(msg, kind) {
        inFlight += 1;
        if (kind === "load") {
            /* load-only: show bar without blocking sidebar navigation */
        } else {
            saveInFlight += 1;
        }
        if (msg) message = String(msg);
        syncBar();
    }

    function end(kind) {
        inFlight = Math.max(0, inFlight - 1);
        if (kind !== "load") {
            saveInFlight = Math.max(0, saveInFlight - 1);
        }
        syncBar();
    }

    function isActive() {
        return inFlight > 0;
    }

    async function run(fn, msg, kind) {
        begin(msg, kind);
        try {
            return await fn();
        } finally {
            end(kind);
        }
    }

    const api = {
        begin,
        end,
        run,
        isActive,
        runLoad(fn, msg) {
            return run(fn, msg || "Loading — please wait", "load");
        },
    };
    window.OplixSaveBusy = api;
    window.OplixAppBusy = api;
})();
