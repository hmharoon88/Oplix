/**
 * Books summary — monthly totals and history from Daily books.
 */
(function () {
    const M = () => window.OplixBooksModel;
    const Store = () => window.OplixBooksStore;
    const Charts = () => window.OplixBooksSummaryCharts;
    const RBS = () => window.OplixReportsBooksSections;
    const RM = () => window.OplixReportsModel;
    const ReportsStore = () => window.OplixReportsStore;

    let userId = null;
    let locations = [];
    let drillPack = null;
    let activeDrill = null;
    let lastRenderedKey = null;
    let currentRootId = "analytics-root";
    let embeddedLocationId = null;
    let state = {
        locationId: "",
        monthId: "",
        showCompare: false,
    };

    function isEmbedded() {
        return !!embeddedLocationId;
    }

    function scopeRoot() {
        return document.getElementById(currentRootId);
    }

    function idFor(base) {
        return isEmbedded() ? `${currentRootId}-${base}` : base;
    }

    function elById(base) {
        return document.getElementById(idFor(base));
    }

    function monthControlId() {
        return idFor("an-month");
    }

    function locControlId() {
        return idFor("an-loc");
    }

    function compareControlId() {
        return idFor("an-compare-toggle");
    }

    function defaultMonthId() {
        return M()?.monthIdFromDate(new Date()) || "";
    }

    function ensureStateMonth() {
        if (!state.monthId) state.monthId = defaultMonthId();
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

    function formatMetricValue(row, value) {
        if (row.format === "number") {
            return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(M().num(value));
        }
        return money(value);
    }

    function dailyTableCell(value, prevValue, row, opts) {
        if (!row.hasData) return `<td class="home-cc-num">—</td>`;
        const formatted =
            opts?.format === "number"
                ? formatMetricValue({ format: "number" }, value)
                : money(value);
        const cellClass = opts?.cellClass || "";
        if (prevValue == null || !Charts()?.renderCellTrend) {
            return `<td class="home-cc-num${cellClass ? ` ${cellClass}` : ""}">${formatted}</td>`;
        }
        const trend = Charts().renderCellTrend(value, prevValue, {
            invert: opts?.trendInvert,
            format: opts?.format,
            compareMode: "day",
        });
        return Charts().renderTableValueCell(formatted, trend, cellClass);
    }

    function locName(id) {
        return locations.find((l) => l.id === id)?.name || "Facility";
    }

    function facilityTypesById() {
        const map = {};
        locations.forEach((l) => {
            map[l.id] = l.facilityType === "c_store_gas" ? "c_store_gas" : "c_store";
        });
        return map;
    }

    function booksFieldConfigsById() {
        const FC = window.OplixBooksFieldConfig;
        const out = {};
        locations.forEach((l) => {
            out[l.id] = FC ? FC.configFromLocation(l) : null;
        });
        return out;
    }

    function loadOptions() {
        return {
            facilityTypesById: facilityTypesById(),
            booksFieldConfigsById: booksFieldConfigsById(),
        };
    }

    async function fetchLotteryForms(locationId) {
        if (!userId || !locationId || !window.oplixDb) return [];
        try {
            const snap = await window.oplixDb
                .collection("users")
                .doc(userId)
                .collection("locations")
                .doc(locationId)
                .collection("lotteryForms")
                .get();
            return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
        } catch (err) {
            console.warn("[Oplix] Could not load lottery forms for summary:", err);
            return [];
        }
    }

    function applyLotteryFormsToPack(pack, forms) {
        if (!pack?.aggregate || !forms?.length) return pack;
        return {
            ...pack,
            aggregate: M().enrichAggregateWithLotteryForms(
                pack.aggregate,
                forms,
                pack.monthId
            ),
        };
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

    function monthIdsForHistory(anchorMonthId, count) {
        const anchor = M().parseMonthId(anchorMonthId);
        const ids = [];
        for (let i = 0; i < count; i++) {
            ids.push(M().monthIdFromDate(new Date(anchor.getFullYear(), anchor.getMonth() - i, 1)));
        }
        return ids;
    }

    function renderPreviousMonthsSection(packs, locationId, currentMonthId, progressText) {
        if (!packs.length && !progressText) return "";
        const isGas = !!packs[0]?.aggregate?.hasGasStation;
        const M = window.OplixBooksModel;
        const rows = packs
            .slice()
            .sort((a, b) => b.monthId.localeCompare(a.monthId))
            .map((p) => {
                const agg = p.aggregate;
                const netCls = agg.net >= 0 ? "pos" : "neg";
                const cc = M ? M.cardCashBreakdownFromAggregate(agg) : { card: 0, cash: 0 };
                const salesStats = isGas
                    ? `<span class="an-prev-month-stat"><em>Merch</em><strong>${money(agg.sales)}</strong></span>
                        <span class="an-prev-month-stat"><em>Fuel (gal)</em><strong>${formatMetricValue({ format: "number" }, agg.fuelGallons)}</strong></span>
                        <span class="an-prev-month-stat"><em>Fuel ($)</em><strong>${money(agg.fuelDollars)}</strong></span>`
                    : `<span class="an-prev-month-stat"><em>Sales</em><strong>${money(agg.sales)}</strong></span>
                        <span class="an-prev-month-stat"><em>Card</em><strong>${money(cc.card)}</strong></span>
                        <span class="an-prev-month-stat"><em>Cash</em><strong>${money(cc.cash)}</strong></span>`;
                return `
                    <button type="button" class="an-prev-month-row${isGas ? " an-prev-month-row--gas" : " an-prev-month-row--cstore"}" data-an-prev-month="${escapeHtml(p.monthId)}">
                        <span class="an-prev-month-name">${escapeHtml(monthLabel(p.monthId))}</span>
                        ${salesStats}
                        <span class="an-prev-month-stat"><em>Expenses</em><strong>${money(agg.expenses)}</strong></span>
                        <span class="an-prev-month-stat an-prev-month-stat--net"><em>Net</em><strong class="${netCls}">${money(agg.net)}</strong></span>
                    </button>`;
            })
            .join("");

        return `
            <section class="an-prev-months">
                <header class="an-prev-months-head">
                    <h3 class="an-prev-months-title">Previous months · ${escapeHtml(locName(locationId))}</h3>
                    <p class="an-prev-months-lead">Books totals for earlier months. Tap a row to load that month above (currently ${escapeHtml(monthLabel(currentMonthId))}).</p>
                </header>
                ${progressText ? `<p class="books-hint an-history-progress">${escapeHtml(progressText)}</p>` : ""}
                <div class="an-prev-month-list">${rows}</div>
            </section>`;
    }

    function syncMonthSelect() {
        const root = scopeRoot();
        if (!root) return;
        const monthEl = root.querySelector(`#${monthControlId()}`);
        if (monthEl) monthEl.value = state.monthId;
        const locEl = root.querySelector(`#${locControlId()}`);
        if (locEl) locEl.value = state.locationId;
    }

    function renderPreviousMonthsMount(html) {
        const mount = elById("an-previous-mount");
        if (!mount) return;
        mount.innerHTML = html || "";
        mount.hidden = !html;
    }

    function renderKeyMetricsMount(html) {
        const mount = elById("an-key-metrics-mount");
        if (!mount) return;
        mount.innerHTML = html || "";
        mount.hidden = !html;
    }

    function formatDayId(dayId) {
        if (!dayId) return "—";
        const parts = dayId.split("-").map(Number);
        if (parts.length < 3) return dayId;
        return new Date(parts[0], parts[1] - 1, parts[2]).toLocaleDateString("en-US", {
            weekday: "short",
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
            const gasNote = aggregate.hasGasStation
                ? `<p class="books-hint an-drill-note">Total sales uses merch only. Credit card tile uses register card from the detail sheet.</p>`
                : "";
            return `
                <section class="an-drill bs-drill" id="an-drill-panel">
                    ${back}
                    <h3 class="home-cc-heading">Sales breakdown</h3>
                    ${subtitle}
                    ${gasNote}
                    <div class="home-card home-cc-table-wrap">
                        <table class="home-cc-table">
                            <thead><tr><th>Source</th><th class="home-cc-num">Amount</th></tr></thead>
                            <tbody>
                                ${rows
                                    .map(
                                        (r) =>
                                            `<tr><td>${escapeHtml(r.label)}</td><td class="home-cc-num">${r.format === "number" ? formatMetricValue({ format: "number" }, r.amount) : money(r.amount)}</td></tr>`
                                    )
                                    .join("")}
                                <tr class="an-total-row">
                                    <td><strong>${aggregate.hasGasStation ? "Total sales (merch)" : "Total sales"}</strong></td>
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
                <section class="an-drill bs-drill" id="an-drill-panel">
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
                <section class="an-drill bs-drill" id="an-drill-panel">
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
                            : `<p class="an-drill-empty">No expense lines for this period. Enter expenses in Daily books.</p>`
                    }
                </section>`;
        }

        return "";
    }

    function openDrill(type) {
        activeDrill = type;
        const panel = elById("an-drill-mount");
        const overview = elById("an-overview-mount");
        if (panel) {
            panel.innerHTML = renderDrillPanel(type);
            panel.hidden = false;
        }
        if (overview) overview.hidden = true;
        panel?.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    function closeDrill() {
        activeDrill = null;
        const panel = elById("an-drill-mount");
        const overview = elById("an-overview-mount");
        if (panel) {
            panel.innerHTML = "";
            panel.hidden = true;
        }
        if (overview) overview.hidden = false;
    }

    function renderMainDashboard(agg, title, options) {
        if (Charts()) {
            return Charts().renderDashboard(agg, {
                title,
                drillable: options?.drillable,
                booksModel: M(),
                formatDay: formatDayId,
            });
        }
        return renderKpis(agg, title, options);
    }

    function renderDailySalesExpenseSection(pack) {
        const hasGas = !!pack?.aggregate?.hasGasStation;
        const { rows, totals } = M().dailySalesExpenseRows(pack.monthId, pack.daysById, {
            hasGasStation: hasGas,
        });

        if (!totals.daysWithData) {
            return `
                <section class="bs-panel bs-panel--daily-sales">
                    <div class="bs-panel-head">
                        <div class="bs-panel-head-text">
                            <h3 class="bs-panel-title">Daily sales &amp; expenses</h3>
                            <p class="bs-panel-sub">Day-by-day totals for ${escapeHtml(monthLabel(pack.monthId))}.</p>
                        </div>
                    </div>
                    <p class="books-hint">No daily entries yet. Enter sales and expenses on <strong>Daily books → Daily sheet</strong>.</p>
                </section>`;
        }

        const salesHint = hasGas
            ? "Merch, credit card, and fuel are separate columns. Net uses merch minus daily expenses — credit card, fuel, pulltab, lottery, wind, and keno are not included in net."
            : "Sales = register card + cash for each day.";

        const tableRows = rows
            .map((row, rowIndex) => {
                const dayDoc = pack.daysById?.[row.dayId];
                const closedMark =
                    dayDoc && M().isDayClosed(dayDoc)
                        ? ' <span class="an-day-closed" title="Day closed">🔒</span>'
                        : "";
                const emptyCls = row.hasData ? "" : " an-daily-row--empty";
                const prev = rowIndex > 0 ? rows[rowIndex - 1] : null;
                const prevVal = (field) => (prev?.hasData ? prev[field] : null);
                const extraGas = hasGas
                    ? `${dailyTableCell(row.merchSale, prevVal("merchSale"), row, {})}
                       ${dailyTableCell(row.fuelGallons, prevVal("fuelGallons"), row, { format: "number" })}
                       ${dailyTableCell(row.fuelDollars, prevVal("fuelDollars"), row, {})}
                       ${dailyTableCell(row.creditCard, prevVal("creditCard"), row, {})}`
                    : "";
                const salesCell = hasGas
                    ? ""
                    : dailyTableCell(row.sales, prevVal("sales"), row, {});
                return `
                    <tr class="an-daily-row${emptyCls}">
                        <td class="an-daily-day-col">${escapeHtml(formatDayId(row.dayId))}${closedMark}</td>
                        ${extraGas}
                        ${salesCell}
                        ${dailyTableCell(row.cashExpense, prevVal("cashExpense"), row, { trendInvert: true })}
                        ${dailyTableCell(row.checksAch, prevVal("checksAch"), row, { trendInvert: true })}
                        ${dailyTableCell(row.otherExpense, prevVal("otherExpense"), row, { trendInvert: true })}
                        ${dailyTableCell(row.expenses, prevVal("expenses"), row, { trendInvert: true })}
                        ${dailyTableCell(row.net, prevVal("net"), row, {
                            cellClass: `an-daily-net${row.net >= 0 ? " pos" : " neg"}`,
                        })}
                    </tr>`;
            })
            .join("");

        const gasHead = hasGas
            ? `<th class="home-cc-num">Merch</th>
               <th class="home-cc-num">Fuel (gal)</th>
               <th class="home-cc-num">Fuel ($)</th>
               <th class="home-cc-num">Credit card</th>`
            : "";

        const monthTotals = hasGas
            ? `<span><em>Merch</em> <strong>${money(totals.merchSale)}</strong></span>
               <span><em>Fuel (gal)</em> <strong>${formatMetricValue({ format: "number" }, totals.fuelGallons)}</strong></span>
               <span><em>Fuel ($)</em> <strong>${money(totals.fuelDollars)}</strong></span>
               <span><em>Credit card</em> <strong>${money(totals.creditCard)}</strong></span>`
            : `<span><em>Sales</em> <strong>${money(totals.sales)}</strong></span>`;

        const salesColHead = hasGas ? "" : `<th class="home-cc-num">Sales</th>`;

        const gasFoot = hasGas
            ? `<td class="home-cc-num"><strong>${money(totals.merchSale)}</strong></td>
               <td class="home-cc-num"><strong>${formatMetricValue({ format: "number" }, totals.fuelGallons)}</strong></td>
               <td class="home-cc-num"><strong>${money(totals.fuelDollars)}</strong></td>
               <td class="home-cc-num"><strong>${money(totals.creditCard)}</strong></td>`
            : "";

        const salesFoot = hasGas
            ? ""
            : `<td class="home-cc-num"><strong>${money(totals.sales)}</strong></td>`;

        return `
            <section class="bs-panel bs-panel--daily-sales">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">Daily sales &amp; expenses</h3>
                        <p class="bs-panel-sub">${escapeHtml(monthLabel(pack.monthId))} · ${totals.daysWithData} of ${rows.length} days with entries. ${escapeHtml(salesHint)}</p>
                        ${window.OplixBooksTrendLegend ? OplixBooksTrendLegend.legendHtml("day") : ""}
                    </div>
                </div>
                <div class="books-cash-recon-totals an-daily-month-totals">
                    ${monthTotals}
                    <span><em>Expenses</em> <strong>${money(totals.expenses)}</strong></span>
                    <span><em>Net</em> <strong class="${totals.net >= 0 ? "pos" : "neg"}">${money(totals.net)}</strong></span>
                </div>
                <div class="home-card home-cc-table-wrap an-daily-table-wrap">
                    <table class="home-cc-table an-daily-table">
                        <thead>
                            <tr>
                                <th class="an-daily-day-col">Day / date</th>
                                ${gasHead}
                                ${salesColHead}
                                <th class="home-cc-num">Cash exp.</th>
                                <th class="home-cc-num">Check Exp</th>
                                <th class="home-cc-num">Other</th>
                                <th class="home-cc-num">Total exp.</th>
                                <th class="home-cc-num">Net</th>
                            </tr>
                        </thead>
                        <tbody>${tableRows}</tbody>
                        <tfoot>
                            <tr class="an-total-row">
                                <td><strong>Month (days entered)</strong></td>
                                ${gasFoot}
                                ${salesFoot}
                                <td class="home-cc-num"><strong>${money(totals.cashExpense)}</strong></td>
                                <td class="home-cc-num"><strong>${money(totals.checksAch)}</strong></td>
                                <td class="home-cc-num"><strong>${money(totals.otherExpense)}</strong></td>
                                <td class="home-cc-num"><strong>${money(totals.expenses)}</strong></td>
                                <td class="home-cc-num"><strong class="${totals.net >= 0 ? "pos" : "neg"}">${money(totals.net)}</strong></td>
                            </tr>
                        </tfoot>
                    </table>
                </div>
                <p class="books-hint an-daily-footnote">Daily expenses are from the Daily sheet only. Monthly utilities, payroll, sales tax, and accountant fees are included in the month totals above, not in this table.${
                    hasGas
                        ? " For gas stations, <strong>Net</strong> uses merch only — credit card, fuel, pulltab, lottery, wind, and keno are track only."
                        : ""
                }</p>
            </section>`;
    }

    function renderCashReconciliationCategory(title, subtitle, category) {
        const rows = category?.dailyRows || [];
        if (!rows.length) {
            return `
                <div class="bs-cash-recon-category">
                    <h4 class="bs-cash-recon-category-title">${escapeHtml(title)}</h4>
                    <p class="books-hint">No ${escapeHtml(title.toLowerCase())} entries this month.</p>
                </div>`;
        }

        const summaryLine =
            category.daysWithExpected > 0
                ? `<p class="books-cash-recon-month-summary"><strong>${category.daysReconciled}</strong> of <strong>${category.daysWithExpected}</strong> days reconciled${
                      category.daysNeedingAttention > 0
                          ? ` · <span class="bs-cash-recon-attn">${category.daysNeedingAttention} need attention</span>`
                          : ""
                  }</p>`
                : "";

        const tableRows = rows
            .map((row) => {
                const tone = row.status?.tone || "missing";
                const label = row.status?.label || "—";
                const depositCell = row.deposit == null ? "—" : money(row.deposit);
                const varianceCell =
                    row.deposit != null ? money(row.depositVariance) : money(row.variance);
                const statusCell =
                    tone === "unreconciled"
                        ? `<button type="button" class="bs-cash-recon-badge bs-cash-recon-badge--${tone} bs-cash-recon-badge--link" data-an-open-recon="${escapeHtml(row.dayId)}" title="Open cash reconciliation for this day">${escapeHtml(label)}</button>`
                        : `<span class="bs-cash-recon-badge bs-cash-recon-badge--${tone}">${escapeHtml(label)}</span>`;
                return `
                    <tr>
                        <td>${escapeHtml(formatDayId(row.dayId))}</td>
                        <td class="home-cc-num">${money(row.countedTotal)}</td>
                        ${
                            category.totalCashExpenses > 0
                                ? `<td class="home-cc-num">${money(row.cashExpensesTotal || 0)}</td>`
                                : ""
                        }
                        <td class="home-cc-num">${money(row.expectedDeposit)}</td>
                        <td class="home-cc-num">${depositCell}</td>
                        <td class="home-cc-num">${varianceCell}</td>
                        <td>${statusCell}</td>
                    </tr>`;
            })
            .join("");

        const showExpenses = category.totalCashExpenses > 0;

        return `
            <div class="bs-cash-recon-category">
                <h4 class="bs-cash-recon-category-title">${escapeHtml(title)}</h4>
                ${subtitle ? `<p class="books-hint bs-cash-recon-category-sub">${escapeHtml(subtitle)}</p>` : ""}
                ${summaryLine}
                <div class="books-cash-recon-totals bs-cash-recon-month-totals">
                    <span><em>Received</em> <strong>${money(category.totalCounted)}</strong></span>
                    ${showExpenses ? `<span><em>Cash expenses</em> <strong>${money(category.totalCashExpenses)}</strong></span>` : ""}
                    <span><em>Expected</em> <strong>${money(category.totalExpectedDeposit)}</strong></span>
                    <span><em>Received / deposited</em> <strong>${money(category.totalDeposit)}</strong></span>
                    <span><em>Variance</em> <strong>${money(category.totalDepositVariance || category.totalVariance)}</strong></span>
                </div>
                <div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table bs-cash-recon-month-table">
                        <thead>
                            <tr>
                                <th>Day</th>
                                <th class="home-cc-num">Received</th>
                                ${showExpenses ? `<th class="home-cc-num">Expenses</th>` : ""}
                                <th class="home-cc-num">Expected</th>
                                <th class="home-cc-num">Received / deposited</th>
                                <th class="home-cc-num">Variance</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>${tableRows}</tbody>
                    </table>
                </div>
            </div>`;
    }

    function renderCashReconciliationSection(agg) {
        const cr = agg?.cashReconciliation;
        const lotterySubtitle = agg?.lotteryCashFromForms
            ? "Cash enclosed from lottery shift closes (Facilities → Lottery)."
            : "Lottery cash per shift from the Daily sheet.";
        const categories = [
            {
                title: "Register cash",
                subtitle: "Register cash minus cash expenses = expected deposit.",
                data: cr?.register || cr,
            },
            {
                title: "Lottery cash",
                subtitle: lotterySubtitle,
                data: cr?.lottery,
            },
            {
                title: "Pulltab cash",
                subtitle: "Pulltab machine cash from the Daily sheet.",
                data: cr?.pulltab,
            },
            {
                title: "Wind station cash",
                subtitle: "Wind station cash from the Daily sheet.",
                data: cr?.wind,
            },
            {
                title: "Keno station cash",
                subtitle: "Keno station cash from the Daily sheet.",
                data: cr?.keno,
            },
        ];

        const hasAny = categories.some((c) => (c.data?.dailyRows || []).length > 0);

        if (!hasAny) {
            return `
                <section class="bs-panel bs-panel--cash-recon">
                    <div class="bs-panel-head">
                        <div class="bs-panel-head-text">
                            <h3 class="bs-panel-title">Cash reconciliation</h3>
                            <p class="bs-panel-sub">Register, lottery, pulltab, wind, and keno station cash by day.</p>
                        </div>
                    </div>
                    <p class="books-hint">No cash entries this month yet. Enter amounts on <strong>Daily books → Daily sheet</strong>, then reconcile on <strong>Cash reconciliation</strong>.</p>
                </section>`;
        }

        return `
            <section class="bs-panel bs-panel--cash-recon">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">Cash reconciliation</h3>
                        <p class="bs-panel-sub">Daily received and deposited amounts by category. Edit in Daily books → Cash reconciliation.</p>
                    </div>
                </div>
                ${categories.map((c) => renderCashReconciliationCategory(c.title, c.subtitle, c.data)).join("")}
            </section>`;
    }

    function prevMonthId(monthId) {
        const d = M().parseMonthId(monthId);
        return M().monthIdFromDate(new Date(d.getFullYear(), d.getMonth() - 1, 1));
    }

    async function loadApArData() {
        const PM = window.OplixPayablesModel;
        const RecM = window.OplixReceivablesModel;
        if (!PM || !RecM || !ReportsStore() || !RM() || !userId || !state.locationId) {
            return { snapshot: null, report: null };
        }
        try {
            const pack = await ReportsStore().loadPayablesReceivables(
                userId,
                state.locationId,
                locName(state.locationId)
            );
            const report = RM().buildPayablesReceivablesReport([pack], {
                locationName: locName(state.locationId),
                allLocations: false,
            });
            const summary = report.summary || [];
            return {
                snapshot: {
                    openPayables: summary[0]?.value ?? 0,
                    openReceivables: summary[1]?.value ?? 0,
                    overduePayables: summary[2]?.value ?? 0,
                    overdueReceivables: summary[3]?.value ?? 0,
                },
                report,
            };
        } catch (err) {
            console.warn("[Oplix] Could not load payables/receivables for summary:", err);
            return { snapshot: null, report: null };
        }
    }

    async function loadCompareHtml(primaryPack) {
        if (!state.showCompare || !Charts() || !primaryPack?.aggregate) return "";
        const prevId = prevMonthId(state.monthId);
        let prevAgg;
        try {
            const [prevPack] = await Store().loadMonthsForCompare(
                userId,
                [state.locationId],
                [prevId],
                loadOptions()
            );
            prevAgg = prevPack?.aggregate || M().aggregateMonth(M().defaultMonthDoc(), {}, loadOptions().facilityTypesById[state.locationId] === "c_store_gas" ? { hasGasStation: true } : {});
        } catch {
            prevAgg = M().aggregateMonth(M().defaultMonthDoc(), {}, {
                hasGasStation: facilityTypesById()[state.locationId] === "c_store_gas",
            });
        }
        const cmp = M().compareAggregates(primaryPack.aggregate, prevAgg, {
            base: `${locName(state.locationId)} · ${monthLabel(state.monthId)}`,
            compare: `${locName(state.locationId)} · ${monthLabel(prevId)}`,
        });
        return Charts().renderCompareOverview(cmp, primaryPack.aggregate, prevAgg, M());
    }

    function renderApArSnapshot(snapshot) {
        if (!snapshot || !RBS()) return "";
        return RBS().renderPayablesReceivablesSnapshot(
            snapshot.openPayables,
            snapshot.openReceivables,
            snapshot.overduePayables,
            snapshot.overdueReceivables
        );
    }

    function renderMonthPicker() {
        const locOpts = locations
            .map(
                (l) =>
                    `<option value="${l.id}"${l.id === state.locationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            )
            .join("");
        const showFacility = locations.length > 1 && !isEmbedded();
        const monthId = monthControlId();
        const locId = locControlId();
        const compareId = compareControlId();

        const fieldsClass = showFacility
            ? "bs-toolbar-fields an-month-toolbar-fields an-month-toolbar-fields--with-facility"
            : "bs-toolbar-fields an-month-toolbar-fields";

        return `
            <div class="bs-toolbar an-month-toolbar">
                <div class="${fieldsClass}">
                    ${
                        showFacility
                            ? `<label class="books-label an-tb-field an-tb-facility">Facility
                        <select id="${locId}" class="books-select">${locOpts}</select>
                    </label>`
                            : ""
                    }
                    <label class="books-label an-tb-field an-tb-month">Month
                        <select id="${monthId}" class="books-select">${monthOptions(state.monthId)}</select>
                    </label>
                    <button type="button" class="btn btn-nav-outline an-compare-toggle an-tb-field an-tb-action" id="${compareId}">
                        ${state.showCompare ? "Hide month compare" : "Compare to previous month"}
                    </button>
                    <div class="an-month-status an-tb-badge">${renderMonthStatusBadge()}</div>
                </div>
                ${state.showCompare && window.OplixBooksTrendLegend ? OplixBooksTrendLegend.legendHtml("month") : ""}
            </div>`;
    }

    let reviewMonthDoc = null;

    function renderMonthStatusBadge() {
        const month = reviewMonthDoc;
        if (!month) return "";
        if (M().isMonthClosed(month)) {
            const at = month.closedAt
                ? new Date(month.closedAt).toLocaleDateString("en-US", { dateStyle: "medium" })
                : "";
            return `<span class="bs-month-badge bs-month-badge--closed" title="Month closed${at ? ` · ${at}` : ""}">Month closed</span>`;
        }
        return `<span class="bs-month-badge bs-month-badge--open">Month open</span>`;
    }

    function refreshMonthStatusBadge() {
        const slot = scopeRoot()?.querySelector(".an-month-status");
        if (!slot) return;
        slot.innerHTML = renderMonthStatusBadge();
    }

    function reviewAmountRow(label, amount, opts = {}) {
        const n = M().num(amount);
        if (!opts.showZero && n === 0) return "";
        const prefix = opts.credit ? "+" : opts.expense ? "−" : "";
        const display = opts.credit || opts.expense ? `${prefix}${money(Math.abs(n))}` : money(n);
        const note = opts.note ? `<span class="bs-review-note">${escapeHtml(opts.note)}</span>` : "";
        return `<tr><td>${escapeHtml(label)}${note}</td><td class="home-cc-num">${display}</td></tr>`;
    }

    function renderBooksReviewSection(pack, apArReport) {
        if (!pack?.aggregate) return "";
        const agg = pack.aggregate;
        const month = pack.month || M().defaultMonthDoc();
        const health = M().booksHealthSummary(pack.monthId, pack.daysById, month, {
            hasGasStation: agg.hasGasStation,
        });
        const supplement = RM()?.buildBooksSupplement?.(agg) || {};
        const legacyRec = (month.receivables || []).filter((r) => !r.linkedReceivableId);

        const revenueRows = [
            ...(agg.salesBreakdown || M().salesBreakdownFromAggregate(agg))
                .filter((r) => M().num(r.amount) !== 0)
                .map((r) =>
                    reviewAmountRow(r.label, r.amount, {
                        note: r.format === "number" ? "count" : "",
                    })
                ),
            reviewAmountRow("Month credits (Net)", agg.receivablesTotal, { credit: true }),
            ...(agg.monthAdjustments || [])
                .filter((a) => a.kind === "credit" && M().num(a.amount) !== 0)
                .map((a) => reviewAmountRow(`Adjustment — ${a.description || "Credit"}`, a.amount, { credit: true })),
        ].filter(Boolean);

        const expenseRows = [
            reviewAmountRow("Cash expenses (daily)", agg.cashExpense, { expense: true }),
            reviewAmountRow("Checks / ACH", agg.checksAch, { expense: true }),
            reviewAmountRow("Other daily expenses", agg.otherExpense, { expense: true }),
            ...(agg.utilitiesBreakdown || [])
                .filter((u) => M().num(u.amount) !== 0)
                .map((u) => reviewAmountRow(`Utility — ${u.label}`, u.amount, { expense: true })),
            reviewAmountRow("Payroll", agg.payrollTotal, { expense: true }),
            reviewAmountRow("Sales tax", agg.salesTax, { expense: true }),
            reviewAmountRow("Accountant", agg.accountant, { expense: true }),
            ...(agg.monthAdjustments || [])
                .filter((a) => a.kind !== "credit" && M().num(a.amount) !== 0)
                .map((a) =>
                    reviewAmountRow(`Adjustment — ${a.description || "Expense"}`, a.amount, { expense: true })
                ),
        ].filter(Boolean);

        const statusItems = [
            { label: "Days with entry", value: `${health.daysWithData} / ${health.daysInMonth}` },
            { label: "Days closed", value: String(health.daysClosed) },
            {
                label: "Days with entry not closed",
                value: String(health.unclosedWithData),
                warn: health.unclosedWithData > 0,
            },
            { label: "Month status", value: M().isMonthClosed(month) ? "Closed" : "Open" },
        ];

        const payoutsHtml =
            supplement.registerPayouts?.length && RBS()
                ? `<div class="bs-review-block">
                    <h4 class="bs-review-subtitle">Register payouts</h4>
                    ${RBS().renderRegisterPayouts(supplement.registerPayouts)}
                </div>`
                : "";

        const payrollHtml =
            (supplement.booksPayroll?.length || agg.payrollTotal) && RBS()
                ? `<div class="bs-review-block">
                    <h4 class="bs-review-subtitle">Payroll detail</h4>
                    ${RBS().renderBooksPayroll(supplement.booksPayroll, agg.payrollTotal)}
                </div>`
                : "";

        const apArHtml =
            apArReport && RBS()
                ? `<div class="bs-review-block">
                    ${RBS().renderPayablesReceivablesReport(apArReport)}`
                : "";

        const legacyHtml = legacyRec.length
            ? `<div class="bs-review-block">
                <h4 class="bs-review-subtitle">Legacy month credits</h4>
                <table class="home-cc-table">
                    <thead><tr><th>Description</th><th class="home-cc-num">Amount</th></tr></thead>
                    <tbody>${legacyRec
                        .map(
                            (r) =>
                                `<tr><td>${escapeHtml(r.description || "—")}</td><td class="home-cc-num">${money(r.amount)}</td></tr>`
                        )
                        .join("")}</tbody>
                </table></div>`
            : "";

        const closeNotes = month.closeNotes?.trim()
            ? `<div class="bs-review-block"><h4 class="bs-review-subtitle">Close notes</h4><p class="books-hint">${escapeHtml(month.closeNotes)}</p></div>`
            : "";

        return `
            <section class="bs-panel bs-panel--review">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">Books review</h3>
                        <p class="bs-panel-sub">Everything recorded for this facility and month. Edit in <strong>Daily books</strong> or <strong>Monthly books</strong>.</p>
                    </div>
                </div>
                <div class="bs-review-status-grid">
                    ${statusItems
                        .map(
                            (item) =>
                                `<div class="bs-review-status${item.warn ? " bs-review-status--warn" : ""}"><span>${escapeHtml(item.label)}</span><strong>${escapeHtml(item.value)}</strong></div>`
                        )
                        .join("")}
                </div>
                <div class="bs-review-grid">
                    <div class="bs-review-block">
                        <h4 class="bs-review-subtitle">Revenue &amp; credits</h4>
                        ${
                            revenueRows.length
                                ? `<table class="home-cc-table bs-review-table"><tbody>${revenueRows.join("")}<tr class="an-total-row"><td><strong>Net</strong></td><td class="home-cc-num"><strong class="${agg.net >= 0 ? "pos" : "neg"}">${money(agg.net)}</strong></td></tr></tbody></table>`
                                : `<p class="books-hint">No revenue recorded this month.</p>`
                        }
                    </div>
                    <div class="bs-review-block">
                        <h4 class="bs-review-subtitle">Expenses</h4>
                        ${
                            expenseRows.length
                                ? `<table class="home-cc-table bs-review-table"><tbody>${expenseRows.join("")}<tr class="an-total-row"><td><strong>Total expenses</strong></td><td class="home-cc-num"><strong>${money(agg.expenses)}</strong></td></tr></tbody></table>`
                                : `<p class="books-hint">No expenses recorded this month.</p>`
                        }
                    </div>
                </div>
                ${payoutsHtml}
                ${payrollHtml}
                ${apArHtml}
                ${legacyHtml}
                ${closeNotes}
            </section>`;
    }

    function buildEmptyPack(locationId, monthId) {
        const hasGasStation = facilityTypesById()[locationId] === "c_store_gas";
        const loc = locations.find((l) => l.id === locationId);
        const booksFieldConfig = window.OplixBooksFieldConfig
            ? OplixBooksFieldConfig.configFromLocation(loc || { facilityType: hasGasStation ? "c_store_gas" : "c_store" })
            : null;
        const month = M().defaultMonthDoc();
        const daysById = {};
        return {
            locationId,
            monthId,
            month,
            daysById,
            aggregate: M().aggregateMonth(month, daysById, { hasGasStation, booksFieldConfig }),
        };
    }

    function analysisKey() {
        return `${state.locationId}:${state.monthId}`;
    }

    function prefetchHistoryMonths() {
        /* loaded progressively in loadHistorySections */
    }

    function renderPrimaryDashboard(primaryPack, extras) {
        if (!primaryPack?.aggregate) return;
        drillPack = {
            title: `${locName(primaryPack.locationId)} · ${monthLabel(primaryPack.monthId)}`,
            ...primaryPack,
        };

        reviewMonthDoc = primaryPack.month || null;

        let overviewHtml;
        try {
            overviewHtml = `
            <div class="bs-report">
                ${renderBooksReviewSection(primaryPack, extras?.apArReport)}
                ${renderMainDashboard(primaryPack.aggregate, drillPack.title)}
                ${extras?.apAr || ""}
                ${extras?.compare || ""}
                ${renderDailySalesExpenseSection(primaryPack)}
                ${renderCashReconciliationSection(primaryPack.aggregate)}
            </div>`;
        } catch (err) {
            console.error("[Oplix] Summary render failed:", err);
            overviewHtml = `<p class="app-error">${escapeHtml(err.message || "Could not render summary.")}</p>`;
        }

        const out = elById("analytics-output");
        if (!out) return;
        out.innerHTML = `
            <div id="${idFor("an-drill-mount")}" class="an-drill-mount" hidden></div>
            <div id="${idFor("an-overview-mount")}" class="an-overview-mount bs-overview">${overviewHtml}</div>`;
    }

    function renderHistorySections(accumulated, primaryPack, keyAtStart, loaded, total) {
        if (analysisKey() !== keyAtStart) return;

        const historyComplete = loaded >= total;
        const previousPacks = accumulated
            .slice()
            .sort((a, b) => b.monthId.localeCompare(a.monthId));
        const progressText = historyComplete
            ? ""
            : `Loading previous months… ${loaded} of ${total}`;

        renderPreviousMonthsMount(
            renderPreviousMonthsSection(
                previousPacks,
                state.locationId,
                state.monthId,
                progressText
            )
        );
        const prevMount = elById("an-previous-mount");
        if (prevMount) prevMount.hidden = !previousPacks.length && !progressText;

        const historyPacks = [primaryPack, ...previousPacks].sort((a, b) =>
            b.monthId.localeCompare(a.monthId)
        );
        const metricsHtml = Charts()
            ? Charts().renderKeyMetricsHistory(historyPacks, {
                  booksModel: M(),
                  monthLabel,
                  locationName: locName(state.locationId),
              })
            : "";

        renderKeyMetricsMount(
            historyComplete
                ? metricsHtml
                : `${metricsHtml}<p class="books-hint an-history-progress">Loading monthly detail… ${loaded} of ${total}</p>`
        );
        const keyMount = elById("an-key-metrics-mount");
        if (keyMount) keyMount.hidden = !metricsHtml && !historyComplete;
    }

    async function loadHistorySections(keyAtStart, primaryPack, lotteryForms) {
        const otherMonthIds = monthIdsForHistory(state.locationId, state.monthId, 12).filter(
            (id) => id !== state.monthId
        );
        if (!otherMonthIds.length) {
            renderPreviousMonthsMount("");
            renderKeyMetricsMount(
                Charts()
                    ? Charts().renderKeyMetricsHistory(
                          [applyLotteryFormsToPack(primaryPack, lotteryForms || [])],
                          {
                              booksModel: M(),
                              monthLabel,
                              locationName: locName(state.locationId),
                          }
                      )
                    : ""
            );
            return;
        }

        const accumulated = [];
        renderHistorySections(accumulated, primaryPack, keyAtStart, 0, otherMonthIds.length);

        for (let i = 0; i < otherMonthIds.length; i++) {
            if (analysisKey() !== keyAtStart) return;

            const monthId = otherMonthIds[i];
            let pack;
            try {
                [pack] = await Store().loadMonthsForCompare(
                    userId,
                    [state.locationId],
                    [monthId],
                    loadOptions()
                );
            } catch {
                pack = buildEmptyPack(state.locationId, monthId);
            }

            if (analysisKey() !== keyAtStart) return;
            accumulated.push(
                applyLotteryFormsToPack(pack || buildEmptyPack(state.locationId, monthId), lotteryForms)
            );
            renderHistorySections(accumulated, primaryPack, keyAtStart, i + 1, otherMonthIds.length);
        }
    }

    async function runAnalysis() {
        ensureStateMonth();
        const keyAtStart = analysisKey();
        const out = elById("analytics-output");
        if (!out) return;

        try {
            closeDrill();
            renderPrimaryDashboard(buildEmptyPack(state.locationId, state.monthId));
            lastRenderedKey = keyAtStart;
            renderPreviousMonthsMount("");
            renderKeyMetricsMount("");

            const [primaryPacks, lotteryForms, apArData] = await Promise.all([
                Store().loadMonthsForCompare(
                    userId,
                    [state.locationId],
                    [state.monthId],
                    loadOptions()
                ),
                fetchLotteryForms(state.locationId),
                loadApArData(),
            ]);
            if (analysisKey() !== keyAtStart) return;

            const primaryPack = applyLotteryFormsToPack(
                primaryPacks[0] || buildEmptyPack(state.locationId, state.monthId),
                lotteryForms
            );
            const compareHtml = await loadCompareHtml(primaryPack);
            if (analysisKey() !== keyAtStart) return;

            renderPrimaryDashboard(primaryPack, {
                apAr: renderApArSnapshot(apArData.snapshot),
                apArReport: apArData.report,
                compare: compareHtml,
            });
            refreshMonthStatusBadge();
            out.querySelector(".an-load-error")?.remove();

            loadHistorySections(keyAtStart, primaryPack, lotteryForms);
        } catch (err) {
            if (analysisKey() !== keyAtStart) return;
            console.error("[Oplix] Summary load failed:", err);
            renderPrimaryDashboard(buildEmptyPack(state.locationId, state.monthId));
            out.querySelector(".an-load-error")?.remove();
            out.insertAdjacentHTML(
                "beforeend",
                `<p class="app-error an-load-error">${escapeHtml(err.message || "Failed to load books summary.")}</p>`
            );
        }
    }

    function readControls() {
        const root = scopeRoot();
        if (!root) return;
        const locEl = root.querySelector(`#${locControlId()}`);
        if (locEl) state.locationId = locEl.value;
        const monthEl = root.querySelector(`#${monthControlId()}`);
        if (monthEl) state.monthId = monthEl.value;
    }

    function bindControls(panelEl) {
        const panel = panelEl || $("panel-analytics");
        if (!panel || panel.dataset.anBound) return;
        panel.dataset.anBound = "1";

        panel.addEventListener("click", (e) => {
            if (e.target.id === compareControlId()) {
                state.showCompare = !state.showCompare;
                render();
                runAnalysis();
                return;
            }
            const prevRow = e.target.closest("[data-an-prev-month]");
            if (prevRow) {
                state.monthId = prevRow.dataset.anPrevMonth;
                syncMonthSelect();
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
                return;
            }
            const openRecon = e.target.closest("[data-an-open-recon]");
            if (openRecon) {
                const dayId = openRecon.dataset.anOpenRecon;
                if (dayId && window.OplixDataInput?.openCashReconciliation) {
                    OplixDataInput.openCashReconciliation({
                        dayId,
                        monthId: state.monthId,
                        locationId: state.locationId,
                    });
                }
                return;
            }
            if (e.target.closest("[data-sales-open-summary]")) {
                openForLocation(state.locationId, state.monthId);
                return;
            }
        });

        panel.addEventListener("change", (e) => {
            if (e.target.id === locControlId() || e.target.id === monthControlId()) {
                readControls();
                runAnalysis();
            }
        });
    }

    function render() {
        const root = scopeRoot();
        if (!root) return;
        if (!locations.length) {
            root.innerHTML =
                '<p class="data-list-empty">Add a facility and enter data in Daily books first.</p>';
            return;
        }
        if (!state.locationId) state.locationId = embeddedLocationId || locations[0].id;
        ensureStateMonth();

        root.innerHTML = `${renderMonthPicker()}<div id="${idFor("analytics-output")}" class="an-output"></div><div id="${idFor("an-previous-mount")}" class="an-previous-mount" hidden></div><div id="${idFor("an-key-metrics-mount")}" class="an-key-metrics-mount" hidden></div>`;
    }

    function renderEmbedded(ctx) {
        return `
            <h2 class="loc-section-heading">Sales</h2>
            <p class="books-hint dir-hint">Monthly books totals from Daily books for <strong>${escapeHtml(ctx.locationName || "this facility")}</strong> — same data as sidebar <strong>Summary</strong>.</p>
            <p class="books-hint"><button type="button" class="books-link-btn" data-sales-open-summary>Open full Summary</button></p>
            <div id="sales-embedded-root" class="an-embedded-root"></div>`;
    }

    function bindEmbedded(container, ctx) {
        const slot = container.querySelector("#sales-embedded-root");
        if (!slot) return;
        slot.dataset.anBound = "";
        slot.innerHTML = "";
        init(ctx.userId, ctx.locations || locations, {
            rootId: "sales-embedded-root",
            embeddedLocationId: ctx.locationId,
            bindTarget: slot,
        });
        runAnalysis();
    }

    function openForLocation(locationId, monthId) {
        embeddedLocationId = null;
        currentRootId = "analytics-root";
        if (locationId) state.locationId = locationId;
        if (monthId) state.monthId = monthId;
        if (window.showDashboardPanel) {
            showDashboardPanel("analytics");
        }
        render();
        runAnalysis();
    }

    window.OplixAnalytics = {
        init(uid, locs, options) {
            userId = uid;
            locations = locs || [];
            currentRootId = options?.rootId || "analytics-root";
            embeddedLocationId = options?.embeddedLocationId || null;
            if (embeddedLocationId) state.locationId = embeddedLocationId;
            else if (locations.length && !state.locationId) state.locationId = locations[0].id;
            const bindTarget = options?.bindTarget || $("panel-analytics");
            if (bindTarget) {
                bindTarget.dataset.anBound = "";
                bindControls(bindTarget);
            }
            render();
        },
        onShow() {
            readControls();
            if (!userId || !locations.length) return;
            if (
                lastRenderedKey === analysisKey() &&
                elById("analytics-output")?.querySelector(".bs-report")
            ) {
                return;
            }
            runAnalysis();
        },
        invalidateCache() {
            lastRenderedKey = null;
        },
        resetToRoot() {
            closeDrill();
        },
        renderEmbedded,
        bindEmbedded,
        openForLocation,
    };
})();
