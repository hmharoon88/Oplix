/**
 * Receivables UI — facility section (mirrors payables).
 */
(function () {
    const M = () => window.OplixReceivablesModel;
    const Store = () => window.OplixReceivablesStore;

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

    function formatDue(r) {
        const d = M().toDate(r.dueDate);
        if (!d) return "No due date";
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function freqLabel(id) {
        return M().FREQUENCIES.find((f) => f.id === id)?.label || id;
    }

    function renderRow(r) {
        const overdue =
            !r.isReceived &&
            M().toDate(r.dueDate) &&
            M().toDate(r.dueDate) < new Date(new Date().setHours(0, 0, 0, 0));
        return `
            <li class="loc-row-card dir-row pay-row" data-rec-id="${escapeHtml(r.id)}">
                <div>
                    <strong>${money(r.amount)} · ${escapeHtml(r.receiveFrom || "Receivable")}</strong>
                    <span class="data-list-meta">${escapeHtml(formatDue(r))}${r.frequency !== "none" ? ` · ${escapeHtml(freqLabel(r.frequency))}` : ""}${overdue ? ' · <strong class="pay-overdue">Overdue</strong>' : ""}</span>
                    ${r.notes ? `<span class="data-list-meta">${escapeHtml(r.notes)}</span>` : ""}
                </div>
                <div class="dir-row-actions pay-row-actions">
                    ${
                        !r.isReceived
                            ? `<button type="button" class="btn btn-nav-outline pay-btn-paid" data-rec-mark="${escapeHtml(r.id)}">Mark received</button>`
                            : ""
                    }
                    <button type="button" class="dir-btn-edit" data-rec-edit="${escapeHtml(r.id)}">Edit</button>
                </div>
            </li>`;
    }

    function renderForm(receivable, id, locationId) {
        const r = M().normalizeReceivable(receivable, locationId);
        const freqOpts = M().FREQUENCIES.map(
            (f) =>
                `<option value="${f.id}"${f.id === r.frequency ? " selected" : ""}>${escapeHtml(f.label)}</option>`
        ).join("");
        return `
            <form class="dir-form pay-form" data-rec-form data-rec-id="${escapeHtml(id)}">
                <div class="books-grid-2">
                    <label class="books-label">Receive from *
                        <input class="books-input" name="receiveFrom" required value="${escapeHtml(r.receiveFrom)}">
                    </label>
                    <label class="books-label">Amount ($) *
                        <input class="books-input books-input-amount" name="amount" type="text" inputmode="decimal" autocomplete="off" required value="${escapeHtml(window.OplixBooksModel ? OplixBooksModel.formatAmountForInput(r.amount) : r.amount || "")}">
                    </label>
                    <label class="books-label">Due date
                        <input class="books-input" name="dueDate" type="date" value="${escapeHtml(M().isoDateInput(r.dueDate))}">
                    </label>
                    <label class="books-label">Frequency
                        <select class="books-select" name="frequency">${freqOpts}</select>
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="2">${escapeHtml(r.notes)}</textarea>
                </label>
                ${
                    id
                        ? `<label class="books-label pay-paid-check">
                            <input type="checkbox" name="isReceived"${r.isReceived ? " checked" : ""}> Mark as received
                        </label>`
                        : ""
                }
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save receivable</button>
                    <button type="button" class="btn btn-nav-outline" data-rec-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn fac-btn-delete" data-rec-delete>Delete</button>` : ""}
                    <span class="dir-status" data-rec-form-status></span>
                </div>
            </form>`;
    }

    function readForm(form, locationId, existing) {
        const fd = new FormData(form);
        const dueStr = String(fd.get("dueDate") || "").trim();
        return M().normalizeReceivable(
            {
                ...existing,
                locationId,
                receiveFrom: fd.get("receiveFrom"),
                amount: window.OplixBooksModel
                    ? OplixBooksModel.num(fd.get("amount"))
                    : parseFloat(fd.get("amount")) || 0,
                dueDate: M().dueTimestampFromInput(dueStr),
                frequency: fd.get("frequency"),
                notes: fd.get("notes"),
                isReceived: form.querySelector('[name="isReceived"]')?.checked || false,
            },
            locationId
        );
    }

    function renderShell(opts) {
        const {
            hint,
            totalLabel,
            total,
            openCount,
            open,
            received,
            receivedHeading,
            receivedEmpty,
        } = opts;
        return `
            <div class="books-panel pay-section${opts.facility ? " pay-section--facility" : " data-input-form"}" data-rec-section>
                <h2 class="loc-section-heading">Receivables</h2>
                <p class="books-hint">${hint}</p>
                <div class="loc-total-banner pay-total-banner">
                    <span>${totalLabel}</span>
                    <strong>${money(total)}</strong>
                    <span class="data-list-meta">${openCount} open</span>
                </div>
                <div class="dir-toolbar">
                    <button type="button" class="btn" data-rec-add>Add receivable</button>
                    <span class="dir-status" data-rec-status></span>
                </div>
                <div class="dir-form-slot" data-rec-form-slot hidden></div>

                <h3 class="loc-subheading">Open (${open.length})</h3>
                ${
                    open.length
                        ? `<ul class="loc-row-list dir-list">${open.map(renderRow).join("")}</ul>`
                        : `<p class="data-list-empty">No open receivables.</p>`
                }

                <h3 class="loc-subheading">${receivedHeading}</h3>
                ${
                    received.length
                        ? `<ul class="loc-row-list dir-list">${received.map(renderRow).join("")}</ul>`
                        : `<p class="data-list-empty">${receivedEmpty}</p>`
                }
            </div>`;
    }

    async function afterReceivableChange(ctx, receivable) {
        if (ctx.onSyncBooks) await ctx.onSyncBooks(receivable);
    }

    async function carryPayerForwardIfNeeded(ctx, receivedItem) {
        if (!receivedItem?.isReceived) return false;
        const id = await Store().ensureNextOpenForBooks(
            ctx.userId,
            ctx.locationId,
            receivedItem,
            ctx.receivables
        );
        return !!id;
    }

    function renderTab(ctx) {
        const open = M().openReceivables(ctx.receivables);
        const received = M().receivedReceivablesForMonth(ctx.receivables, ctx.monthId);
        const total = M().openTotal(ctx.receivables);

        return renderShell({
            hint: "Add who pays you, enter the amount, and mark <strong>received</strong> (counts in Books Net). Same person can pay more than once in a month — use <strong>Add receivable</strong> again for each check. After each received one-time item, that payer stays open next month at $0 for the next amount. Leave Frequency as <strong>One-time</strong> for this books flow.",
            totalLabel: "Open receivables",
            total,
            openCount: open.length,
            open,
            received,
            receivedHeading: `Received this month (${received.length}) — counts in Books Net`,
            receivedEmpty: "Nothing marked received this month yet.",
            ctx,
            books: true,
        });
    }

    function renderFacilitySection(ctx) {
        const all = ctx.receivables || [];
        const open = M().openReceivables(all);
        const paid = M().sortReceivables(all.filter((r) => r.isReceived)).slice(0, 50);
        const total = M().openTotal(all);

        return renderShell({
            hint: "Same list as Daily books → Receivables. Mark received to sync into that month’s Books Net. On web, one-time items keep the payer open next month at $0 for the next amount.",
            totalLabel: "Open receivables",
            total,
            openCount: open.length,
            open,
            received: paid,
            receivedHeading: `Received (${paid.length}${all.filter((r) => r.isReceived).length > paid.length ? "+ shown" : ""})`,
            receivedEmpty: "No received receivables yet.",
            facility: true,
        });
    }

    function bind(container, ctx) {
        if (!container || container.dataset.recBound) return;
        container.dataset.recBound = "1";

        const slot = container.querySelector("[data-rec-form-slot]");
        const statusEl = container.querySelector("[data-rec-status]");
        let saveReady = null;

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function closeForm() {
            saveReady?.detach();
            saveReady = null;
            if (slot) {
                slot.hidden = true;
                slot.innerHTML = "";
            }
        }

        function openForm(item, id) {
            if (!slot) return;
            saveReady?.detach();
            slot.hidden = false;
            slot.innerHTML = renderForm(item, id, ctx.locationId);
            if (window.OplixFormSaveReady) {
                saveReady = OplixFormSaveReady.watch(slot, { mode: id ? "edit" : "new" });
            }
            const form = slot.querySelector("[data-rec-form]");
            form?.querySelector("[data-rec-cancel]")?.addEventListener("click", closeForm);
            form?.querySelector("[data-rec-delete]")?.addEventListener("click", async () => {
                if (!id || !confirm("Delete this receivable?")) return;
                const st = form.querySelector("[data-rec-form-status]");
                if (st) st.textContent = "Deleting…";
                try {
                    await Store().remove(ctx.userId, ctx.locationId, id);
                    await afterReceivableChange(ctx, { id, isReceived: false });
                    closeForm();
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Delete failed.";
                }
            });
            form?.addEventListener("submit", async (e) => {
                e.preventDefault();
                const st = form.querySelector("[data-rec-form-status]");
                if (st) st.textContent = "Saving…";
                const amountEl = form.querySelector('[name="amount"]');
                if (amountEl && window.OplixBooksModel) {
                    const n = OplixBooksModel.parseAmountExpression(amountEl.value);
                    if (Number.isFinite(n)) {
                        amountEl.value = OplixBooksModel.formatAmountForInput(n);
                    }
                }
                try {
                    await OplixSaveBusy.run(async () => {
                        const existing = (ctx.receivables || []).find((r) => r.id === id) || {};
                        const wasReceived = !!existing.isReceived;
                        const payload = readForm(form, ctx.locationId, {
                            ...existing,
                            id: id || Store().newId(),
                            createdAt: existing.createdAt,
                        });
                        if (!payload.isReceived) payload.receivedAt = null;
                        else if (!existing.receivedAt) {
                            payload.receivedAt = firebase.firestore.FieldValue.serverTimestamp();
                        } else payload.receivedAt = existing.receivedAt;
                        await Store().save(ctx.userId, ctx.locationId, payload);
                        await afterReceivableChange(ctx, payload);
                        if (payload.isReceived && !wasReceived) {
                            await carryPayerForwardIfNeeded(ctx, payload);
                        }
                    }, "Saving…");
                    closeForm();
                    setStatus("Saved.");
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Save failed.";
                }
            });
        }

        container.addEventListener("click", async (e) => {
            if (e.target.matches("[data-rec-add]")) {
                openForm(M().defaultReceivable(ctx.locationId), "");
                return;
            }
            const editId = e.target.closest("[data-rec-edit]")?.dataset.recEdit;
            if (editId) {
                const item = (ctx.receivables || []).find((r) => r.id === editId);
                openForm(item || M().defaultReceivable(ctx.locationId), editId);
                return;
            }
            const markId = e.target.closest("[data-rec-mark]")?.dataset.recMark;
            if (markId) {
                const item = (ctx.receivables || []).find((r) => r.id === markId);
                if (!item) return;
                setStatus("Updating…");
                try {
                    let carried = false;
                    await OplixSaveBusy.run(async () => {
                        await Store().markReceived(ctx.userId, ctx.locationId, item);
                        const received = { ...item, isReceived: true, receivedAt: new Date() };
                        await afterReceivableChange(ctx, received);
                        carried = await carryPayerForwardIfNeeded(ctx, received);
                    }, "Updating…");
                    setStatus(
                        carried
                            ? "Marked received — added to Books Net. Same payer kept open for next month ($0 — enter new amount)."
                            : "Marked received — added to Books Net for this month."
                    );
                    await ctx.onRefresh();
                } catch (err) {
                    setStatus(err.message || "Update failed.");
                }
            }
        });
    }

    window.OplixReceivablesUI = {
        renderTab,
        renderFacilitySection,
        bind,
        isReceivablesSection(sectionId) {
            return sectionId === "receivables";
        },
    };
})();
