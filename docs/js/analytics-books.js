/**
 * Books summary — cross-period and cross-facility comparison from Data input books.
 */
(function () {
    const M = () => window.OplixBooksModel;
    const Store = () => window.OplixBooksStore;

    let userId = null;
    let locations = [];
    let drillPack = null;
    let activeDrill = null;
    let state = {
        compareMode: "period", // period | facilities | utility
        baseLocationId: "",
        compareLocationId: "",
        baseMonthId: M().monthIdFromDate(new Date()),
        compareMonthId: M().monthIdFromDate(new Date(new Date().setMonth(new Date().getMonth() - 1))),
        utilityKey: "electric",
    };

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

    function formatMetricValue(row, value) {
        if (row.format === "number") {
            return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(M().num(value));
        }
        return money(value);
    }

    function locName(id) {
        return locations.find((l) => l.id === id)?.name || "Facility";
    }

    function monthLabel(monthId) {
        const d = M().parseMonthId(monthId);
        return d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
    }

    function monthOptions(selected) {
        const opts = [];
        const now = new Date();
        for (let i = 0; i < 18; i++) {
            const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const id = M().monthIdFromDate(d);
            opts.push(
                `<option value="${id}"${id === selected ? " selected" : ""}>${monthLabel(id)}</option>`
            );
        }
        return opts.join("");
    }

    function formatDayId(dayId) {
        if (!dayId) return "—";
        const parts = dayId.split("-").map(Number);
        if (parts.length < 3) return dayId;
        return new Date(parts[0], parts[1] - 1, parts[2]).toLocaleDateString("en-US", {
            month: "short",
            day: "numeric",
        });
    }

    function renderDrillableKpi(label, amount, drillKey, extraClass) {
        const cls = ["an-kpi", "an-kpi--drill", extraClass].filter(Boolean).join(" ");
        return `
            <button type="button" class="${cls}" data-an-drill="${drillKey}" aria-label="${escapeHtml(label)} breakdown">
                <span>${escapeHtml(label)}</span>
                <strong>${amount}</strong>
            </button>`;
    }

    function renderKpis(agg, title, options) {
        const drillable = options?.drillable !== false;
        return `
            <div class="an-kpi-block">
                ${title ? `<h4 class="an-kpi-block-title">${escapeHtml(title)}</h4>` : ""}
                ${drillable ? '<p class="books-hint an-kpi-hint">Click Sales, Utilities, or Expenses for a breakdown.</p>' : ""}
                <div class="an-kpi-row">
                    ${
                        drillable
                            ? renderDrillableKpi("Sales", money(agg.sales), "sales")
                            : `<div class="an-kpi"><span>Sales</span><strong>${money(agg.sales)}</strong></div>`
                    }
                    <div class="an-kpi"><span>Fuel ($)</span><strong>${money(agg.fuelDollars)}</strong></div>
                    <div class="an-kpi"><span>Fuel gal.</span><strong>${formatMetricValue({ format: "number" }, agg.fuelGallons)}</strong></div>
                    ${
                        drillable
                            ? renderDrillableKpi("Expenses", money(agg.expenses), "expenses")
                            : `<div class="an-kpi"><span>Expenses</span><strong>${money(agg.expenses)}</strong></div>`
                    }
                    <div class="an-kpi"><span>Net</span><strong class="${agg.net >= 0 ? "pos" : "neg"}">${money(agg.net)}</strong></div>
                    ${
                        drillable
                            ? renderDrillableKpi("Utilities", money(agg.utilitiesTotal), "utilities")
                            : `<div class="an-kpi"><span>Utilities</span><strong>${money(agg.utilitiesTotal)}</strong></div>`
                    }
                    <div class="an-kpi"><span>Payroll</span><strong>${money(agg.payrollTotal)}</strong></div>
                    <div class="an-kpi"><span>Over / short</span><strong>${money(agg.totalOverShort)}</strong></div>
                </div>
            </div>`;
    }

    function renderDrillPanel(type) {
        if (!type || !drillPack) return "";
        const { aggregate, title } = drillPack;
        const back = `<button type="button" class="an-drill-back" data-an-drill-close>← Back to overview</button>`;
        const subtitle = `<p class="an-drill-sub">${escapeHtml(title)}</p>`;

        if (type === "sales") {
            const rows = aggregate.salesBreakdown || M().salesBreakdownFromAggregate(aggregate);
            return `
                <section class="an-drill" id="an-drill-panel">
                    ${back}
                    <h3 class="home-cc-heading">Sales breakdown</h3>
                    ${subtitle}
                    <div class="home-card home-cc-table-wrap">
                        <table class="home-cc-table">
                            <thead><tr><th>Source</th><th class="home-cc-num">Amount</th></tr></thead>
                            <tbody>
                                ${rows
                                    .map(
                                        (r) =>
                                            `<tr><td>${escapeHtml(r.label)}</td><td class="home-cc-num">${money(r.amount)}</td></tr>`
                                    )
                                    .join("")}
                                <tr class="an-total-row">
                                    <td><strong>Total sales</strong></td>
                                    <td class="home-cc-num"><strong>${money(aggregate.sales)}</strong></td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </section>`;
        }

        if (type === "utilities") {
            const rows = aggregate.utilitiesBreakdown || [];
            return `
                <section class="an-drill" id="an-drill-panel">
                    ${back}
                    <h3 class="home-cc-heading">Utilities breakdown</h3>
                    ${subtitle}
                    <div class="home-card home-cc-table-wrap">
                        <table class="home-cc-table">
                            <thead><tr><th>Utility</th><th class="home-cc-num">Amount</th></tr></thead>
                            <tbody>
                                ${rows
                                    .map(
                                        (u) =>
                                            `<tr><td>${escapeHtml(u.label)}</td><td class="home-cc-num">${money(u.amount)}</td></tr>`
                                    )
                                    .join("")}
                                <tr class="an-total-row">
                                    <td><strong>Total utilities</strong></td>
                                    <td class="home-cc-num"><strong>${money(aggregate.utilitiesTotal)}</strong></td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </section>`;
        }

        if (type === "expenses") {
            const rows = aggregate.expenseDetail || [];
            const total = rows.reduce((s, r) => s + M().num(r.amount), 0);
            return `
                <section class="an-drill" id="an-drill-panel">
                    ${back}
                    <h3 class="home-cc-heading">Expense detail</h3>
                    ${subtitle}
                    ${
                        rows.length
                            ? `<div class="home-card home-cc-table-wrap an-drill-table-scroll">
                        <table class="home-cc-table">
                            <thead>
                                <tr>
                                    <th>Category</th>
                                    <th>Day</th>
                                    <th>Description</th>
                                    <th class="home-cc-num">Amount</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${rows
                                    .map(
                                        (r) => `<tr>
                                    <td>${escapeHtml(r.category)}</td>
                                    <td>${escapeHtml(r.dayId ? formatDayId(r.dayId) : "—")}</td>
                                    <td>${escapeHtml(r.description)}</td>
                                    <td class="home-cc-num">${money(r.amount)}</td>
                                </tr>`
                                    )
                                    .join("")}
                                <tr class="an-total-row">
                                    <td colspan="3"><strong>Line items total</strong></td>
                                    <td class="home-cc-num"><strong>${money(total)}</strong></td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                    <p class="books-hint">Total expenses (${money(aggregate.expenses)}) includes all categories above.</p>`
                            : `<p class="an-drill-empty">No expense lines for this period. Enter expenses in Data input.</p>`
                    }
                </section>`;
        }

        return "";
    }

    function openDrill(type) {
        activeDrill = type;
        const panel = $("an-drill-mount");
        const overview = $("an-overview-mount");
        if (panel) {
            panel.innerHTML = renderDrillPanel(type);
            panel.hidden = false;
        }
        if (overview) overview.hidden = true;
        panel?.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    function closeDrill() {
        activeDrill = null;
        const panel = $("an-drill-mount");
        const overview = $("an-overview-mount");
        if (panel) {
            panel.innerHTML = "";
            panel.hidden = true;
        }
        if (overview) overview.hidden = false;
    }

    function renderCompareTable(comparison) {
        return `
            <div class="home-card an-compare-table-wrap">
                <table class="home-cc-table">
                    <thead>
                        <tr>
                            <th>Metric</th>
                            <th class="home-cc-num">${escapeHtml(comparison.labels.base)}</th>
                            <th class="home-cc-num">${escapeHtml(comparison.labels.compare)}</th>
                            <th class="home-cc-num">Change</th>
                            <th class="home-cc-num">%</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${comparison.metrics
                            .map((r) => {
                                const cls = r.diff > 0 ? "pos" : r.diff < 0 ? "neg" : "";
                                return `<tr>
                                    <td>${escapeHtml(r.label)}</td>
                                    <td class="home-cc-num">${formatMetricValue(r, r.base)}</td>
                                    <td class="home-cc-num">${formatMetricValue(r, r.compare)}</td>
                                    <td class="home-cc-num ${cls}">${r.diff >= 0 ? "+" : ""}${formatMetricValue(r, r.diff)}</td>
                                    <td class="home-cc-num ${cls}">${r.pct >= 0 ? "+" : ""}${r.pct.toFixed(1)}%</td>
                                </tr>`;
                            })
                            .join("")}
                    </tbody>
                </table>
            </div>`;
    }

    function renderUtilityCompare(comparison) {
        return `
            <h3 class="home-cc-heading">Utilities comparison</h3>
            <div class="home-card home-cc-table-wrap">
                <table class="home-cc-table">
                    <thead>
                        <tr>
                            <th>Utility</th>
                            <th class="home-cc-num">${escapeHtml(comparison.labels.base)}</th>
                            <th class="home-cc-num">${escapeHtml(comparison.labels.compare)}</th>
                            <th class="home-cc-num">Change</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${comparison.utilities
                            .map((r) => {
                                const cls = r.diff > 0 ? "neg" : r.diff < 0 ? "pos" : "";
                                return `<tr>
                                    <td>${escapeHtml(r.label)}</td>
                                    <td class="home-cc-num">${money(r.base)}</td>
                                    <td class="home-cc-num">${money(r.compare)}</td>
                                    <td class="home-cc-num ${cls}">${r.diff >= 0 ? "+" : ""}${money(r.diff)}</td>
                                </tr>`;
                            })
                            .join("")}
                    </tbody>
                </table>
            </div>`;
    }

    function renderUtilitiesBreakdown(agg) {
        return `
            <h3 class="home-cc-heading">Utilities breakdown</h3>
            <div class="home-card home-cc-table-wrap">
                <table class="home-cc-table">
                    <thead><tr><th>Utility</th><th class="home-cc-num">Amount</th></tr></thead>
                    <tbody>
                        ${agg.utilitiesBreakdown
                            .map(
                                (u) =>
                                    `<tr><td>${escapeHtml(u.label)}</td><td class="home-cc-num">${money(u.amount)}</td></tr>`
                            )
                            .join("")}
                        <tr class="an-total-row"><td><strong>Total</strong></td><td class="home-cc-num"><strong>${money(agg.utilitiesTotal)}</strong></td></tr>
                    </tbody>
                </table>
            </div>`;
    }

    function renderExpenseMix(agg) {
        const slices = [
            { label: "Cash expense", amount: agg.cashExpense },
            { label: "Checks / ACH", amount: agg.checksAch },
            { label: "Other", amount: agg.otherExpense },
            { label: "Utilities", amount: agg.utilitiesTotal },
            { label: "Payroll", amount: agg.payrollTotal },
            { label: "Sales tax", amount: agg.salesTax },
            { label: "Accountant", amount: agg.accountant },
        ].filter((s) => s.amount > 0);
        const total = slices.reduce((s, x) => s + x.amount, 0) || 1;
        return `
            <h3 class="home-cc-heading">Expense mix</h3>
            <div class="home-card an-mix">
                ${slices
                    .map((s) => {
                        const pct = (s.amount / total) * 100;
                        return `<div class="an-mix-row">
                            <span class="an-mix-label">${escapeHtml(s.label)}</span>
                            <div class="an-mix-bar"><div class="an-mix-fill" style="width:${pct}%"></div></div>
                            <span class="an-mix-val">${money(s.amount)}</span>
                        </div>`;
                    })
                    .join("")}
            </div>`;
    }

    async function runAnalysis() {
        const out = $("analytics-output");
        out.innerHTML = '<p class="books-hint">Loading…</p>';
        closeDrill();

        try {
            const [primaryPack] = await Store().loadMonthsForCompare(
                userId,
                [state.baseLocationId],
                [state.baseMonthId]
            );
            drillPack = {
                title: `${locName(primaryPack.locationId)} · ${monthLabel(primaryPack.monthId)}`,
                ...primaryPack,
            };

            let overviewHtml = "";

            if (state.compareMode === "period") {
                const [{ aggregate: base }, { aggregate: compare }] = await Store().loadMonthsForCompare(
                    userId,
                    [state.baseLocationId],
                    [state.baseMonthId, state.compareMonthId]
                );
                const labels = {
                    base: `${locName(state.baseLocationId)} · ${monthLabel(state.baseMonthId)}`,
                    compare: `${locName(state.baseLocationId)} · ${monthLabel(state.compareMonthId)}`,
                };
                const cmp = M().compareAggregates(base, compare, labels);
                overviewHtml = `
                    ${renderKpis(primaryPack.aggregate, drillPack.title)}
                    ${renderExpenseMix(primaryPack.aggregate)}
                    <h3 class="home-cc-heading">Period comparison (same facility)</h3>
                    ${renderCompareTable(cmp)}
                    ${renderUtilityCompare(cmp)}
                    <h3 class="home-cc-heading">Compare period summary</h3>
                    ${renderKpis(compare, labels.compare, { drillable: false })}`;
            } else if (state.compareMode === "facilities") {
                const [{ aggregate: base }, { aggregate: compare }] = await Store().loadMonthsForCompare(
                    userId,
                    [state.baseLocationId, state.compareLocationId],
                    [state.baseMonthId, state.baseMonthId]
                );
                const labels = {
                    base: `${locName(state.baseLocationId)} · ${monthLabel(state.baseMonthId)}`,
                    compare: `${locName(state.compareLocationId)} · ${monthLabel(state.baseMonthId)}`,
                };
                const cmp = M().compareAggregates(base, compare, labels);
                overviewHtml = `
                    ${renderKpis(primaryPack.aggregate, drillPack.title)}
                    ${renderExpenseMix(primaryPack.aggregate)}
                    <h3 class="home-cc-heading">Facility comparison (same month)</h3>
                    ${renderCompareTable(cmp)}
                    ${renderUtilityCompare(cmp)}
                    <h3 class="home-cc-heading">Compare facility summary</h3>
                    ${renderKpis(compare, labels.compare, { drillable: false })}`;
            } else if (state.compareMode === "utility") {
                const locIds = locations.map((l) => l.id);
                const packs = await Store().loadMonthsForCompare(
                    userId,
                    locIds,
                    [state.baseMonthId]
                );
                const uLabel =
                    M().UTILITY_KEYS.find((u) => u.key === state.utilityKey)?.label || state.utilityKey;
                overviewHtml = `
                    ${renderKpis(primaryPack.aggregate, drillPack.title)}
                    <h3 class="home-cc-heading">${escapeHtml(uLabel)} — all facilities · ${monthLabel(state.baseMonthId)}</h3>
                    <div class="home-card home-cc-table-wrap">
                        <table class="home-cc-table">
                            <thead><tr><th>Facility</th><th class="home-cc-num">Amount</th></tr></thead>
                            <tbody>
                                ${packs
                                    .map((p) => {
                                        const amt = M().num(p.aggregate.utilities[state.utilityKey]);
                                        return `<tr><td>${escapeHtml(locName(p.locationId))}</td><td class="home-cc-num">${money(amt)}</td></tr>`;
                                    })
                                    .join("")}
                            </tbody>
                        </table>
                    </div>
                    <p class="books-hint">Use “Two facilities” or “Same facility, two months” to see change % for a single utility.</p>`;
            }

            out.innerHTML = `
                <div id="an-drill-mount" class="an-drill-mount" hidden></div>
                <div id="an-overview-mount" class="an-overview-mount">${overviewHtml}</div>`;
        } catch (err) {
            out.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Failed to load books summary.")}</p>`;
        }
    }

    function renderControls() {
        const locOpts = locations
            .map(
                (l) =>
                    `<option value="${l.id}"${l.id === state.baseLocationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            )
            .join("");
        const utilOpts = M().UTILITY_KEYS.map(
            (u) =>
                `<option value="${u.key}"${u.key === state.utilityKey ? " selected" : ""}>${escapeHtml(u.label)}</option>`
        ).join("");

        const periodFields =
            state.compareMode === "period"
                ? `
            <label class="books-label">Base month
                <select id="an-base-month" class="books-select">${monthOptions(state.baseMonthId)}</select>
            </label>
            <label class="books-label">Compare month
                <select id="an-compare-month" class="books-select">${monthOptions(state.compareMonthId)}</select>
            </label>`
                : "";

        const facilityFields =
            state.compareMode === "facilities"
                ? `
            <label class="books-label">Facility A
                <select id="an-base-loc" class="books-select">${locOpts}</select>
            </label>
            <label class="books-label">Facility B
                <select id="an-compare-loc" class="books-select">${locations
                    .map(
                        (l) =>
                            `<option value="${l.id}"${l.id === state.compareLocationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
                    )
                    .join("")}</select>
            </label>
            <label class="books-label">Month
                <select id="an-base-month" class="books-select">${monthOptions(state.baseMonthId)}</select>
            </label>`
                : "";

        const utilityFields =
            state.compareMode === "utility"
                ? `
            <label class="books-label">Utility
                <select id="an-utility" class="books-select">${utilOpts}</select>
            </label>
            <label class="books-label">Month
                <select id="an-base-month" class="books-select">${monthOptions(state.baseMonthId)}</select>
            </label>`
                : "";

        const baseLocField =
            state.compareMode === "period"
                ? `<label class="books-label">Facility
                <select id="an-base-loc" class="books-select">${locOpts}</select>
            </label>`
                : "";

        return `
            <div class="an-controls">
                <label class="books-label">Compare by
                    <select id="an-mode" class="books-select">
                        <option value="period"${state.compareMode === "period" ? " selected" : ""}>Same facility · two months</option>
                        <option value="facilities"${state.compareMode === "facilities" ? " selected" : ""}>Two facilities · same month</option>
                        <option value="utility"${state.compareMode === "utility" ? " selected" : ""}>One utility · all facilities</option>
                    </select>
                </label>
                ${baseLocField}
                ${periodFields}
                ${facilityFields}
                ${utilityFields}
                <button type="button" class="btn books-save" id="an-run">View results</button>
            </div>
            <p class="books-hint">Data comes from <strong>Data input</strong>. Enter utilities, daily sales, and expenses there first.</p>`;
    }

    function readControls() {
        const mode = $("an-mode");
        if (mode) state.compareMode = mode.value;
        const bl = $("an-base-loc");
        if (bl) state.baseLocationId = bl.value;
        const cl = $("an-compare-loc");
        if (cl) state.compareLocationId = cl.value;
        const bm = $("an-base-month");
        if (bm) state.baseMonthId = bm.value;
        const cm = $("an-compare-month");
        if (cm) state.compareMonthId = cm.value;
        const u = $("an-utility");
        if (u) state.utilityKey = u.value;
    }

    function bindControls() {
        const panel = $("panel-analytics");
        if (!panel || panel.dataset.anBound) return;
        panel.dataset.anBound = "1";

        panel.addEventListener("click", (e) => {
            if (e.target.id === "an-run") {
                readControls();
                runAnalysis();
                return;
            }
            const drillBtn = e.target.closest("[data-an-drill]");
            if (drillBtn) {
                openDrill(drillBtn.dataset.anDrill);
                return;
            }
            if (e.target.closest("[data-an-drill-close]")) {
                closeDrill();
            }
        });

        panel.addEventListener("change", (e) => {
            if (e.target.id === "an-mode") {
                readControls();
                render();
            }
        });
    }

    function render() {
        const root = $("analytics-root");
        if (!root) return;
        if (!locations.length) {
            root.innerHTML =
                '<p class="data-list-empty">Add a facility and enter data in Data input first.</p>';
            return;
        }
        if (!state.baseLocationId) state.baseLocationId = locations[0].id;
        if (!state.compareLocationId && locations[1])
            state.compareLocationId = locations[1].id;
        else if (!state.compareLocationId) state.compareLocationId = locations[0].id;

        root.innerHTML = `${renderControls()}<div id="analytics-output" class="an-output"></div>`;
    }

    window.OplixAnalytics = {
        init(uid, locs) {
            userId = uid;
            locations = locs || [];
            bindControls();
            render();
        },
        onShow() {
            readControls();
            if (userId && locations.length) runAnalysis();
        },
    };
})();
