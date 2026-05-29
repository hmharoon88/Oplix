/**
 * Data input — monthly books (daily sheet, utilities, payroll, receivables).
 */
(function () {
    const M = () => window.OplixBooksModel;
    const Store = () => window.OplixBooksStore;
    const DirStore = () => window.OplixLocationDirectoryStore;
    const DirModel = () => window.OplixLocationDirectoryModel;

    let userId = null;
    let locations = [];
    let state = {
        locationId: "",
        monthId: M().monthIdFromDate(new Date()),
        dayId: M().dayIdFromDate(new Date()),
        tab: "daily",
        month: M().defaultMonthDoc(),
        day: M().defaultDayDoc(),
        daysById: {},
        utilityProviders: [],
        dirty: false,
    };

    function mergedUtilityKeys() {
        return M().mergeUtilityKeys(state.utilityProviders, state.month.utilities);
    }

    async function loadUtilityProviders() {
        if (!state.locationId || !DirStore()) {
            state.utilityProviders = [];
            return;
        }
        await DirStore().ensureDefaultUtilityProviders(userId, state.locationId);
        const list = await DirStore().list(
            userId,
            state.locationId,
            DirModel().COLLECTIONS.utilityProviders
        );
        state.utilityProviders = DirModel().sortUtilityProviders(list);
    }

    function $(id) {
        return document.getElementById(id);
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

    function lineId() {
        return "ln_" + Date.now() + "_" + Math.random().toString(36).slice(2, 7);
    }

    function currentLocation() {
        return locations.find((l) => l.id === state.locationId);
    }

    function effectiveFacilityType(loc) {
        const t = loc?.facilityType;
        return t === "c_store_gas" ? "c_store_gas" : "c_store";
    }

    function hasGasStation(loc) {
        return effectiveFacilityType(loc || currentLocation()) === "c_store_gas";
    }

    function bindShell() {
        const panel = $("panel-data-input");
        if (!panel || panel.dataset.diBound) return;
        panel.dataset.diBound = "1";

        panel.addEventListener("change", async (e) => {
            if (e.target.id === "di-location") {
                state.locationId = e.target.value;
                await loadCurrent();
                return;
            }
            if (e.target.id === "di-month") state.monthId = e.target.value;
            if (e.target.id === "di-day") {
                state.dayId = e.target.value;
                state.day = M().normalizeDayDoc(state.daysById[state.dayId]);
                render();
            }
        });

        panel.addEventListener("click", (e) => {
            const tab = e.target.closest("[data-di-tab]");
            if (tab) {
                state.tab = tab.dataset.diTab;
                render();
                return;
            }
            if (e.target.id === "di-reload") {
                loadCurrent();
                return;
            }
            if (e.target.id === "di-save-month") {
                saveMonth();
                return;
            }
            if (e.target.id === "di-save-day") {
                saveDay();
                return;
            }
            const add = e.target.closest("[data-di-add]");
            if (add) {
                addLine(add.dataset.diAdd);
                render();
                return;
            }
            const rm = e.target.closest("[data-di-rm]");
            if (rm) {
                removeLine(rm.dataset.diList, rm.dataset.diRm);
                render();
            }
        });

        panel.addEventListener("input", (e) => {
            if (!e.target.closest(".data-input-form")) return;
            syncFromForm();
            state.dirty = true;
        });
    }

    function addLine(list) {
        if (list === "cashExpenses") {
            state.day.cashExpenses.push({ id: lineId(), description: "", amount: 0, overShort: 0 });
        } else if (list === "checksAch") {
            state.day.checksAch.push({
                id: lineId(),
                date: state.dayId,
                description: "",
                checkNo: "",
                amount: 0,
            });
        } else if (list === "otherExpenses") {
            state.day.otherExpenses.push({ id: lineId(), description: "", amount: 0 });
        } else if (list === "receivables") {
            state.month.receivables.push({ id: lineId(), description: "", amount: 0 });
        }
    }

    function removeLine(list, id) {
        if (list === "receivables") {
            state.month.receivables = state.month.receivables.filter((r) => r.id !== id);
        } else {
            state.day[list] = (state.day[list] || []).filter((r) => r.id !== id);
        }
    }

    function syncFromForm() {
        const root = $("data-input-root");
        if (!root) return;

        mergedUtilityKeys().forEach((u) => {
            const el = root.querySelector(`[name="util_${u.key}"]`);
            if (el) state.month.utilities[u.key] = M().num(el.value);
        });

        ["week1", "week2", "week3", "week4"].forEach((w) => {
            const el = root.querySelector(`[name="payroll_${w}"]`);
            if (el) state.month.payroll[w] = M().num(el.value);
        });

        const tax = root.querySelector('[name="salesTax"]');
        const acct = root.querySelector('[name="accountant"]');
        if (tax) state.month.salesTax = M().num(tax.value);
        if (acct) state.month.accountant = M().num(acct.value);

        const registerFields = ["cardSale", "cashSale", "overShort"];
        ["register1", "register2"].forEach((regKey) => {
            if (!state.day[regKey]) state.day[regKey] = M().defaultRegisterUnit();
            ["shift1", "shift2"].forEach((sh) => {
                registerFields.forEach((f) => {
                    const el = root.querySelector(`[name="reg_${regKey}_${sh}_${f}"]`);
                    if (el) state.day[regKey][sh][f] = M().num(el.value);
                });
            });
        });

        ["cash", "winner", "overShort"].forEach((f) => {
            const el = root.querySelector(`[name="pull_${f}"]`);
            if (el) state.day.pulltab[f] = M().num(el.value);
        });

        if (!state.day.fuelSale) state.day.fuelSale = M().defaultFuelSale();
        if (hasGasStation()) {
            const fuelG = root.querySelector('[name="fuel_gallons"]');
            const fuelD = root.querySelector('[name="fuel_dollars"]');
            const merch = root.querySelector('[name="merch_sale"]');
            const credit = root.querySelector('[name="credit_card"]');
            if (fuelG) state.day.fuelSale.gallons = M().num(fuelG.value);
            if (fuelD) state.day.fuelSale.dollars = M().num(fuelD.value);
            if (merch) state.day.merchSale = M().num(merch.value);
            if (credit) state.day.creditCard = M().num(credit.value);
        } else {
            state.day.fuelSale = M().defaultFuelSale();
            state.day.merchSale = 0;
            state.day.creditCard = 0;
        }

        syncLinesFromDom("cashExpenses", ["description", "amount", "overShort"]);
        syncLinesFromDom("checksAch", ["date", "description", "checkNo", "amount"]);
        syncLinesFromDom("otherExpenses", ["description", "amount"]);
        syncLinesFromDom("receivables", ["description", "amount"], true);
    }

    function syncLinesFromDom(listKey, fields, isMonth) {
        const root = $("data-input-root");
        const target = isMonth ? state.month[listKey] : state.day[listKey];
        const rows = root.querySelectorAll(`[data-di-list="${listKey}"] [data-di-row]`);
        const updated = [];
        rows.forEach((row) => {
            const id = row.dataset.diRow;
            const existing = target.find((r) => r.id === id) || { id };
            const obj = { ...existing, id };
            fields.forEach((f) => {
                const inp = row.querySelector(`[name="${f}"]`);
                if (inp) obj[f] = f === "amount" || f === "overShort" ? M().num(inp.value) : inp.value;
            });
            updated.push(obj);
        });
        if (isMonth) state.month[listKey] = updated;
        else state.day[listKey] = updated;
    }

    async function loadCurrent() {
        if (!state.locationId) return;
        $("di-status").textContent = "Loading…";
        const { month, daysById } = await Store().loadMonth(userId, state.locationId, state.monthId);
        await loadUtilityProviders();
        state.month = month;
        state.month.utilities = M().normalizeMonthUtilities(
            state.month.utilities,
            M().mergeUtilityKeys(state.utilityProviders, state.month.utilities)
        );
        state.daysById = daysById;
        state.day = M().normalizeDayDoc(daysById[state.dayId]);
        state.dirty = false;
        $("di-status").textContent = "";
        render();
    }

    async function saveMonth() {
        syncFromForm();
        $("di-status").textContent = "Saving…";
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        state.dirty = false;
        $("di-status").textContent = "Month saved.";
        setTimeout(() => {
            if ($("di-status").textContent === "Month saved.") $("di-status").textContent = "";
        }, 2000);
    }

    async function saveDay() {
        syncFromForm();
        $("di-status").textContent = "Saving…";
        await Promise.all([
            Store().saveDay(userId, state.locationId, state.monthId, state.dayId, state.day),
            Store().saveMonth(userId, state.locationId, state.monthId, state.month),
        ]);
        state.daysById[state.dayId] = { ...state.day, _dayId: state.dayId };
        state.dirty = false;
        $("di-status").textContent = "Day saved.";
        setTimeout(() => {
            if ($("di-status").textContent === "Day saved.") $("di-status").textContent = "";
        }, 2000);
    }

    function monthOptions() {
        const opts = [];
        const now = new Date();
        for (let i = 0; i < 18; i++) {
            const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const id = M().monthIdFromDate(d);
            const label = d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
            opts.push(`<option value="${id}"${id === state.monthId ? " selected" : ""}>${label}</option>`);
        }
        return opts.join("");
    }

    function dayOptions() {
        const n = M().daysInMonth(state.monthId);
        const [y, m] = state.monthId.split("-").map(Number);
        const opts = [];
        for (let d = 1; d <= n; d++) {
            const date = new Date(y, m - 1, d);
            const id = M().dayIdFromDate(date);
            const has = !!state.daysById[id];
            const label = date.toLocaleDateString("en-US", {
                weekday: "short",
                month: "short",
                day: "numeric",
            });
            opts.push(
                `<option value="${id}"${id === state.dayId ? " selected" : ""}>${has ? "● " : ""}${label}</option>`
            );
        }
        return opts.join("");
    }

    const REGISTER_SHIFT_FIELDS = [
        { name: "cardSale", label: "Card sale" },
        { name: "cashSale", label: "Cash sale" },
        { name: "overShort", label: "Over / short" },
    ];

    function renderRegisterUnit(title, regKey, unit) {
        const total = M().registerBlockTotal(unit);
        return `
            <h3 class="books-subtitle">${escapeHtml(title)}</h3>
            ${renderShiftBlock("Shift 1", `reg_${regKey}_shift1`, unit.shift1, REGISTER_SHIFT_FIELDS)}
            ${renderShiftBlock("Shift 2", `reg_${regKey}_shift2`, unit.shift2, REGISTER_SHIFT_FIELDS)}
            <p class="books-total-line">${escapeHtml(title)} total: ${money(total.card + total.cash)} card+cash · O/S ${money(total.overShort)}</p>`;
    }

    function renderShiftBlock(title, prefix, data, fields) {
        return `
            <fieldset class="books-fieldset">
                <legend>${escapeHtml(title)}</legend>
                <div class="books-grid-3">
                    ${fields
                        .map(
                            (f) => `
                    <label class="books-label">${escapeHtml(f.label)}
                        <input type="number" step="0.01" class="books-input" name="${prefix}_${f.name}" value="${M().num(data[f.name]) || ""}">
                    </label>`
                        )
                        .join("")}
                </div>
            </fieldset>`;
    }

    function renderLineList(listKey, columns, rows, isMonth) {
        const list = isMonth ? state.month[listKey] : state.day[listKey];
        return `
            <div class="books-lines" data-di-list="${listKey}">
                <div class="books-lines-head">
                    ${columns.map((c) => `<span>${escapeHtml(c.label)}</span>`).join("")}
                    <span></span>
                </div>
                ${(list || [])
                    .map((row) => {
                        const cells = columns
                            .map((c) => {
                                const type = c.type || "text";
                                const val = row[c.name] ?? "";
                                return `<input type="${type}" step="${type === "number" ? "0.01" : ""}" class="books-input" name="${c.name}" value="${escapeHtml(val)}">`;
                            })
                            .join("");
                        return `
                    <div class="books-lines-row" data-di-row="${escapeHtml(row.id)}">
                        ${cells}
                        <button type="button" class="books-rm" data-di-rm="${escapeHtml(row.id)}" data-di-list="${listKey}">×</button>
                    </div>`;
                    })
                    .join("")}
                <button type="button" class="books-add-line" data-di-add="${listKey}">+ Add line</button>
            </div>`;
    }

    function renderUtilitiesPayroll() {
        const utilityKeys = mergedUtilityKeys();
        const utilFields = utilityKeys
            .map(
                (u) => `
            <label class="books-label">${escapeHtml(u.label)}
                <input type="number" step="0.01" class="books-input" name="util_${u.key}" value="${M().num(state.month.utilities[u.key]) || ""}">
            </label>`
            )
            .join("");

        const payrollFields = ["week1", "week2", "week3", "week4"]
            .map(
                (w, i) => `
            <label class="books-label">Week ${i + 1}
                <input type="number" step="0.01" class="books-input" name="payroll_${w}" value="${M().num(state.month.payroll[w]) || ""}">
            </label>`
            )
            .join("");

        const utilTotal = utilityKeys.reduce(
            (s, u) => s + M().num(state.month.utilities[u.key]),
            0
        );
        const payTotal =
            M().num(state.month.payroll.week1) +
            M().num(state.month.payroll.week2) +
            M().num(state.month.payroll.week3) +
            M().num(state.month.payroll.week4);

        return `
            <div class="books-panel data-input-form">
                <h3 class="books-subtitle">Utilities</h3>
                <p class="books-hint">Monthly amounts — same types as <strong>Facilities → Utilities</strong>. Add custom types under the facility first; they appear here automatically.</p>
                <div class="books-grid-util">${utilFields}</div>
                <p class="books-total-line">Utilities total: <strong>${money(utilTotal)}</strong></p>

                <h3 class="books-subtitle">Payroll</h3>
                <div class="books-grid-4">${payrollFields}</div>
                <p class="books-total-line">Payroll total: <strong>${money(payTotal)}</strong></p>

                <h3 class="books-subtitle">Other monthly</h3>
                <div class="books-grid-2">
                    <label class="books-label">Sales tax
                        <input type="number" step="0.01" class="books-input" name="salesTax" value="${M().num(state.month.salesTax) || ""}">
                    </label>
                    <label class="books-label">Accountant
                        <input type="number" step="0.01" class="books-input" name="accountant" value="${M().num(state.month.accountant) || ""}">
                    </label>
                </div>
                <button type="button" class="btn books-save" id="di-save-month">Save month (utilities & payroll)</button>
            </div>`;
    }

    function renderDaily() {
        const reg = M().registerDayTotal(state.day);
        const gas = hasGasStation();
        const fuel = M().fuelDayTotal(state.day);
        const totals = `
            <p class="books-total-line">All registers (1 + 2): ${money(reg.card + reg.cash)} card+cash · O/S ${money(reg.overShort)}</p>`;

        const fuelSection = gas
            ? `
                <h3 class="books-subtitle">Gas station sales</h3>
                <div class="books-grid-2">
                    <label class="books-label">Gallons sold
                        <input type="number" step="0.01" min="0" class="books-input" name="fuel_gallons" value="${M().num(fuel.gallons) || ""}">
                    </label>
                    <label class="books-label">Amount ($)
                        <input type="number" step="0.01" min="0" class="books-input" name="fuel_dollars" value="${M().num(fuel.dollars) || ""}">
                    </label>
                    <label class="books-label">Merch sale
                        <input type="number" step="0.01" min="0" class="books-input" name="merch_sale" value="${M().num(state.day.merchSale) || ""}">
                    </label>
                    <label class="books-label">Credit card
                        <input type="number" step="0.01" min="0" class="books-input" name="credit_card" value="${M().num(state.day.creditCard) || ""}">
                    </label>
                </div>`
            : "";

        return `
            <div class="books-panel data-input-form">
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>

                ${renderRegisterUnit("Register 1", "register1", state.day.register1)}
                ${renderRegisterUnit("Register 2", "register2", state.day.register2)}
                ${totals}
                ${fuelSection}

                <h3 class="books-subtitle">Pulltab</h3>
                ${renderShiftBlock("Pulltab", "pull", state.day.pulltab, [
                    { name: "cash", label: "Cash" },
                    { name: "winner", label: "Winners" },
                    { name: "overShort", label: "Over / short" },
                ])}

                <h3 class="books-subtitle">Cash expense</h3>
                ${renderLineList("cashExpenses", [
                    { name: "description", label: "Description" },
                    { name: "amount", label: "Amount", type: "number" },
                    { name: "overShort", label: "O/S", type: "number" },
                ])}

                <h3 class="books-subtitle">Checks / ACH</h3>
                ${renderLineList("checksAch", [
                    { name: "date", label: "Date" },
                    { name: "description", label: "Description" },
                    { name: "checkNo", label: "Check #" },
                    { name: "amount", label: "Amount", type: "number" },
                ])}

                <h3 class="books-subtitle">Other expense</h3>
                ${renderLineList("otherExpenses", [
                    { name: "description", label: "Description" },
                    { name: "amount", label: "Amount", type: "number" },
                ])}

                <button type="button" class="btn books-save" id="di-save-day">Save this day</button>
            </div>`;
    }

    function renderReceivables() {
        return `
            <div class="books-panel data-input-form">
                <h3 class="books-subtitle">Receivables / checks received</h3>
                <p class="books-hint">Credits and deposits (Uber, DoorDash, ATM, vendor rebates, etc.)</p>
                ${renderLineList(
                    "receivables",
                    [
                        { name: "description", label: "Description" },
                        { name: "amount", label: "Amount", type: "number" },
                    ],
                    null,
                    true
                )}
                <button type="button" class="btn books-save" id="di-save-month">Save receivables</button>
            </div>`;
    }

    function render() {
        const root = $("data-input-root");
        if (!root) return;

        if (!locations.length) {
            root.innerHTML = '<p class="data-list-empty">Add a facility first (Facilities tab or iOS app).</p>';
            return;
        }

        const tabs = [
            { id: "daily", label: "Daily sheet" },
            { id: "utilities", label: "Utilities & payroll" },
            { id: "receivables", label: "Receivables" },
        ];

        let body = "";
        if (state.tab === "daily") body = renderDaily();
        else if (state.tab === "utilities") body = renderUtilitiesPayroll();
        else body = renderReceivables();

        root.innerHTML = `
            <div class="books-toolbar">
                <label class="books-label">Facility
                    <select id="di-location" class="books-select">
                        ${locations.map((l) => `<option value="${l.id}"${l.id === state.locationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`).join("")}
                    </select>
                </label>
                <label class="books-label">Month
                    <select id="di-month" class="books-select">${monthOptions()}</select>
                </label>
                <button type="button" class="btn btn-nav-outline" id="di-reload">Load</button>
                <span class="books-status" id="di-status"></span>
            </div>
            <nav class="books-tabs">
                ${tabs.map((t) => `<button type="button" class="books-tab${state.tab === t.id ? " active" : ""}" data-di-tab="${t.id}">${t.label}</button>`).join("")}
            </nav>
            ${body}`;
    }

    window.OplixDataInput = {
        init(uid, locs) {
            userId = uid;
            locations = locs || [];
            if (locations.length && !state.locationId) state.locationId = locations[0].id;
            const root = $("data-input-root");
            bindShell();
            if (!root) return;
            render();
            if (state.locationId) loadCurrent();
        },
        onShow() {
            if (userId && state.locationId) loadCurrent();
        },
    };
})();
