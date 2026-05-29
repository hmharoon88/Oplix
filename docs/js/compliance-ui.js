/**
 * Facility Compliance section — audits, inspections, checklist items.
 */
(function () {
    const M = () => window.OplixComplianceModel;
    const Store = () => window.OplixComplianceStore;

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function statusClass(status) {
        if (status === "pass") return "comp-status--pass";
        if (status === "fail") return "comp-status--fail";
        if (status === "scheduled") return "comp-status--scheduled";
        if (status === "na") return "comp-status--na";
        return "comp-status--pending";
    }

    function renderListRow(item) {
        const overdue = M().isOverdue(item);
        const title = item.title || M().categoryLabel(item.category);
        const meta = [
            M().categoryLabel(item.category),
            item.dueDate ? `Due ${item.dueDate}` : "",
            item.inspector ? item.inspector : "",
        ]
            .filter(Boolean)
            .join(" · ");
        return `
            <li class="loc-row-card dir-row comp-row" data-comp-id="${escapeHtml(item.id)}">
                <div>
                    <strong>${escapeHtml(title)}</strong>
                    ${meta ? `<span class="data-list-meta">${escapeHtml(meta)}</span>` : ""}
                </div>
                <div class="dir-row-actions comp-row-actions">
                    <span class="comp-status-pill ${statusClass(item.status)}${overdue ? " comp-status--overdue" : ""}">${escapeHtml(M().statusLabel(item.status))}${overdue ? " · overdue" : ""}</span>
                    <button type="button" class="dir-btn-edit" data-comp-edit="${escapeHtml(item.id)}">Edit</button>
                </div>
            </li>`;
    }

    function renderForm(item, id) {
        const v = M().normalizeItem(item);
        const catOpts = M().CATEGORIES.map(
            (c) =>
                `<option value="${c.id}"${c.id === v.category ? " selected" : ""}>${escapeHtml(c.label)}</option>`
        ).join("");
        const statusOpts = M().STATUSES.map(
            (s) =>
                `<option value="${s.id}"${s.id === v.status ? " selected" : ""}>${escapeHtml(s.label)}</option>`
        ).join("");
        return `
            <form class="dir-form comp-form" data-comp-form data-comp-id="${escapeHtml(id)}">
                <div class="books-grid-2">
                    <label class="books-label">Category
                        <select class="books-select" name="category">${catOpts}</select>
                    </label>
                    <label class="books-label">Status
                        <select class="books-select" name="status">${statusOpts}</select>
                    </label>
                    <label class="books-label">Title
                        <input class="books-input" name="title" placeholder="e.g. Monthly tobacco audit" value="${escapeHtml(v.title)}">
                    </label>
                    <label class="books-label">Inspector / owner
                        <input class="books-input" name="inspector" value="${escapeHtml(v.inspector)}">
                    </label>
                    <label class="books-label">Due date
                        <input class="books-input" name="dueDate" type="date" value="${escapeHtml(v.dueDate)}">
                    </label>
                    <label class="books-label">Completed date
                        <input class="books-input" name="completedDate" type="date" value="${escapeHtml(v.completedDate)}">
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="3">${escapeHtml(v.notes)}</textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-comp-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn fac-btn-delete" data-comp-delete>Delete</button>` : ""}
                    <span class="dir-status" data-comp-form-status></span>
                </div>
            </form>`;
    }

    function readForm(form) {
        const fd = new FormData(form);
        return M().normalizeItem({
            active: true,
            category: fd.get("category"),
            status: fd.get("status"),
            title: fd.get("title"),
            inspector: fd.get("inspector"),
            dueDate: fd.get("dueDate"),
            completedDate: fd.get("completedDate"),
            notes: fd.get("notes"),
        });
    }

    function renderSection(ctx) {
        const items = M().sortItems((ctx.data.complianceItems || []).filter((i) => i.active !== false));
        const attention = M().needsAttentionCount(items);
        const hint =
            attention > 0
                ? `<p class="books-hint dir-hint comp-hint-warn">${attention} item${attention === 1 ? "" : "s"} need attention (failed or overdue).</p>`
                : `<p class="books-hint dir-hint">Track inspections, audits, and regulatory checklists for this facility.</p>`;

        return `
            <div class="comp-section" data-comp-section>
                <h2 class="loc-section-heading">Compliance</h2>
                ${hint}
                <div class="dir-toolbar">
                    <button type="button" class="btn" data-comp-add>Add item</button>
                    <span class="dir-status" data-comp-status></span>
                </div>
                <div class="dir-form-slot" data-comp-form-slot hidden></div>
                ${
                    items.length
                        ? `<ul class="loc-row-list dir-list">${items.map(renderListRow).join("")}</ul>`
                        : `<p class="data-list-empty">No compliance items yet. Add audits, inspections, or checklist entries.</p>`
                }
            </div>`;
    }

    function bind(container, ctx) {
        if (!container || container.dataset.compBound) return;
        container.dataset.compBound = "1";

        const slot = container.querySelector("[data-comp-form-slot]");
        const statusEl = container.querySelector("[data-comp-status]");

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function closeForm() {
            if (slot) {
                slot.hidden = true;
                slot.innerHTML = "";
            }
        }

        function openForm(item, id) {
            if (!slot) return;
            slot.hidden = false;
            slot.innerHTML = renderForm(item, id);
            const form = slot.querySelector("[data-comp-form]");
            form?.querySelector("[data-comp-cancel]")?.addEventListener("click", closeForm);
            form?.querySelector("[data-comp-delete]")?.addEventListener("click", async () => {
                if (!id || !confirm("Delete this compliance item?")) return;
                const st = form.querySelector("[data-comp-form-status]");
                if (st) st.textContent = "Deleting…";
                try {
                    await Store().remove(ctx.userId, ctx.locationId, id);
                    closeForm();
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Delete failed.";
                }
            });
            form?.addEventListener("submit", async (e) => {
                e.preventDefault();
                const st = form.querySelector("[data-comp-form-status]");
                if (st) st.textContent = "Saving…";
                try {
                    const payload = readForm(form);
                    const docId = id || Store().newId();
                    await Store().save(ctx.userId, ctx.locationId, docId, payload);
                    closeForm();
                    setStatus("Saved.");
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Save failed.";
                }
            });
        }

        container.addEventListener("click", (e) => {
            if (e.target.matches("[data-comp-add]")) {
                openForm(M().defaultItem(), "");
                return;
            }
            const editId = e.target.closest("[data-comp-edit]")?.dataset.compEdit;
            if (editId) {
                const item = (ctx.data.complianceItems || []).find((i) => i.id === editId);
                openForm(item || M().defaultItem(), editId);
            }
        });
    }

    window.OplixFacilityCompliance = {
        renderSection,
        bind,
        isComplianceSection(sectionId) {
            return sectionId === "compliance";
        },
    };
})();
