/**
 * Facility Lottery section — template customization, close shift, history (iOS parity).
 */
(function () {
    const Calc = () => window.OplixLotteryCalc;
    const Store = () => window.OplixLotteryStore;

    let userId = null;
    let embeddedLocationId = null;
    let currentRootId = "lottery-embedded-root";

    let state = {
        view: "history",
        terminal: 1,
        terminalCount: 1,
        templates: [],
        forms: [],
        shifts: [],
        peopleById: {},
        loading: false,
        saving: false,
        status: "",
        statusKind: "",
        selectedFormId: null,
        editRows: [],
        editRegister: "",
        editReverse: false,
        closeEnding: {},
        closeOnlineTotals: [""],
        closeOnlineCashes: [""],
        closeInstantCashes: [""],
        closeCashInHand: "",
        closeShiftId: "",
        closeImageFile: null,
        closeImagePreview: "",
        lastCloseSummary: null,
    };

    function $(sel, root) {
        return (root || document).querySelector(sel);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function formatCurrency(amount) {
        const n = Number(amount);
        if (!Number.isFinite(n)) return "—";
        return n.toLocaleString(undefined, { style: "currency", currency: "USD" });
    }

    function formatNumber(n) {
        const v = Number(n);
        if (!Number.isFinite(v)) return "—";
        return v.toLocaleString();
    }

    function toDate(v) {
        if (!v) return null;
        if (v.toDate) return v.toDate();
        if (v instanceof Date) return v;
        const d = new Date(v);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function setStatus(msg, kind) {
        state.status = msg || "";
        state.statusKind = kind || "";
    }

    function terminalCountFromLocation(loc) {
        const n = parseInt(loc?.lotteryTerminalCount, 10);
        return Number.isFinite(n) && n > 0 ? Math.min(n, 3) : 1;
    }

    function currentTemplate() {
        return (
            state.templates.find((t) => Store().effectiveTerminalNumber(t) === state.terminal) ||
            Store().emptyTemplate(embeddedLocationId, state.terminal <= 1 ? null : state.terminal)
        );
    }

    async function loadData() {
        if (!userId || !embeddedLocationId) return;
        state.loading = true;
        renderPanel();
        try {
            const [templates, forms] = await Promise.all([
                Store().fetchAllTemplates(userId, embeddedLocationId),
                Store().fetchForms(userId, embeddedLocationId, 50),
            ]);
            state.templates = templates;
            state.forms = forms;
            if (!templates.some((t) => Store().effectiveTerminalNumber(t) === state.terminal)) {
                state.templates.push(
                    Store().emptyTemplate(
                        embeddedLocationId,
                        state.terminal <= 1 ? null : state.terminal
                    )
                );
            }
            syncEditFromTemplate();
        } catch (err) {
            setStatus(err.message || "Could not load lottery data.", "error");
        } finally {
            state.loading = false;
            renderPanel();
        }
    }

    function syncEditFromTemplate() {
        const t = currentTemplate();
        state.editRows = (t.rows || []).map((r, i) => Store().normalizeRow(r, i));
        state.editRegister = t.lotteryRegisterAmount || "";
        state.editReverse = !!t.reverseOrder;
    }

    function syncCloseFromTemplate() {
        const t = currentTemplate();
        state.closeEnding = {};
        for (const row of t.rows || []) {
            state.closeEnding[row.id] = row.endingNumber || "";
        }
        state.closeOnlineTotals = [""];
        state.closeOnlineCashes = [""];
        state.closeInstantCashes = [""];
        state.closeCashInHand = "";
        state.closeShiftId = "";
        state.closeImageFile = null;
        if (state.closeImagePreview) URL.revokeObjectURL(state.closeImagePreview);
        state.closeImagePreview = "";
    }

    function liveCloseSummary() {
        const t = currentTemplate();
        const rows = (t.rows || []).map((row) => ({
            ...row,
            endingNumber: state.closeEnding[row.id] != null ? state.closeEnding[row.id] : row.endingNumber,
        }));
        const totals = Calc().calculateTemplateTotals(rows, !!t.reverseOrder);
        const onlineTotal = state.closeOnlineTotals
            .map(Calc().parseCashAmount)
            .find((n) => n != null);
        const summary = Calc().calculateShiftSummary(
            totals,
            onlineTotal,
            state.closeOnlineCashes.filter(Boolean),
            state.closeInstantCashes.filter(Boolean),
            t.lotteryRegisterAmount || null
        );
        const cashInHand = Calc().parseCashAmount(state.closeCashInHand);
        const overShort =
            cashInHand != null ? cashInHand - summary.cashInBagNet : null;
        return { summary, overShort, cashInHand };
    }

    function renderTabs() {
        const tabs = [
            { id: "history", label: "History" },
            { id: "customize", label: "Customize" },
            { id: "close", label: "Close shift" },
        ];
        return `
            <div class="lottery-subtabs">
                ${tabs
                    .map(
                        (t) =>
                            `<button type="button" class="lottery-subtab${state.view === t.id ? " is-active" : ""}" data-lottery-view="${t.id}">${escapeHtml(t.label)}</button>`
                    )
                    .join("")}
            </div>`;
    }

    function renderTerminalTabs() {
        if (state.terminalCount <= 1) return "";
        const items = [];
        for (let i = 1; i <= state.terminalCount; i++) {
            items.push(
                `<button type="button" class="lottery-term-tab${state.terminal === i ? " is-active" : ""}" data-lottery-terminal="${i}">Terminal ${i}</button>`
            );
        }
        return `<div class="lottery-term-tabs">${items.join("")}</div>`;
    }

    function renderStatus() {
        if (!state.status) return "";
        return `<p class="lottery-status lottery-status--${escapeHtml(state.statusKind || "info")}">${escapeHtml(state.status)}</p>`;
    }

    function renderHistory() {
        const forms = [...state.forms].sort(
            (a, b) => (toDate(b.submittedAt)?.getTime() || 0) - (toDate(a.submittedAt)?.getTime() || 0)
        );
        if (!forms.length) {
            return `<p class="data-list-empty">No lottery shift closes yet. Use <strong>Close shift</strong> or the iPhone app.</p>`;
        }
        return `
            <ul class="loc-row-list lottery-history-list">
                ${forms
                    .map((f) => {
                        const d = toDate(f.submittedAt);
                        const term =
                            f.terminalNumber != null && f.terminalNumber > 1
                                ? `Terminal ${f.terminalNumber}`
                                : "";
                        const sold = f.shiftSummary?.totalSoldAmount;
                        const os = f.shiftSummary?.overShort;
                        const sub = [
                            d ? d.toLocaleString() : "",
                            term,
                            sold != null ? formatCurrency(sold) + " sold" : "",
                            os != null ? formatCurrency(os) + (os >= 0 ? " over" : " short") : "",
                        ]
                            .filter(Boolean)
                            .join(" · ");
                        return `
                            <li class="loc-row-card lottery-history-row" data-lottery-form="${escapeHtml(f.id)}">
                                <div>
                                    <strong>Shift close</strong>
                                    <span class="data-list-meta">${escapeHtml(sub)}</span>
                                </div>
                                <span class="lottery-chevron">›</span>
                            </li>`;
                    })
                    .join("")}
            </ul>`;
    }

    function renderCustomizeTable() {
        if (state.loading) {
            return `<p class="data-list-empty">Loading template…</p>`;
        }
        const reverse = state.editReverse;
        const rows = state.editRows;
        let totalSold = 0;
        let totalDollars = 0;
        let totalBooks = 0;

        const body = rows
            .map((row, index) => {
                const calc = Calc().rowCalculated(
                    {
                        ...row,
                        beginningNumber: row.beginningNumber,
                        endingNumber: row.endingNumber,
                    },
                    reverse
                );
                totalSold += calc.sold;
                totalDollars += calc.dollars;
                totalBooks += calc.books;
                return `
                    <tr data-lottery-row="${escapeHtml(row.id)}">
                        <td class="lottery-cell-read">${index + 1}</td>
                        <td><input class="lottery-inp" data-lottery-field="gameNumber" value="${escapeHtml(row.gameNumber)}" /></td>
                        <td><input class="lottery-inp lottery-inp--sm" data-lottery-field="value" value="${escapeHtml(row.value)}" /></td>
                        <td><input class="lottery-inp lottery-inp--sm" data-lottery-field="tickets" value="${escapeHtml(row.tickets)}" /></td>
                        <td><input class="lottery-inp lottery-inp--sm" data-lottery-field="beginningNumber" value="${escapeHtml(row.beginningNumber)}" /></td>
                        <td><input class="lottery-inp lottery-inp--sm" data-lottery-field="endingNumber" value="${escapeHtml(row.endingNumber)}" /></td>
                        <td class="lottery-cell-read">${formatNumber(calc.sold)}</td>
                        <td class="lottery-cell-read">${formatCurrency(calc.dollars)}</td>
                        <td class="lottery-cell-read">${formatNumber(calc.books)}</td>
                        <td><button type="button" class="lottery-row-del" data-lottery-del-row="${escapeHtml(row.id)}" title="Remove row">×</button></td>
                    </tr>`;
            })
            .join("");

        return `
            <div class="lottery-settings">
                <label class="books-label">Register starting cash
                    <input class="books-input" id="lottery-register" value="${escapeHtml(state.editRegister)}" placeholder="0.00" />
                </label>
                <label class="lottery-check">
                    <input type="checkbox" id="lottery-reverse" ${state.editReverse ? "checked" : ""} />
                    Reverse ticket order
                </label>
            </div>
            <div class="lottery-table-wrap">
                <table class="lottery-table">
                    <thead>
                        <tr>
                            <th>Bin</th><th>Game</th><th>Value</th><th>Tickets</th>
                            <th>Begin</th><th>End</th><th>Sold</th><th>$</th><th>Books</th><th></th>
                        </tr>
                    </thead>
                    <tbody>${body || `<tr><td colspan="10" class="data-list-empty">No rows — add one below.</td></tr>`}</tbody>
                    <tfoot>
                        <tr class="lottery-totals-row">
                            <td></td><td><strong>TOTAL</strong></td><td colspan="4"></td>
                            <td><strong>${formatNumber(totalSold)}</strong></td>
                            <td><strong>${formatCurrency(totalDollars)}</strong></td>
                            <td><strong>${formatNumber(totalBooks)}</strong></td>
                            <td></td>
                        </tr>
                    </tfoot>
                </table>
            </div>
            <div class="lottery-toolbar">
                <button type="button" class="btn btn-secondary" id="lottery-add-row">Add row</button>
                <button type="button" class="btn" id="lottery-save-template" ${state.saving ? "disabled" : ""}>Save template</button>
            </div>`;
    }

    function renderCashFieldList(label, key, values) {
        const rows = values
            .map(
                (v, i) => `
                <div class="lottery-cash-row">
                    <input class="books-input" data-lottery-cash="${key}" data-lottery-cash-idx="${i}" value="${escapeHtml(v)}" placeholder="0.00" />
                    ${values.length > 1 ? `<button type="button" class="lottery-row-del" data-lottery-rm-cash="${key}" data-lottery-cash-idx="${i}">×</button>` : ""}
                </div>`
            )
            .join("");
        return `
            <div class="lottery-cash-block">
                <div class="lottery-cash-head">
                    <span>${escapeHtml(label)}</span>
                    <button type="button" class="btn-link" data-lottery-add-cash="${key}">+ Add</button>
                </div>
                ${rows}
            </div>`;
    }

    function renderCashFlowSummary(summary, overShort, cashInHand) {
        return `
            <div class="lottery-summary">
                <h3>Cash in &amp; cash out</h3>
                <div class="lottery-flow">
                    <p class="lottery-flow-title">Cash in</p>
                    ${summaryLine("Instant ticket sales", summary.instantTotal)}
                    ${summaryLine("Online lottery sales", summary.onlineTotal)}
                    ${summaryLine("Register starting cash", summary.registerCash)}
                    <div class="lottery-flow-total lottery-flow-total--in">
                        <span>Total cash in</span><strong>${formatCurrency(summary.totalCash)}</strong>
                    </div>
                </div>
                <div class="lottery-flow">
                    <p class="lottery-flow-title">Cash out</p>
                    ${summaryLine("Online payouts", summary.onlineCashes)}
                    ${summaryLine("Instant payouts", summary.instantCashes)}
                    <div class="lottery-flow-total lottery-flow-total--out">
                        <span>Total cash out</span><strong>${formatCurrency(summary.totalCashes)}</strong>
                    </div>
                </div>
                <div class="lottery-net">
                    ${summaryLine("Balance after cash out", summary.cashInBag)}
                    ${summary.registerCash > 0.005 ? summaryLine("Less register float", -summary.registerCash) : ""}
                    ${summaryLine("Expected enclosed cash", summary.cashInBagNet, true)}
                    ${cashInHand != null ? summaryLine("Actual enclosed cash", cashInHand, true) : ""}
                    ${
                        overShort != null
                            ? `<div class="lottery-net-row lottery-net-row--${overShort >= 0 ? "over" : "short"}">
                                <span>${overShort >= 0 ? "Over" : "Short"}</span>
                                <strong>${formatCurrency(overShort)}</strong>
                               </div>`
                            : ""
                    }
                </div>
            </div>`;
    }

    function summaryLine(label, value, emphasized) {
        return `
            <div class="lottery-net-row${emphasized ? " lottery-net-row--emph" : ""}">
                <span>${escapeHtml(label)}</span>
                <span>${formatCurrency(value)}</span>
            </div>`;
    }

    function renderClose() {
        const t = currentTemplate();
        const rows = t.rows || [];
        if (!rows.length) {
            return `<p class="data-list-empty">Customize the lottery template first — add rows with beginning numbers.</p>`;
        }

        const { summary, overShort, cashInHand } = liveCloseSummary();

        const tableRows = rows
            .map((row) => {
                const ending = state.closeEnding[row.id] ?? "";
                return `
                    <tr>
                        <td>${escapeHtml(row.gameNumber || "—")}</td>
                        <td>${escapeHtml(row.value || "—")}</td>
                        <td class="lottery-cell-read">${escapeHtml(row.beginningNumber || "—")}</td>
                        <td><input class="lottery-inp lottery-inp--sm" data-lottery-close-end="${escapeHtml(row.id)}" value="${escapeHtml(ending)}" placeholder="End #" /></td>
                    </tr>`;
            })
            .join("");

        const shiftOpts = state.shifts
            .filter((s) => s.clockInTime)
            .slice(0, 20)
            .map((s) => {
                const inT = toDate(s.clockInTime);
                const label = inT
                    ? `${state.peopleById[s.employeeId] || "Employee"} · ${inT.toLocaleString()}`
                    : s.id;
                return `<option value="${escapeHtml(s.id)}" ${state.closeShiftId === s.id ? "selected" : ""}>${escapeHtml(label)}</option>`;
            })
            .join("");

        return `
            <p class="books-hint">Enter ending ticket numbers and cash amounts, then close the shift. Data syncs with the iPhone app.</p>
            <label class="books-label">Link to shift (optional)
                <select class="books-select" id="lottery-close-shift">
                    <option value="">Web close (no shift link)</option>
                    ${shiftOpts}
                </select>
            </label>
            <div class="lottery-table-wrap lottery-table-wrap--close">
                <table class="lottery-table">
                    <thead><tr><th>Game</th><th>Value</th><th>Begin</th><th>End #</th></tr></thead>
                    <tbody>${tableRows}</tbody>
                </table>
            </div>
            ${renderCashFieldList("Online lottery sales", "onlineTotals", state.closeOnlineTotals)}
            ${renderCashFieldList("Online payouts", "onlineCashes", state.closeOnlineCashes)}
            ${renderCashFieldList("Instant payouts", "instantCashes", state.closeInstantCashes)}
            <label class="books-label">Actual enclosed cash
                <input class="books-input" id="lottery-cash-in-hand" value="${escapeHtml(state.closeCashInHand)}" placeholder="Required" />
            </label>
            <label class="books-label">Photo (optional)
                <input type="file" accept="image/*" id="lottery-close-photo" />
            </label>
            ${state.closeImagePreview ? `<img class="lottery-photo-preview" src="${state.closeImagePreview}" alt="Preview" />` : ""}
            ${renderCashFlowSummary(summary, overShort, cashInHand)}
            <div class="lottery-toolbar">
                <button type="button" class="btn" id="lottery-close-submit" ${state.saving ? "disabled" : ""}>Close shift</button>
            </div>`;
    }

    function renderDetail() {
        const form = state.forms.find((f) => f.id === state.selectedFormId);
        if (!form) {
            return `<p class="data-list-empty">Form not found.</p>`;
        }
        const d = toDate(form.submittedAt);
        const s = form.shiftSummary || {};
        const imageUrl = form.formData?.imageURL;
        const term =
            form.terminalNumber != null && form.terminalNumber > 1
                ? ` · Terminal ${form.terminalNumber}`
                : "";

        return `
            <button type="button" class="btn-link lottery-back" data-lottery-view="history">← Back to history</button>
            <h3 class="lottery-detail-title">Shift close${escapeHtml(term)}</h3>
            <p class="data-list-meta">${d ? d.toLocaleString() : ""}</p>
            ${imageUrl ? `<img class="lottery-photo-full" src="${escapeHtml(imageUrl)}" alt="Lottery close photo" />` : ""}
            <div class="lottery-detail-stats">
                <div><span>Tickets sold</span><strong>${formatNumber(s.totalSold)}</strong></div>
                <div><span>Instant sales</span><strong>${formatCurrency(s.instantTotal)}</strong></div>
                <div><span>Online sales</span><strong>${formatCurrency(s.onlineTotal)}</strong></div>
                <div><span>Total sold</span><strong>${formatCurrency(s.totalSoldAmount)}</strong></div>
                <div><span>Books</span><strong>${formatNumber(s.totalBooks)}</strong></div>
            </div>
            ${renderCashFlowSummary(s, s.overShort, s.overShort != null ? s.cashInBagNet + s.overShort : null)}
        `;
    }

    function renderPanel() {
        const root = document.getElementById(currentRootId);
        if (!root) return;

        let body = "";
        if (state.view === "history") body = renderHistory();
        else if (state.view === "customize") body = renderCustomizeTable();
        else if (state.view === "close") body = renderClose();
        else if (state.view === "detail") body = renderDetail();

        root.innerHTML = `
            ${renderTabs()}
            ${state.view !== "detail" && state.view !== "history" ? renderTerminalTabs() : ""}
            ${renderStatus()}
            ${state.loading && state.view === "history" ? '<p class="data-list-empty">Loading…</p>' : body}
        `;

        bindPanelEvents(root);
    }

    function bindPanelEvents(root) {
        root.querySelectorAll("[data-lottery-view]").forEach((btn) => {
            btn.addEventListener("click", () => {
                const view = btn.dataset.lotteryView;
                if (view === "customize") syncEditFromTemplate();
                if (view === "close") syncCloseFromTemplate();
                if (view === "history") state.selectedFormId = null;
                state.view = view;
                setStatus("");
                renderPanel();
            });
        });

        root.querySelectorAll("[data-lottery-terminal]").forEach((btn) => {
            btn.addEventListener("click", () => {
                state.terminal = parseInt(btn.dataset.lotteryTerminal, 10) || 1;
                if (state.view === "customize") syncEditFromTemplate();
                if (state.view === "close") syncCloseFromTemplate();
                renderPanel();
            });
        });

        root.querySelectorAll("[data-lottery-form]").forEach((row) => {
            row.addEventListener("click", () => {
                state.selectedFormId = row.dataset.lotteryForm;
                state.view = "detail";
                renderPanel();
            });
        });

        root.querySelector("#lottery-add-row")?.addEventListener("click", () => {
            state.editRows.push(Store().normalizeRow({}, state.editRows.length));
            renderPanel();
        });

        root.querySelectorAll("[data-lottery-del-row]").forEach((btn) => {
            btn.addEventListener("click", () => {
                const id = btn.dataset.lotteryDelRow;
                state.editRows = state.editRows.filter((r) => r.id !== id);
                renderPanel();
            });
        });

        root.querySelectorAll("[data-lottery-field]").forEach((inp) => {
            inp.addEventListener("input", () => {
                const tr = inp.closest("[data-lottery-row]");
                const id = tr?.dataset.lotteryRow;
                const field = inp.dataset.lotteryField;
                const row = state.editRows.find((r) => r.id === id);
                if (row && field) row[field] = inp.value;
            });
            inp.addEventListener("change", async () => {
                const tr = inp.closest("[data-lottery-row]");
                const id = tr?.dataset.lotteryRow;
                const field = inp.dataset.lotteryField;
                const row = state.editRows.find((r) => r.id === id);
                if (row && field) row[field] = inp.value;

                // Match iOS: when game # is entered, fill value + tickets from gameDatabase.
                if (field === "gameNumber" && row) {
                    const gameNumber = String(row.gameNumber || "").trim();
                    if (gameNumber) {
                        try {
                            const game = await Store().fetchGameData(gameNumber);
                            if (game) {
                                row.value = game.value != null ? String(game.value) : "";
                                row.tickets = game.tickets != null ? String(game.tickets) : "";
                                setStatus(
                                    `Game ${gameNumber}: $${row.value || "—"} · ${row.tickets || "—"} tickets`,
                                    "success"
                                );
                            } else {
                                setStatus(`Game ${gameNumber} not in game database.`, "info");
                            }
                        } catch (err) {
                            setStatus(err.message || "Could not look up game.", "error");
                        }
                    }
                }
                renderPanel();
            });
        });

        root.querySelector("#lottery-register")?.addEventListener("input", (e) => {
            state.editRegister = e.target.value;
        });

        root.querySelector("#lottery-reverse")?.addEventListener("change", (e) => {
            state.editReverse = e.target.checked;
            renderPanel();
        });

        root.querySelector("#lottery-save-template")?.addEventListener("click", saveTemplate);

        root.querySelectorAll("[data-lottery-close-end]").forEach((inp) => {
            inp.addEventListener("input", () => {
                state.closeEnding[inp.dataset.lotteryCloseEnd] = inp.value;
                const summaryEl = root.querySelector(".lottery-summary");
                if (summaryEl) {
                    const { summary, overShort, cashInHand } = liveCloseSummary();
                    summaryEl.outerHTML = renderCashFlowSummary(summary, overShort, cashInHand);
                }
            });
        });

        root.querySelectorAll("[data-lottery-cash]").forEach((inp) => {
            inp.addEventListener("input", () => {
                const key = inp.dataset.lotteryCash;
                const idx = parseInt(inp.dataset.lotteryCashIdx, 10);
                state[key][idx] = inp.value;
                const summaryEl = root.querySelector(".lottery-summary");
                if (summaryEl) {
                    const { summary, overShort, cashInHand } = liveCloseSummary();
                    summaryEl.outerHTML = renderCashFlowSummary(summary, overShort, cashInHand);
                }
            });
        });

        root.querySelectorAll("[data-lottery-add-cash]").forEach((btn) => {
            btn.addEventListener("click", () => {
                const key = btn.dataset.lotteryAddCash;
                state[key].push("");
                renderPanel();
            });
        });

        root.querySelectorAll("[data-lottery-rm-cash]").forEach((btn) => {
            btn.addEventListener("click", () => {
                const key = btn.dataset.lotteryRmCash;
                const idx = parseInt(btn.dataset.lotteryCashIdx, 10);
                state[key].splice(idx, 1);
                if (!state[key].length) state[key] = [""];
                renderPanel();
            });
        });

        root.querySelector("#lottery-cash-in-hand")?.addEventListener("input", (e) => {
            state.closeCashInHand = e.target.value;
            const summaryEl = root.querySelector(".lottery-summary");
            if (summaryEl) {
                const { summary, overShort, cashInHand } = liveCloseSummary();
                summaryEl.outerHTML = renderCashFlowSummary(summary, overShort, cashInHand);
            }
        });

        root.querySelector("#lottery-close-shift")?.addEventListener("change", (e) => {
            state.closeShiftId = e.target.value;
        });

        root.querySelector("#lottery-close-photo")?.addEventListener("change", (e) => {
            const file = e.target.files?.[0];
            if (state.closeImagePreview) URL.revokeObjectURL(state.closeImagePreview);
            state.closeImageFile = file || null;
            state.closeImagePreview = file ? URL.createObjectURL(file) : "";
            renderPanel();
        });

        root.querySelector("#lottery-close-submit")?.addEventListener("click", submitClose);
    }

    async function saveTemplate() {
        if (!userId || !embeddedLocationId) return;
        state.saving = true;
        setStatus("Saving…", "info");
        renderPanel();
        try {
            await OplixSaveBusy.run(async () => {
                const terminalNumber = state.terminal <= 1 ? null : state.terminal;
                await Store().saveTemplate(userId, embeddedLocationId, {
                    locationId: embeddedLocationId,
                    rows: state.editRows,
                    lotteryRegisterAmount: state.editRegister,
                    reverseOrder: state.editReverse,
                    terminalNumber,
                });
                await loadData();
            }, "Saving…");
            setStatus("Template saved.", "success");
            state.saving = false;
        } catch (err) {
            setStatus(err.message || "Could not save template.", "error");
            state.saving = false;
            renderPanel();
        }
    }

    async function submitClose() {
        if (!userId || !embeddedLocationId) return;
        const cashInHand = Calc().parseCashAmount(state.closeCashInHand);
        if (cashInHand == null) {
            setStatus("Enter actual enclosed cash before closing.", "error");
            renderPanel();
            return;
        }

        state.saving = true;
        setStatus("Closing shift…", "info");
        renderPanel();

        try {
            await OplixSaveBusy.run(async () => {
                const template = currentTemplate();
                const terminalNumber = state.terminal <= 1 ? null : state.terminal;
                const result = await Store().closeShift(userId, embeddedLocationId, {
                    template,
                    endingByRowId: state.closeEnding,
                    onlineTotals: state.closeOnlineTotals.filter(Boolean),
                    onlineCashes: state.closeOnlineCashes.filter(Boolean),
                    instantCashes: state.closeInstantCashes.filter(Boolean),
                    cashInHand,
                    shiftId: state.closeShiftId || undefined,
                    imageFile: state.closeImageFile,
                    terminalNumber,
                });

                state.lastCloseSummary = result.summary;
                state.selectedFormId = result.form.id;
                state.view = "detail";
                await loadData();
            }, "Closing shift…");
            setStatus("Shift closed successfully.", "success");
            state.saving = false;
        } catch (err) {
            setStatus(err.message || "Could not close shift.", "error");
            state.saving = false;
            renderPanel();
        }
    }

    async function init(ctx) {
        userId = ctx.userId;
        embeddedLocationId = ctx.locationId;
        currentRootId = ctx.rootId || "lottery-embedded-root";
        state.terminalCount = terminalCountFromLocation(ctx.location);
        state.shifts = ctx.shifts || [];
        const people = ctx.data?.allPeople || ctx.allPeople || [];
        state.peopleById = {};
        for (const p of people) {
            if (p?.id) state.peopleById[p.id] = p.name || "Employee";
        }
        state.view = "history";
        state.terminal = 1;
        setStatus("");
        await loadData();
    }

    function renderEmbedded(ctx) {
        return `
            <h2 class="loc-section-heading">Lottery</h2>
            <p class="books-hint dir-hint">Customize templates, close shifts, and view history — same data as the iPhone app.</p>
            <div id="lottery-embedded-root"></div>`;
    }

    function bindEmbedded(container, ctx) {
        const slot = container.querySelector("#lottery-embedded-root");
        if (!slot) return;
        init({
            userId: ctx.userId,
            locationId: ctx.locationId,
            location: ctx.data?.location || ctx.location,
            shifts: ctx.data?.shifts || [],
            data: ctx.data,
            rootId: "lottery-embedded-root",
        });
    }

    window.OplixLotteryUI = {
        renderEmbedded,
        bindEmbedded,
    };
})();
