/**
 * Daily books field customization — embeddable in facility customize screen.
 */
(function () {
    const FC = () => window.OplixBooksFieldConfig;

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function renderBuiltinTable(group, config, gas) {
        const fields = FC().fieldsForGroup(group, gas);
        if (!fields.length) return "";
        return `
            <section class="bfc-group">
                <h4 class="bfc-group-title">${escapeHtml(FC().GROUP_LABELS[group])}</h4>
                <p class="books-hint bfc-group-hint">Uncheck <strong>Show</strong> to hide a built-in field from Daily books.</p>
                <div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table bfc-table">
                        <thead>
                            <tr>
                                <th>Show</th>
                                <th>Field</th>
                                <th>Category</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${fields
                                .map((f) => {
                                    const row = config.fields[f.id] || {};
                                    const enabled = row.enabled !== false;
                                    const category = row.category || f.defaultCategory;
                                    return `
                                <tr data-bfc-builtin="${escapeHtml(f.id)}">
                                    <td>
                                        <input type="checkbox" class="bfc-enable" data-bfc-field="${escapeHtml(f.id)}"${enabled ? " checked" : ""} aria-label="Show ${escapeHtml(f.label)}">
                                    </td>
                                    <td>${escapeHtml(f.label)}</td>
                                    <td>
                                        <select class="books-select bfc-category" data-bfc-field="${escapeHtml(f.id)}" aria-label="Category for ${escapeHtml(f.label)}">
                                            ${FC()
                                                .CATEGORIES.map(
                                                    (c) =>
                                                        `<option value="${c.id}"${c.id === category ? " selected" : ""}>${escapeHtml(c.label)}</option>`
                                                )
                                                .join("")}
                                        </select>
                                    </td>
                                </tr>`;
                                })
                                .join("")}
                        </tbody>
                    </table>
                </div>
            </section>`;
    }

    function renderCustomFieldRow(cf) {
        return `
            <tr class="bfc-custom-row" data-bfc-custom-id="${escapeHtml(cf.id)}">
                <td>
                    <input type="checkbox" class="bfc-custom-enable" data-bfc-custom-id="${escapeHtml(cf.id)}"${cf.enabled !== false ? " checked" : ""} aria-label="Show ${escapeHtml(cf.label)}">
                </td>
                <td>
                    <input type="text" class="books-input bfc-custom-label" value="${escapeHtml(cf.label)}" required aria-label="Custom field label">
                </td>
                <td>
                    <select class="books-select bfc-custom-group" aria-label="Where to show ${escapeHtml(cf.label)}">
                        <option value="daily"${cf.group === "daily" ? " selected" : ""}>Daily sheet</option>
                        <option value="month"${cf.group === "month" ? " selected" : ""}>Utilities & payroll</option>
                    </select>
                </td>
                <td>
                    <select class="books-select bfc-custom-category" aria-label="Category for ${escapeHtml(cf.label)}">
                        ${FC()
                            .CATEGORIES.map(
                                (c) =>
                                    `<option value="${c.id}"${c.id === cf.category ? " selected" : ""}>${escapeHtml(c.label)}</option>`
                            )
                            .join("")}
                    </select>
                </td>
                <td>
                    <button type="button" class="books-rm bfc-custom-rm" data-bfc-custom-id="${escapeHtml(cf.id)}" title="Remove custom field">×</button>
                </td>
            </tr>`;
    }

    function renderCustomFieldsSection(customFields) {
        const rows = (customFields || []).map(renderCustomFieldRow).join("");
        return `
            <section class="bfc-group bfc-group--custom">
                <h4 class="bfc-group-title">Custom fields</h4>
                <p class="books-hint bfc-group-hint">Add your own lines (e.g. ATM commission, car wash).</p>
                <div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table bfc-table bfc-table--custom">
                        <thead>
                            <tr>
                                <th>Show</th>
                                <th>Label</th>
                                <th>Where</th>
                                <th>Category</th>
                                <th></th>
                            </tr>
                        </thead>
                        <tbody class="bfc-custom-tbody">
                            ${rows || `<tr class="bfc-custom-empty"><td colspan="5"><span class="data-list-empty">No custom fields yet.</span></td></tr>`}
                        </tbody>
                    </table>
                </div>
                <div class="bfc-custom-add-row">
                    <label class="books-label">New field label
                        <input type="text" class="books-input bfc-new-label" placeholder="e.g. ATM commission">
                    </label>
                    <label class="books-label">Where
                        <select class="books-select bfc-new-group">
                            <option value="daily">Daily sheet</option>
                            <option value="month">Utilities & payroll</option>
                        </select>
                    </label>
                    <label class="books-label">Category
                        <select class="books-select bfc-new-category">
                            ${FC()
                                .CATEGORIES.map((c) => `<option value="${c.id}">${escapeHtml(c.label)}</option>`)
                                .join("")}
                        </select>
                    </label>
                    <button type="button" class="btn btn-nav-outline bfc-add-custom">+ Add field</button>
                </div>
            </section>`;
    }

    function renderBooksConfigFields(config, gas) {
        return `
            ${renderBuiltinTable("daily", config, gas)}
            ${renderBuiltinTable("month", config, gas)}
            ${renderBuiltinTable("tab", config, gas)}
            ${renderCustomFieldsSection(config.customFields)}`;
    }

    function readCustomFieldsFromDom(root) {
        const rows = root.querySelectorAll(".bfc-custom-row");
        const out = [];
        rows.forEach((tr) => {
            const id = tr.dataset.bfcCustomId;
            if (!id) return;
            out.push({
                id,
                label: String(tr.querySelector(".bfc-custom-label")?.value || "").trim(),
                group: tr.querySelector(".bfc-custom-group")?.value === "month" ? "month" : "daily",
                category: tr.querySelector(".bfc-custom-category")?.value || "none",
                enabled: tr.querySelector(".bfc-custom-enable")?.checked !== false,
            });
        });
        return FC().normalizeCustomFieldDefs(out);
    }

    function readBooksConfigFromDom(root, hasGas) {
        const base = FC().defaultBooksFieldConfig(hasGas);
        root.querySelectorAll(".bfc-enable").forEach((el) => {
            const id = el.dataset.bfcField;
            if (!id || !base.fields[id]) return;
            base.fields[id].enabled = el.checked;
        });
        root.querySelectorAll(".bfc-category").forEach((el) => {
            const id = el.dataset.bfcField;
            if (!id || !base.fields[id]) return;
            base.fields[id].category = el.value;
        });
        base.customFields = readCustomFieldsFromDom(root);
        return FC().normalizeBooksFieldConfig(base, hasGas);
    }

    function bindBooksConfigHandlers(root, options) {
        if (!root || root.dataset.bfcHandlersBound) return;
        root.dataset.bfcHandlersBound = "1";

        const hasGas = options?.hasGas ?? false;
        const status = options?.statusEl;
        const tbody = root.querySelector(".bfc-custom-tbody");

        function clearCustomEmptyRow() {
            tbody?.querySelector(".bfc-custom-empty")?.remove();
        }

        root.querySelector(".bfc-add-custom")?.addEventListener("click", () => {
            const label = String(root.querySelector(".bfc-new-label")?.value || "").trim();
            if (!label) {
                if (status) status.textContent = "Enter a label for the new field.";
                root.querySelector(".bfc-new-label")?.focus();
                return;
            }
            const group = root.querySelector(".bfc-new-group")?.value === "month" ? "month" : "daily";
            const category = root.querySelector(".bfc-new-category")?.value || "none";
            const cf = { id: FC().newCustomFieldId(), label, group, category, enabled: true };
            clearCustomEmptyRow();
            tbody?.insertAdjacentHTML("beforeend", renderCustomFieldRow(cf));
            const labelInput = root.querySelector(".bfc-new-label");
            if (labelInput) labelInput.value = "";
            if (status) status.textContent = `Added "${label}" — save to apply.`;
        });

        tbody?.addEventListener("click", (e) => {
            const btn = e.target.closest(".bfc-custom-rm");
            if (!btn) return;
            if (!confirm("Remove this custom field? (Past amounts are kept in records.)")) return;
            btn.closest(".bfc-custom-row")?.remove();
            if (tbody && !tbody.querySelector(".bfc-custom-row")) {
                tbody.innerHTML = `<tr class="bfc-custom-empty"><td colspan="5"><span class="data-list-empty">No custom fields yet.</span></td></tr>`;
            }
            if (status) status.textContent = "Field removed — save to apply.";
        });

        const resetBtn = options?.resetBtn || root.querySelector("#bfc-reset");
        resetBtn?.addEventListener("click", () => {
            if (!confirm("Reset Daily books to defaults? This removes custom fields and restores all built-in fields.")) return;
            const defaults = FC().defaultBooksFieldConfig(hasGas);
            root.querySelectorAll("tr[data-bfc-builtin]").forEach((tr) => {
                const id = tr.dataset.bfcBuiltin;
                const def = defaults.fields[id];
                if (!def) return;
                const cb = tr.querySelector(".bfc-enable");
                const sel = tr.querySelector(".bfc-category");
                if (cb) cb.checked = def.enabled !== false;
                if (sel) sel.value = def.category;
            });
            if (tbody) {
                tbody.innerHTML = `<tr class="bfc-custom-empty"><td colspan="5"><span class="data-list-empty">No custom fields yet.</span></td></tr>`;
            }
            if (status) status.textContent = "Books defaults restored — save to apply.";
        });

        if (!options?.skipSubmit) {
            root.querySelector("#bfc-form")?.addEventListener("submit", (e) => e.preventDefault());
        }
    }

    window.OplixFacilityBooksConfig = {
        renderBooksConfigFields,
        readBooksConfigFromDom,
        bindBooksConfigHandlers,
    };
})();
