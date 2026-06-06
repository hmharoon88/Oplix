/**
 * Books summary — monthly totals and history from Daily books.
 */
(function () {
    const M = () => window.OplixBooksModel;
    const Store = () => window.OplixBooksStore;
    const Charts = () => window.OplixBooksSummaryCharts;

    let userId = null;
    let locations = [];
    let drillPack = null;
    let activeDrill = null;
    let lastRenderedKey = null;
    let state = {
        locationId: "",
        monthId: "",
    };

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

    function loadOptions() {
        return { facilityTypesById: facilityTypesById() };
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
        const monthEl = $("an-month");
        if (monthEl) monthEl.value = state.monthId;
        const locEl = $("an-loc");
        if (locEl) locEl.value = state.locationId;
    }

    function renderPreviousMonthsMount(html) {
        const mount = $("an-previous-mount");
        if (!mount) return;
        mount.innerHTML = html || "";
        mount.hidden = !html;
    }

    function renderKeyMetricsMount(html) {
        const mount = $("an-key-metrics-mount");
        if (!mount) return;
        mount.innerHTML = html || "";
        mount.hidden = !html;
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

    function renderMonthPicker() {
        const locOpts = locations
            .map(
                (l) =>
                    `<option value="${l.id}"${l.id === state.locationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            )
            .join("");
        const showFacility = locations.length > 1;

        return `
            <div class="bs-toolbar an-month-toolbar">
                <div class="bs-toolbar-fields">
                    ${
                        showFacility
                            ? `<label class="books-label">Facility
                        <select id="an-loc" class="books-select">${locOpts}</select>
                    </label>`
                            : ""
                    }
                    <label class="books-label">Month
                        <select id="an-month" class="books-select">${monthOptions(state.monthId)}</select>
                    </label>
                </div>
            </div>`;
    }

    function buildEmptyPack(locationId, monthId) {
        const hasGasStation = facilityTypesById()[locationId] === "c_store_gas";
        const month = M().defaultMonthDoc();
        const daysById = {};
        return {
            locationId,
            monthId,
            month,
            daysById,
            aggregate: M().aggregateMonth(month, daysById, { hasGasStation }),
        };
    }

    function analysisKey() {
        return `${state.locationId}:${state.monthId}`;
    }

    function prefetchHistoryMonths() {
        /* loaded progressively in loadHistorySections */
    }

    function renderPrimaryDashboard(primaryPack) {
        if (!primaryPack?.aggregate) return;
        drillPack = {
            title: `${locName(primaryPack.locationId)} · ${monthLabel(primaryPack.monthId)}`,
            ...primaryPack,
        };

        let overviewHtml;
        try {
            overviewHtml = `
            <div class="bs-report">
                ${renderMainDashboard(primaryPack.aggregate, drillPack.title)}
            </div>`;
        } catch (err) {
            console.error("[Oplix] Summary render failed:", err);
            overviewHtml = `<p class="app-error">${escapeHtml(err.message || "Could not render summary.")}</p>`;
        }

        const out = $("analytics-output");
        if (!out) return;
        out.innerHTML = `
            <div id="an-drill-mount" class="an-drill-mount" hidden></div>
            <div id="an-overview-mount" class="an-overview-mount bs-overview">${overviewHtml}</div>`;
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
        $("an-previous-mount").hidden = !previousPacks.length && !progressText;

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
        $("an-key-metrics-mount").hidden = !metricsHtml && !historyComplete;
    }

    async function loadHistorySections(keyAtStart, primaryPack) {
        const otherMonthIds = monthIdsForHistory(state.locationId, state.monthId, 12).filter(
            (id) => id !== state.monthId
        );
        if (!otherMonthIds.length) {
            renderPreviousMonthsMount("");
            renderKeyMetricsMount(
                Charts()
                    ? Charts().renderKeyMetricsHistory([primaryPack], {
                          booksModel: M(),
                          monthLabel,
                          locationName: locName(state.locationId),
                      })
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
            accumulated.push(pack || buildEmptyPack(state.locationId, monthId));
            renderHistorySections(accumulated, primaryPack, keyAtStart, i + 1, otherMonthIds.length);
        }
    }

    async function runAnalysis() {
        ensureStateMonth();
        const keyAtStart = analysisKey();
        const out = $("analytics-output");
        if (!out) return;

        try {
            closeDrill();
            renderPrimaryDashboard(buildEmptyPack(state.locationId, state.monthId));
            lastRenderedKey = keyAtStart;
            renderPreviousMonthsMount("");
            renderKeyMetricsMount("");

            const primaryPacks = await Store().loadMonthsForCompare(
                userId,
                [state.locationId],
                [state.monthId],
                loadOptions()
            );
            if (analysisKey() !== keyAtStart) return;

            const primaryPack =
                primaryPacks[0] || buildEmptyPack(state.locationId, state.monthId);
            renderPrimaryDashboard(primaryPack);
            out.querySelector(".an-load-error")?.remove();

            loadHistorySections(keyAtStart, primaryPack);
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
        const locEl = $("an-loc");
        if (locEl) state.locationId = locEl.value;
        const monthEl = $("an-month");
        if (monthEl) state.monthId = monthEl.value;
    }

    function bindControls() {
        const panel = $("panel-analytics");
        if (!panel || panel.dataset.anBound) return;
        panel.dataset.anBound = "1";

        panel.addEventListener("click", (e) => {
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
            }
        });

        panel.addEventListener("change", (e) => {
            if (e.target.id === "an-loc" || e.target.id === "an-month") {
                readControls();
                runAnalysis();
            }
        });
    }

    function render() {
        const root = $("analytics-root");
        if (!root) return;
        if (!locations.length) {
            root.innerHTML =
                '<p class="data-list-empty">Add a facility and enter data in Daily books first.</p>';
            return;
        }
        if (!state.locationId) state.locationId = locations[0].id;
        ensureStateMonth();

        root.innerHTML = `${renderMonthPicker()}<div id="analytics-output" class="an-output"></div><div id="an-previous-mount" class="an-previous-mount" hidden></div><div id="an-key-metrics-mount" class="an-key-metrics-mount" hidden></div>`;
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
            if (!userId || !locations.length) return;
            if (lastRenderedKey === analysisKey() && $("analytics-output")?.querySelector(".bs-report")) {
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
    };
})();
