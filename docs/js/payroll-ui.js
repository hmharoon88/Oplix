/**
 * Web Payroll — pay-period runs (shared with iOS `payrollRuns`), synced to Daily books.
 */
(function () {
    const M = () => window.OplixPayrollModel;
    const Store = () => window.OplixPayrollStore;
    const B = () => window.OplixBooksModel;

    let userId = null;
    let locations = [];
    let currentRootId = "payroll-root";
    let state = {
        locationId: "",
        periodStart: M().isoDateOnly(new Date()),
        periodEnd: M().isoDateOnly(new Date()),
        hoursText: {},
        note: "",
        pastRuns: [],
        employees: [],
        expandedRunId: null,
        status: "",
        loading: false,
        embeddedLocationId: null,
    };

    function $(id, root) {
        return (root || document).getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function money(v) {
        return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
            M().num(v)
        );
    }

    function locName(id) {
        return locations.find((l) => l.id === id)?.name || "Facility";
    }

    function effectiveLocationId() {
        return state.embeddedLocationId || state.locationId;
    }

    function parsedHours(employeeId) {
        const raw = String(state.hoursText[employeeId] ?? "").trim();
        if (!raw) return 0;
        return B().num(raw);
    }

    function draftLines() {
        return state.employees.map((emp) => {
            const hours = parsedHours(emp.id);
            const hourlyRate = B().num(emp.hourlyRate);
            const grossPay = Math.round(hours * hourlyRate * 100) / 100;
            return {
                id: emp.id,
                employeeName: emp.name || emp.username || "Employee",
                hourlyRate,
                hours,
                grossPay,
                pay: grossPay,
            };
        });
    }

    function draftTotals() {
        const lines = draftLines().filter((l) => l.hours > 0);
        return {
            hours: lines.reduce((s, l) => s + l.hours, 0),
            pay: lines.reduce((s, l) => s + l.pay, 0),
            count: lines.length,
        };
    }

    function hasAnyHours() {
        return draftLines().some((l) => l.hours > 0);
    }

    function applySuggestedPeriod() {
        const suggested = M().suggestPeriodFromLastRun(state.pastRuns[0]);
        state.periodStart = suggested.periodStart;
        state.periodEnd = suggested.periodEnd;
    }

    async function loadEmployees() {
        const locId = effectiveLocationId();
        if (!locId || !userId) {
            state.employees = [];
            return;
        }
        const list = await Store().listEmployees(userId, locId);
        state.employees = await Store().enrichEmployeesFromManager(userId, list);
    }

    async function loadRuns() {
        const locId = effectiveLocationId();
        if (!userId || !locId) {
            state.pastRuns = [];
            return;
        }
        state.pastRuns = await Store().listRuns(userId, locId);
        applySuggestedPeriod();
    }

    function render() {
        renderPanel(currentRootId);
    }

    async function loadAll() {
        const locId = effectiveLocationId();
        if (!userId) return;
        if (!locId) {
            render();
            return;
        }
        state.loading = true;
        state.status = "Loading…";
        render();
        try {
            await loadEmployees();
            await loadRuns();
            state.status = "";
        } catch (err) {
            state.status = err.message || "Failed to load payroll.";
        } finally {
            state.loading = false;
            render();
        }
    }

    function syncPeriodFromDom(root) {
        const start = root.querySelector("#payroll-period-start");
        const end = root.querySelector("#payroll-period-end");
        const note = root.querySelector("#payroll-note");
        if (start) state.periodStart = start.value;
        if (end) state.periodEnd = end.value;
        if (note) state.note = note.value;
    }

    function syncHoursFromDom(root) {
        root.querySelectorAll("[data-payroll-employee]").forEach((rowEl) => {
            const employeeId = rowEl.dataset.payrollEmployee;
            const hoursInput = rowEl.querySelector('[name="hours"]');
            if (employeeId && hoursInput) {
                state.hoursText[employeeId] = hoursInput.value;
            }
        });
    }

    function normalizeAmountFields(root) {
        root.querySelectorAll(".books-input-amount").forEach((el) => {
            const raw = String(el.value ?? "").trim();
            if (raw === "") return;
            const n = B().parseAmountExpression(raw);
            if (Number.isFinite(n)) el.value = B().formatAmountForInput(n);
        });
    }

    async function saveRun(root) {
        normalizeAmountFields(root);
        syncPeriodFromDom(root);
        syncHoursFromDom(root);

        const locId = effectiveLocationId();
        if (!locId) return;

        if (state.periodEnd < state.periodStart) {
            state.status = "Pay-through date must be on or after the period start.";
            render();
            return;
        }
        if (!hasAnyHours()) {
            state.status = "Enter hours for at least one employee.";
            render();
            return;
        }

        state.status = "Saving…";
        render();

        const run = M().buildRunFromDraft({
            locationId: locId,
            periodStart: state.periodStart,
            periodEnd: state.periodEnd,
            note: state.note,
            lines: draftLines(),
            createdSource: "web",
        });

        try {
            await OplixSaveBusy.run(async () => {
                const saved = await Store().saveRun(userId, locId, run);
                await Store().applyLoanBalances(userId, locId, saved.lines);
                let booksNote = "";
                try {
                    const sync = await Store().syncRunToBooks(userId, locId, saved);
                    const monthLabel = sync.monthId
                        ? B().parseMonthId(sync.monthId).toLocaleDateString("en-US", {
                              month: "long",
                              year: "numeric",
                          })
                        : "";
                    booksNote = monthLabel
                        ? ` Synced to Daily books (${monthLabel}).`
                        : " Synced to Daily books.";
                    if (window.OplixDataInput?.refreshIfOpen && sync.monthId) {
                        OplixDataInput.refreshIfOpen(locId, sync.monthId);
                    }
                } catch (syncErr) {
                    booksNote = ` Daily books were not updated (${syncErr.message || syncErr}).`;
                }

                state.hoursText = {};
                state.note = "";
                await loadRuns();
                state.status = `Payroll saved for ${M().formatPeriod(saved.periodStart, saved.periodEnd)}.${booksNote}`;
            }, "Saving…");
            setTimeout(() => {
                if (state.status.includes("Payroll saved")) state.status = "";
                render();
            }, 4500);
        } catch (err) {
            state.status = err.message || "Save failed.";
            render();
        }
    }

    function renderEmployeeRow(emp) {
        const hours = state.hoursText[emp.id] ?? "";
        const rate = B().num(emp.hourlyRate);
        const pay = M().calcPay(B().num(hours), rate);
        const name = emp.name || emp.username || "Employee";
        return `
            <div class="books-lines-row payroll-lines-row" data-payroll-employee="${escapeHtml(emp.id)}">
                <span class="payroll-employee-name">${escapeHtml(name)}</span>
                <input type="text" inputmode="decimal" autocomplete="off" class="books-input books-input-amount" name="hours" placeholder="0" value="${escapeHtml(hours)}">
                <span class="payroll-rate-cell">${rate > 0 ? money(rate) : "—"}</span>
                <span class="payroll-pay-cell" data-payroll-pay>${money(pay)}</span>
            </div>`;
    }

    function renderRunHistory() {
        if (!state.pastRuns.length) return "";
        const items = state.pastRuns
            .slice(0, 12)
            .map((run) => {
                const expanded = state.expandedRunId === run.id;
                const totals = M().runTotals(run);
                const lines = expanded
                    ? run.lines
                          .map(
                              (line) =>
                                  `<li>${escapeHtml(line.employeeName)} — ${line.hours.toFixed(2)} hrs · ${money(line.pay)}</li>`
                          )
                          .join("")
                    : "";
                return `
                    <div class="payroll-history-item">
                        <button type="button" class="payroll-history-toggle" data-payroll-run-toggle="${escapeHtml(run.id)}">
                            <span>${escapeHtml(M().formatPeriod(run.periodStart, run.periodEnd))}</span>
                            <span class="payroll-history-meta">${totals.count} employees · ${money(totals.pay)} net</span>
                        </button>
                        ${expanded ? `<ul class="payroll-history-lines">${lines}</ul>` : ""}
                    </div>`;
            })
            .join("");

        return `
            <section class="payroll-history">
                <h3 class="books-subtitle">Recent payroll runs</h3>
                <p class="books-hint">Saved runs from web and the iOS app share the same history.</p>
                ${items}
            </section>`;
    }

    function renderPanel(rootId) {
        const root = document.getElementById(rootId || "payroll-root");
        if (!root) return;

        if (!locations.length) {
            root.innerHTML =
                '<p class="data-list-empty">Add a facility first, then enter payroll hours here.</p>';
            return;
        }

        const totals = draftTotals();
        const lastRun = state.pastRuns[0];

        const locField = state.embeddedLocationId
            ? ""
            : `<label class="books-label">Facility
                <select id="payroll-location" class="books-select">
                    ${locations
                        .map(
                            (l) =>
                                `<option value="${l.id}"${l.id === effectiveLocationId() ? " selected" : ""}>${escapeHtml(l.name)}</option>`
                        )
                        .join("")}
                </select>
            </label>`;

        root.innerHTML = `
            <div class="payroll-panel" data-payroll-panel>
                <div class="bs-toolbar payroll-toolbar">
                    <div class="bs-toolbar-fields">
                        ${locField}
                    </div>
                    <button type="button" class="btn btn-nav-outline" id="payroll-reload"${state.loading ? " disabled" : ""}>Reload</button>
                </div>

                <p class="books-hint">Enter hours for each employee, choose the pay period, and save. Net pay syncs to <strong>Daily books</strong> — same data as the iOS payroll sheet.</p>

                <div class="payroll-period-card">
                    <h3 class="books-subtitle">Pay period</h3>
                    ${
                        lastRun
                            ? `<p class="books-hint">Last paid: <strong>${escapeHtml(M().formatPeriod(lastRun.periodStart, lastRun.periodEnd))}</strong></p>`
                            : ""
                    }
                    <div class="payroll-period-fields">
                        <label class="books-label">From
                            <input type="date" id="payroll-period-start" class="books-input" value="${escapeHtml(state.periodStart)}">
                        </label>
                        <label class="books-label">Pay through
                            <input type="date" id="payroll-period-end" class="books-input" value="${escapeHtml(state.periodEnd)}" min="${escapeHtml(state.periodStart)}">
                        </label>
                    </div>
                </div>

                <h3 class="books-subtitle">Enter hours</h3>
                ${
                    state.employees.length
                        ? `
                <div class="books-lines payroll-lines payroll-lines--runs">
                    <div class="books-lines-head payroll-lines-head payroll-lines-head--runs">
                        <span>Employee</span>
                        <span>Hours</span>
                        <span>Rate</span>
                        <span>Net pay</span>
                    </div>
                    ${state.employees.map(renderEmployeeRow).join("")}
                </div>`
                        : '<p class="data-list-empty">No staff assigned to this facility.</p>'
                }

                <p class="books-total-line payroll-total">
                    Period total: <strong>${totals.count ? totals.hours.toFixed(2) : "0"}</strong> hrs ·
                    <strong>${money(totals.pay)}</strong> net
                </p>

                <label class="books-label">Note (optional)
                    <input type="text" id="payroll-note" class="books-input" placeholder="Check #, memo, etc." value="${escapeHtml(state.note)}">
                </label>

                <div class="payroll-actions">
                    <button type="button" class="btn books-save" id="payroll-save"${!hasAnyHours() ? " disabled" : ""}>Save payroll</button>
                    <span class="books-status">${escapeHtml(state.status)}</span>
                </div>

                ${renderRunHistory()}
            </div>`;
    }

    function updateRowPayCells(root) {
        root.querySelectorAll("[data-payroll-employee]").forEach((rowEl) => {
            const employeeId = rowEl.dataset.payrollEmployee;
            const emp = state.employees.find((e) => e.id === employeeId);
            const hours = rowEl.querySelector('[name="hours"]')?.value;
            const rate = B().num(emp?.hourlyRate);
            const cell = rowEl.querySelector("[data-payroll-pay]");
            if (cell) cell.textContent = money(M().calcPay(B().num(hours), rate));
        });
        const saveBtn = root.querySelector("#payroll-save");
        if (saveBtn) {
            syncHoursFromDom(root);
            saveBtn.disabled = !hasAnyHours();
        }
    }

    function bind(rootId) {
        const root = document.getElementById(rootId || "payroll-root");
        if (!root || root.dataset.payrollBound) return;
        root.dataset.payrollBound = "1";

        root.addEventListener("change", async (e) => {
            if (!e.target.closest("[data-payroll-panel]")) return;
            if (e.target.id === "payroll-location") {
                state.locationId = e.target.value;
                await loadAll();
            }
            if (e.target.id === "payroll-period-start") {
                state.periodStart = e.target.value;
                const end = root.querySelector("#payroll-period-end");
                if (end) end.min = state.periodStart;
                if (state.periodEnd < state.periodStart) {
                    state.periodEnd = state.periodStart;
                    if (end) end.value = state.periodEnd;
                }
            }
            if (e.target.id === "payroll-period-end") {
                state.periodEnd = e.target.value;
            }
        });

        root.addEventListener("input", (e) => {
            if (!e.target.closest("[data-payroll-panel]")) return;
            if (e.target.matches('[name="hours"]')) {
                updateRowPayCells(root);
            }
            if (e.target.id === "payroll-note") {
                state.note = e.target.value;
            }
        });

        root.addEventListener(
            "blur",
            (e) => {
                if (!e.target.classList.contains("books-input-amount")) return;
                if (!e.target.closest("[data-payroll-panel]")) return;
                const raw = String(e.target.value ?? "").trim();
                if (raw === "") return;
                const n = B().parseAmountExpression(raw);
                if (Number.isFinite(n)) e.target.value = B().formatAmountForInput(n);
                updateRowPayCells(root);
            },
            true
        );

        root.addEventListener("click", async (e) => {
            if (e.target.id === "payroll-reload") {
                await loadAll();
                return;
            }
            if (e.target.id === "payroll-save" || e.target.closest("#payroll-save")) {
                await saveRun(root);
                return;
            }
            const toggle = e.target.closest("[data-payroll-run-toggle]");
            if (toggle) {
                const runId = toggle.dataset.payrollRunToggle;
                state.expandedRunId = state.expandedRunId === runId ? null : runId;
                renderPanel(rootId);
            }
        });
    }

    async function init(uid, locs, options) {
        userId = uid;
        locations = locs || [];
        state.embeddedLocationId = options?.embeddedLocationId || null;
        if (locations.length && !state.locationId) state.locationId = locations[0].id;
        if (state.embeddedLocationId) state.locationId = state.embeddedLocationId;

        currentRootId = options?.rootId || "payroll-root";
        const root = document.getElementById(currentRootId);
        if (root) {
            root.dataset.payrollBound = "";
            bind(currentRootId);
        }
        if (!locations.length) {
            render();
            return;
        }
        await loadAll();
    }

    function renderEmbedded(ctx) {
        return `
            <h2 class="loc-section-heading">Payroll</h2>
            <p class="books-hint dir-hint">Pay-period runs for <strong>${escapeHtml(ctx.locationName || "this facility")}</strong> — shared with the iOS app.</p>
            <div id="payroll-embedded-root"></div>`;
    }

    function bindEmbedded(container, ctx) {
        const slot = container.querySelector("#payroll-embedded-root");
        if (!slot) return;
        slot.dataset.payrollBound = "";
        slot.innerHTML = "";
        init(ctx.userId, ctx.locations || locations, {
            rootId: "payroll-embedded-root",
            embeddedLocationId: ctx.locationId,
        });
    }

    window.OplixPayrollUI = {
        init,
        async onShow() {
            if (!userId) return;
            if (effectiveLocationId()) await loadAll();
            else render();
        },
        renderEmbedded,
        bindEmbedded,
    };
})();
