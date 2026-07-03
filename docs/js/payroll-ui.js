/**
 * Web Payroll — manual hours, rate, and calculated pay (daily / weekly / monthly).
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
        periodMode: "weekly",
        dayId: B().dayIdFromDate(new Date()),
        monthId: B().monthIdFromDate(new Date()),
        weekDate: new Date().toISOString().slice(0, 10),
        entries: [],
        employees: [],
        rows: [],
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

    function periodKey() {
        return M().periodKeyForMode(state.periodMode, state, B());
    }

    function periodTitle() {
        return M().periodLabel(state.periodMode, periodKey(), B());
    }

    function newRowId() {
        return "pr_" + Date.now() + "_" + Math.random().toString(36).slice(2, 6);
    }

    function blankRow() {
        return {
            rowId: newRowId(),
            id: "",
            employeeId: "",
            employeeName: "",
            hours: "",
            hourlyRate: "",
            notes: "",
        };
    }

    function rowsFromEntries(entries) {
        const list = entries.map((e) => ({
            rowId: e.id || newRowId(),
            id: e.id || "",
            employeeId: e.employeeId || "",
            employeeName: e.employeeName || "",
            hours: B().formatAmountForInput(e.hours),
            hourlyRate: B().formatAmountForInput(e.hourlyRate),
            notes: e.notes || "",
        }));
        return list.length ? list : [blankRow()];
    }

    function rowPay(hours, rate) {
        return M().calcPay(B().num(hours), B().num(rate));
    }

    async function loadEmployees() {
        const locId = effectiveLocationId();
        if (!locId || !userId) {
            state.employees = [];
            return;
        }
        state.employees = await Store().listEmployees(userId, locId);
    }

    function render() {
        renderPanel(currentRootId);
    }

    async function loadEntries() {
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
            state.entries = await Store().list(userId, locId);
            const filtered = M().filterEntries(state.entries, state.periodMode, periodKey());
            state.rows = rowsFromEntries(filtered);
            state.status = "";
        } catch (err) {
            state.status = err.message || "Failed to load payroll.";
        } finally {
            state.loading = false;
            render();
        }
    }

    function syncRowsFromDom(root) {
        const panel = root.querySelector("[data-payroll-panel]");
        if (!panel) return;
        const updated = [];
        panel.querySelectorAll("[data-payroll-row]").forEach((rowEl) => {
            const rowId = rowEl.dataset.payrollRow;
            const existing = state.rows.find((r) => r.rowId === rowId) || { rowId };
            const empSel = rowEl.querySelector('[name="employeeId"]');
            const empId = empSel?.value || "";
            const emp = state.employees.find((e) => e.id === empId);
            updated.push({
                ...existing,
                rowId,
                id: rowEl.dataset.payrollId || existing.id || "",
                employeeId: empId,
                employeeName:
                    emp?.name || emp?.username || rowEl.querySelector('[name="employeeName"]')?.value || "",
                hours: rowEl.querySelector('[name="hours"]')?.value ?? "",
                hourlyRate: rowEl.querySelector('[name="hourlyRate"]')?.value ?? "",
                notes: rowEl.querySelector('[name="notes"]')?.value ?? "",
            });
        });
        state.rows = updated.length ? updated : [blankRow()];
    }

    function normalizeAmountFields(root) {
        root.querySelectorAll(".books-input-amount").forEach((el) => {
            const raw = String(el.value ?? "").trim();
            if (raw === "") return;
            const n = B().parseAmountExpression(raw);
            if (Number.isFinite(n)) el.value = B().formatAmountForInput(n);
        });
    }

    async function saveAll(root) {
        normalizeAmountFields(root);
        syncRowsFromDom(root);
        const locId = effectiveLocationId();
        if (!locId) return;

        state.status = "Saving…";
        render();

        const key = periodKey();
        const existingForPeriod = M().filterEntries(state.entries, state.periodMode, key);
        const keptIds = new Set();

        try {
            for (const row of state.rows) {
                const hours = B().num(row.hours);
                const rate = B().num(row.hourlyRate);
                const name = String(row.employeeName || "").trim();
                if (!name && !row.employeeId) continue;
                if (hours <= 0 && rate <= 0) continue;

                const payload = M().normalizeEntry(
                    {
                        id: row.id || undefined,
                        periodType: state.periodMode,
                        periodKey: key,
                        employeeId: row.employeeId,
                        employeeName: name || "Employee",
                        hours,
                        hourlyRate: rate,
                        notes: row.notes,
                        active: true,
                    },
                    locId
                );

                const id = await Store().save(userId, locId, payload);
                keptIds.add(id);
            }

            for (const old of existingForPeriod) {
                if (old.id && !keptIds.has(old.id)) {
                    await Store().remove(userId, locId, old.id);
                }
            }

            state.entries = await Store().list(userId, locId);
            const booksMonth = M().entryMonthId(
                { periodType: state.periodMode, periodKey: key },
                B()
            );
            const syncResults = await Store().syncAllBooksMonths(userId, locId, [booksMonth]);
            const synced = syncResults.find((r) => r.month) || syncResults[0];
            const monthLabelStr = booksMonth
                ? B().parseMonthId(booksMonth).toLocaleDateString("en-US", {
                      month: "long",
                      year: "numeric",
                  })
                : "";

            state.status = synced
                ? `Saved and synced to Daily books${monthLabelStr ? ` (${monthLabelStr})` : ""}.`
                : "Saved.";
            await loadEntries();
            if (window.OplixDataInput?.refreshIfOpen && booksMonth) {
                OplixDataInput.refreshIfOpen(locId, booksMonth);
            }
            setTimeout(() => {
                if (state.status.includes("Saved")) state.status = "";
                render();
            }, 3500);
        } catch (err) {
            state.status = err.message || "Save failed.";
            render();
        }
    }

    function employeeOptions(selectedId) {
        const opts = [`<option value="">Custom name</option>`];
        state.employees.forEach((e) => {
            const name = e.name || e.username || "Employee";
            opts.push(
                `<option value="${escapeHtml(e.id)}"${e.id === selectedId ? " selected" : ""}>${escapeHtml(name)}</option>`
            );
        });
        return opts.join("");
    }

    function renderRow(row) {
        const pay = rowPay(row.hours, row.hourlyRate);
        const showCustomName = !row.employeeId;
        return `
            <div class="books-lines-row payroll-lines-row" data-payroll-row="${escapeHtml(row.rowId)}" data-payroll-id="${escapeHtml(row.id)}">
                <select class="books-select" name="employeeId">${employeeOptions(row.employeeId)}</select>
                <input type="text" class="books-input${showCustomName ? "" : " payroll-name-readonly"}" name="employeeName" placeholder="Name" value="${escapeHtml(row.employeeName)}"${showCustomName ? "" : " readonly"}>
                <input type="text" inputmode="decimal" autocomplete="off" class="books-input books-input-amount" name="hours" placeholder="0" value="${escapeHtml(row.hours)}">
                <input type="text" inputmode="decimal" autocomplete="off" class="books-input books-input-amount" name="hourlyRate" placeholder="0.00" value="${escapeHtml(row.hourlyRate)}">
                <span class="payroll-pay-cell" data-payroll-pay>${money(pay)}</span>
                <input type="text" class="books-input" name="notes" placeholder="Notes" value="${escapeHtml(row.notes)}">
                <button type="button" class="books-rm" data-payroll-rm title="Remove row">×</button>
            </div>`;
    }

    function renderPeriodFields() {
        if (state.periodMode === "daily") {
            return `<label class="books-label">Day
                <input type="date" id="payroll-day" class="books-input" value="${escapeHtml(state.dayId)}">
            </label>`;
        }
        if (state.periodMode === "monthly") {
            return `<label class="books-label">Month
                <select id="payroll-month" class="books-select">${monthOptions(state.monthId)}</select>
            </label>`;
        }
        return `<label class="books-label payroll-week-field">Week (pick any day in the week)
            <input type="date" id="payroll-week" class="books-input" value="${escapeHtml(state.weekDate)}">
            <span class="books-hint payroll-week-hint">${escapeHtml(M().weekRangeLabel(periodKey()))}</span>
        </label>`;
    }

    function monthOptions(selected) {
        const opts = [];
        const now = new Date();
        for (let i = 0; i < 18; i++) {
            const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const id = B().monthIdFromDate(d);
            const label = d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
            opts.push(`<option value="${id}"${id === selected ? " selected" : ""}>${label}</option>`);
        }
        return opts.join("");
    }

    function renderPanel(rootId) {
        const root = document.getElementById(rootId || "payroll-root");
        if (!root) return;

        if (!locations.length) {
            root.innerHTML =
                '<p class="data-list-empty">Add a facility first, then enter payroll hours here.</p>';
            return;
        }

        const filtered = M().filterEntries(state.entries, state.periodMode, periodKey());
        const totals = M().totals(
            state.rows.map((r) => ({
                hours: B().num(r.hours),
                pay: rowPay(r.hours, r.hourlyRate),
            }))
        );

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
                        <label class="books-label">Period
                            <select id="payroll-mode" class="books-select">
                                ${M()
                                    .PERIOD_MODES.map(
                                        (p) =>
                                            `<option value="${p.id}"${p.id === state.periodMode ? " selected" : ""}>${escapeHtml(p.label)}</option>`
                                    )
                                    .join("")}
                            </select>
                        </label>
                        ${renderPeriodFields()}
                    </div>
                    <button type="button" class="btn btn-nav-outline" id="payroll-reload"${state.loading ? " disabled" : ""}>Load</button>
                </div>

                <p class="books-hint">Enter <strong>hours</strong> and <strong>hourly rate</strong> — pay is calculated automatically and synced to <strong>Daily books</strong> for that month when you save.</p>
                <p class="payroll-period-title">${escapeHtml(periodTitle())}</p>

                <div class="books-lines payroll-lines">
                    <div class="books-lines-head payroll-lines-head">
                        <span>Employee</span>
                        <span>Name</span>
                        <span>Hours</span>
                        <span>Rate ($/hr)</span>
                        <span>Pay</span>
                        <span>Notes</span>
                        <span></span>
                    </div>
                    ${state.rows.map(renderRow).join("")}
                    <button type="button" class="books-add-line" id="payroll-add-row">+ Add employee</button>
                </div>

                <p class="books-total-line payroll-total">
                    Period total: <strong>${totals.count ? totals.hours.toFixed(2) : "0"}</strong> hrs ·
                    <strong>${money(totals.pay)}</strong>
                    ${filtered.length !== state.rows.filter((r) => r.employeeName || r.employeeId).length ? `<span class="books-hint"> (${filtered.length} saved)</span>` : ""}
                </p>

                <div class="payroll-actions">
                    <button type="button" class="btn books-save" id="payroll-save">Save payroll</button>
                    <span class="books-status">${escapeHtml(state.status)}</span>
                </div>
            </div>`;
    }

    function updateRowPayCells(root) {
        root.querySelectorAll("[data-payroll-row]").forEach((rowEl) => {
            const hours = rowEl.querySelector('[name="hours"]')?.value;
            const rate = rowEl.querySelector('[name="hourlyRate"]')?.value;
            const cell = rowEl.querySelector("[data-payroll-pay]");
            if (cell) cell.textContent = money(rowPay(hours, rate));
        });
    }

    function bind(rootId) {
        const root = document.getElementById(rootId || "payroll-root");
        if (!root || root.dataset.payrollBound) return;
        root.dataset.payrollBound = "1";

        root.addEventListener("change", async (e) => {
            if (!e.target.closest("[data-payroll-panel]")) return;
            if (e.target.id === "payroll-location") {
                state.locationId = e.target.value;
                await loadEmployees();
                await loadEntries();
                return;
            }
            if (e.target.id === "payroll-mode") {
                state.periodMode = e.target.value;
                await loadEntries();
                return;
            }
            if (e.target.id === "payroll-day") state.dayId = e.target.value;
            if (e.target.id === "payroll-month") state.monthId = e.target.value;
            if (e.target.id === "payroll-week") state.weekDate = e.target.value;
            if (e.target.name === "employeeId") {
                syncRowsFromDom(root);
                const rowEl = e.target.closest("[data-payroll-row]");
                const emp = state.employees.find((x) => x.id === e.target.value);
                if (emp && rowEl) {
                    const rateInput = rowEl.querySelector('[name="hourlyRate"]');
                    const nameInput = rowEl.querySelector('[name="employeeName"]');
                    if (nameInput) {
                        nameInput.value = emp.name || emp.username || "";
                        nameInput.readOnly = true;
                        nameInput.classList.add("payroll-name-readonly");
                    }
                    if (rateInput && emp.hourlyRate != null && !String(rateInput.value).trim()) {
                        rateInput.value = B().formatAmountForInput(emp.hourlyRate);
                    }
                } else if (rowEl) {
                    const nameInput = rowEl.querySelector('[name="employeeName"]');
                    if (nameInput) {
                        nameInput.readOnly = false;
                        nameInput.classList.remove("payroll-name-readonly");
                    }
                }
                updateRowPayCells(root);
                return;
            }
            if (["payroll-day", "payroll-month", "payroll-week"].includes(e.target.id)) {
                readPeriodFromDom(root);
                loadEntries();
                return;
            }
        });

        root.addEventListener("input", (e) => {
            if (!e.target.closest("[data-payroll-panel]")) return;
            if (e.target.matches('[name="hours"], [name="hourlyRate"]')) {
                updateRowPayCells(root);
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
                readPeriodFromDom(root);
                await loadEntries();
                return;
            }
            if (e.target.id === "payroll-save") {
                readPeriodFromDom(root);
                await saveAll(root);
                return;
            }
            if (e.target.id === "payroll-add-row") {
                syncRowsFromDom(root);
                state.rows.push(blankRow());
                renderPanel(rootId);
                return;
            }
            if (e.target.closest("[data-payroll-rm]")) {
                syncRowsFromDom(root);
                const rowEl = e.target.closest("[data-payroll-row]");
                const rowId = rowEl?.dataset.payrollRow;
                state.rows = state.rows.filter((r) => r.rowId !== rowId);
                if (!state.rows.length) state.rows = [blankRow()];
                renderPanel(rootId);
            }
        });
    }

    function readPeriodFromDom(root) {
        const day = root.querySelector("#payroll-day");
        if (day) state.dayId = day.value;
        const month = root.querySelector("#payroll-month");
        if (month) state.monthId = month.value;
        const week = root.querySelector("#payroll-week");
        if (week) state.weekDate = week.value;
        const loc = root.querySelector("#payroll-location");
        if (loc) state.locationId = loc.value;
        const mode = root.querySelector("#payroll-mode");
        if (mode) state.periodMode = mode.value;
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
        await loadEmployees();
        await loadEntries();
    }

    function renderEmbedded(ctx) {
        return `
            <h2 class="loc-section-heading">Payroll</h2>
            <p class="books-hint dir-hint">Manual hours and pay for <strong>${escapeHtml(ctx.locationName || "this facility")}</strong>.</p>
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
            if (effectiveLocationId()) await loadEntries();
            else render();
        },
        renderEmbedded,
        bindEmbedded,
    };
})();
