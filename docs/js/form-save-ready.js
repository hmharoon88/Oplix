/**
 * Highlights Save buttons when a form is valid and ready to persist.
 */
(function () {
    function snapshotForm(form) {
        if (!form) return "";
        const parts = [];
        form.querySelectorAll("input, select, textarea").forEach((el) => {
            if (!el.name || el.disabled) return;
            if (el.type === "checkbox") {
                parts.push(`${el.name}=${el.checked ? "1" : "0"}`);
            } else if (el.type === "radio") {
                if (el.checked) parts.push(`${el.name}=${el.value}`);
            } else {
                parts.push(`${el.name}=${el.value}`);
            }
        });
        return parts.join("|");
    }

    function formValid(form) {
        if (!form || typeof form.checkValidity !== "function") return true;
        return form.checkValidity();
    }

    let watchSeq = 0;

    function watch(container, options = {}) {
        if (!container) return { detach() {} };

        const token = String(++watchSeq);
        container.dataset.saveReadyWatch = token;

        const saveBtn =
            (typeof options.saveButton === "string"
                ? container.querySelector(options.saveButton)
                : options.saveButton) ||
            container.querySelector(
                options.saveSelector || '[data-save-btn], button[type="submit"].btn, .books-save'
            );

        if (!saveBtn) return { detach() {} };

        saveBtn.classList.add("save-watch");

        const form = options.form || container.querySelector("form") || container;
        const mode =
            options.mode ||
            (form?.dataset?.dirId || form?.dataset?.payId || form?.dataset?.compId ? "edit" : "new");
        let baseline = options.baseline != null ? options.baseline : snapshotForm(form);

        function computeReady() {
            if (typeof options.isReady === "function") {
                return options.isReady({
                    form,
                    saveBtn,
                    baseline,
                    snapshot: snapshotForm(form),
                    mode,
                });
            }
            if (!formValid(form)) return false;
            const snap = snapshotForm(form);
            if (mode === "new") return true;
            return snap !== baseline;
        }

        function update() {
            if (container.dataset.saveReadyWatch !== token) return;
            saveBtn.classList.toggle("is-save-ready", computeReady());
        }

        const onChange = () => update();
        container.addEventListener("input", onChange);
        container.addEventListener("change", onChange);
        update();

        return {
            detach() {
                if (container.dataset.saveReadyWatch !== token) return;
                container.removeEventListener("input", onChange);
                container.removeEventListener("change", onChange);
                saveBtn.classList.remove("save-watch", "is-save-ready");
                delete container.dataset.saveReadyWatch;
            },
            resetBaseline() {
                baseline = snapshotForm(form);
                update();
            },
            update,
        };
    }

    window.OplixFormSaveReady = { watch, snapshotForm };
})();
