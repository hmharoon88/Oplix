/**
 * Payables tab UI for Daily books (shared Firestore path with iOS).
 */
(function () {
    const M = () => window.OplixPayablesModel;
    const Store = () => window.OplixPayablesStore;

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function money(v) {
        return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
            parseFloat(v) || 0
        );
    }

    function formatDue(p) {
        const d = M().toDate(p.dueDate);
        if (!d) return "No due date";
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function freqLabel(id) {
        return M().FREQUENCIES.find((f) => f.id === id)?.label || id;
    }

    function renderRow(p, ctx) {
        const overdue =
            !p.isPaid &&
            M().toDate(p.dueDate) &&
            M().toDate(p.dueDate) < new Date(new Date().setHours(0, 0, 0, 0));
        return `
            <li class="loc-row-card dir-row pay-row" data-pay-id="${escapeHtml(p.id)}">
                <div>
                    <strong>${money(p.amount)} · ${escapeHtml(p.payTo || "Payable")}</strong>
                    <span class="data-list-meta">${escapeHtml(formatDue(p))}${p.frequency !== "none" ? ` · ${escapeHtml(freqLabel(p.frequency))}` : ""}${overdue ? " · <strong class=\"pay-overdue\">Overdue</strong>" : ""}</span>
                    ${p.notes ? `<span class="data-list-meta">${escapeHtml(p.notes)}</span>` : ""}
                </div>
                <div class="dir-row-actions pay-row-actions">
                    ${
                        !p.isPaid
                            ? `<button type="button" class="btn btn-nav-outline pay-btn-paid" data-pay-mark="${escapeHtml(p.id)}">Mark paid</button>`
                            : ""
                    }
                    <button type="button" class="dir-btn-edit" data-pay-edit="${escapeHtml(p.id)}">Edit</button>
                </div>
            </li>`;
    }

    function renderForm(payable, id, locationId) {
        const p = M().normalizePayable(payable, locationId);
        const freqOpts = M().FREQUENCIES.map(
            (f) =>
                `<option value="${f.id}"${f.id === p.frequency ? " selected" : ""}>${escapeHtml(f.label)}</option>`
        ).join("");
        return `
            <form class="dir-form pay-form" data-pay-form data-pay-id="${escapeHtml(id)}">
                <div class="books-grid-2">
                    <label class="books-label">Pay to *
                        <input class="books-input" name="payTo" required value="${escapeHtml(p.payTo)}">
                    </label>
                    <label class="books-label">Amount ($) *
                        <input class="books-input books-input-amount" name="amount" type="text" inputmode="decimal" autocomplete="off" required value="${escapeHtml(window.OplixBooksModel ? OplixBooksModel.formatAmountForInput(p.amount) : p.amount || "")}">
                    </label>
                    <label class="books-label">Due date
                        <input class="books-input" name="dueDate" type="date" value="${escapeHtml(M().isoDateInput(p.dueDate))}">
                    </label>
                    <label class="books-label">Frequency
                        <select class="books-select" name="frequency">${freqOpts}</select>
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="2">${escapeHtml(p.notes)}</textarea>
                </label>
                ${
                    id
                        ? `<label class="books-label pay-paid-check">
                            <input type="checkbox" name="isPaid"${p.isPaid ? " checked" : ""}> Mark as paid
                        </label>`
                        : ""
                }
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save payable</button>
                    <button type="button" class="btn btn-nav-outline" data-pay-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn fac-btn-delete" data-pay-delete>Delete</button>` : ""}
                    <span class="dir-status" data-pay-form-status></span>
                </div>
            </form>`;
    }

    function readForm(form, locationId, existing) {
        const fd = new FormData(form);
        const dueStr = String(fd.get("dueDate") || "").trim();
        return M().normalizePayable(
            {
                ...existing,
                locationId,
                payTo: fd.get("payTo"),
                amount: window.OplixBooksModel
                    ? OplixBooksModel.num(fd.get("amount"))
                    : parseFloat(fd.get("amount")) || 0,
                dueDate: M().dueTimestampFromInput(dueStr),
                frequency: fd.get("frequency"),
                notes: fd.get("notes"),
                isPaid: form.querySelector('[name="isPaid"]')?.checked || false,
            },
            locationId
        );
    }

    function renderTab(ctx) {
        const open = M().openPayablesForMonth(ctx.payables, ctx.monthId);
        const paid = M().paidPayablesForMonth(ctx.payables, ctx.monthId);
        const total = M().openTotal(ctx.payables);

        return `
            <div class="books-panel data-input-form pay-section" data-pay-section>
                <p class="books-hint">Bills and vendors you owe — saved to the same payables list as the Oplix app for this facility.</p>
                <div class="loc-total-banner pay-total-banner">
                    <span>Open payables</span>
                    <strong>${money(total)}</strong>
                    <span class="data-list-meta">${open.length} open</span>
                </div>
                <div class="dir-toolbar">
                    <button type="button" class="btn" data-pay-add>Add payable</button>
                    <span class="dir-status" data-pay-status></span>
                </div>
                <div class="dir-form-slot" data-pay-form-slot hidden></div>

                <h3 class="loc-subheading">Open (${open.length})</h3>
                ${
                    open.length
                        ? `<ul class="loc-row-list dir-list">${open.map((p) => renderRow(p, ctx)).join("")}</ul>`
                        : `<p class="data-list-empty">No open payables.</p>`
                }

                <h3 class="loc-subheading">Paid this month (${paid.length})</h3>
                ${
                    paid.length
                        ? `<ul class="loc-row-list dir-list">${paid.map((p) => renderRow(p, ctx)).join("")}</ul>`
                        : `<p class="data-list-empty">No payables marked paid this month yet.</p>`
                }
            </div>`;
    }

    function bind(container, ctx) {
        if (!container || container.dataset.payBound) return;
        container.dataset.payBound = "1";

        const slot = container.querySelector("[data-pay-form-slot]");
        const statusEl = container.querySelector("[data-pay-status]");
        let paySaveReady = null;

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function closeForm() {
            paySaveReady?.detach();
            paySaveReady = null;
            if (slot) {
                slot.hidden = true;
                slot.innerHTML = "";
            }
        }

        function openForm(item, id) {
            if (!slot) return;
            paySaveReady?.detach();
            slot.hidden = false;
            slot.innerHTML = renderForm(item, id, ctx.locationId);
            const form = slot.querySelector("[data-pay-form]");
            if (window.OplixFormSaveReady) {
                paySaveReady = OplixFormSaveReady.watch(slot, { mode: id ? "edit" : "new" });
            }
            form?.querySelector("[data-pay-cancel]")?.addEventListener("click", closeForm);
            form?.querySelector("[data-pay-delete]")?.addEventListener("click", async () => {
                if (!id || !confirm("Delete this payable?")) return;
                const st = form.querySelector("[data-pay-form-status]");
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
                const st = form.querySelector("[data-pay-form-status]");
                if (st) st.textContent = "Saving…";
                const amountEl = form.querySelector('[name="amount"]');
                if (amountEl && window.OplixBooksModel) {
                    const n = OplixBooksModel.parseAmountExpression(amountEl.value);
                    if (Number.isFinite(n)) {
                        amountEl.value = OplixBooksModel.formatAmountForInput(n);
                    }
                }
                try {
                    const existing = (ctx.payables || []).find((p) => p.id === id) || {};
                    const payload = readForm(form, ctx.locationId, {
                        ...existing,
                        id: id || Store().newId(),
                        createdAt: existing.createdAt,
                    });
                    if (!payload.isPaid) payload.paidAt = null;
                    else if (!existing.paidAt) {
                        payload.paidAt = firebase.firestore.FieldValue.serverTimestamp();
                    } else payload.paidAt = existing.paidAt;
                    await Store().save(ctx.userId, ctx.locationId, payload);
                    closeForm();
                    setStatus("Saved.");
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Save failed.";
                }
            });
        }

        container.addEventListener("click", async (e) => {
            if (e.target.matches("[data-pay-add]")) {
                openForm(M().defaultPayable(ctx.locationId), "");
                return;
            }
            const editId = e.target.closest("[data-pay-edit]")?.dataset.payEdit;
            if (editId) {
                const item = (ctx.payables || []).find((p) => p.id === editId);
                openForm(item || M().defaultPayable(ctx.locationId), editId);
                return;
            }
            const markId = e.target.closest("[data-pay-mark]")?.dataset.payMark;
            if (markId) {
                const item = (ctx.payables || []).find((p) => p.id === markId);
                if (!item) return;
                setStatus("Updating…");
                try {
                    await Store().markPaid(ctx.userId, ctx.locationId, item);
                    setStatus("Marked paid.");
                    await ctx.onRefresh();
                } catch (err) {
                    setStatus(err.message || "Update failed.");
                }
            }
        });
    }

    window.OplixPayablesUI = {
        renderTab,
        bind,
    };
})();
