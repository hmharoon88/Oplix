/**
 * Web Reports panel — generate, preview, CSV, and print/PDF.
 */
(function () {
    const RM = () => window.OplixReportsModel;
    const RS = () => window.OplixReportsStore;
    const BM = () => window.OplixBooksModel;
    const Charts = () => window.OplixBooksSummaryCharts;

    let userId = null;
    let locations = [];
    let state = {
        reportType: "monthly_books",
        locationId: "",
        locationScope: "one",
        monthId: BM().monthIdFromDate(new Date()),
        preset: "monthToDate",
        customStart: BM().monthIdFromDate(new Date()) + "-01",
        customEnd: new Date().toISOString().slice(0, 10),
        generated: null,
        loading: false,
        error: "",
        embeddedLocationId: null,
    };

    function $(sel, root) {
        return (root || document).querySelector(sel);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function money(v) {
        return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
            RM().num(v)
        );
    }

    function formatValue(v, format) {
        if (format === "number") {
            return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(RM().num(v));
        }
        return money(v);
    }

    function reportCellWithTrend(value, prevValue, opts) {
        const formatted =
            opts?.format === "number" ? formatValue(value, "number") : money(value);
        const cellClass = opts?.cellClass || "";
        if (prevValue == null || !Charts()?.renderCellTrend) {
            return `<td class="home-cc-num${cellClass ? ` ${cellClass}` : ""}">${formatted}</td>`;
        }
        const trend = Charts().renderCellTrend(value, prevValue, {
            invert: opts?.invert,
            format: opts?.format,
        });
        return Charts().renderTableValueCell(formatted, trend, cellClass);
    }

    function monthLabel(monthId) {
        const d = BM().parseMonthId(monthId);
        return d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
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

    function monthOptions(selected) {
        const opts = [];
        const now = new Date();
        for (let i = 0; i < 18; i++) {
            const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
            const id = BM().monthIdFromDate(d);
            opts.push(
                `<option value="${id}"${id === selected ? " selected" : ""}>${monthLabel(id)}</option>`
            );
        }
        return opts.join("");
    }

    function locName(id) {
        return locations.find((l) => l.id === id)?.name || "Facility";
    }

    function hasGas(locId) {
        const loc = locations.find((l) => l.id === locId);
        return loc?.facilityType === "c_store_gas";
    }

    function currentType() {
        return RM().REPORT_TYPES.find((t) => t.id === state.reportType) || RM().REPORT_TYPES[0];
    }

    function effectiveLocationId() {
        if (state.embeddedLocationId) return state.embeddedLocationId;
        return state.locationId;
    }

    function renderControls() {
        const type = currentType();
        const locOpts = locations
            .map(
                (l) =>
                    `<option value="${l.id}"${l.id === effectiveLocationId() ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            )
            .join("");

        const locField =
            type.needsLocation && !state.embeddedLocationId
                ? type.locationAllOption
                    ? `
                <label class="books-label">Facility
                    <select id="rpt-location-scope" class="books-select">
                        <option value="one"${state.locationScope === "one" ? " selected" : ""}>One facility</option>
                        <option value="all"${state.locationScope === "all" ? " selected" : ""}>All facilities</option>
                    </select>
                </label>
                ${
                    state.locationScope === "one"
                        ? `<label class="books-label">Location
                        <select id="rpt-location" class="books-select">${locOpts}</select>
                    </label>`
                        : ""
                }`
                    : `<label class="books-label">Location
                    <select id="rpt-location" class="books-select">${locOpts}</select>
                </label>`
                : "";

        const monthField = type.needsMonth
            ? `<label class="books-label">Month
                <select id="rpt-month" class="books-select">${monthOptions(state.monthId)}</select>
            </label>`
            : "";

        const rangeFields = type.needsRange
            ? `
            <label class="books-label">Period
                <select id="rpt-preset" class="books-select">
                    ${RM()
                        .PERIOD_PRESETS.map(
                            (p) =>
                                `<option value="${p.id}"${state.preset === p.id ? " selected" : ""}>${escapeHtml(p.label)}</option>`
                        )
                        .join("")}
                </select>
            </label>
            ${
                state.preset === "custom"
                    ? `
            <label class="books-label">Start
                <input type="date" id="rpt-start" class="books-input" value="${escapeHtml(state.customStart)}">
            </label>
            <label class="books-label">End
                <input type="date" id="rpt-end" class="books-input" value="${escapeHtml(state.customEnd)}">
            </label>`
                    : `<p class="books-hint rpt-range-hint">${escapeHtml(
                          RM().formatRange(
                              RM().intervalFromPreset(
                                  state.preset,
                                  new Date(state.customStart + "T12:00:00"),
                                  new Date(state.customEnd + "T12:00:00")
                              )
                          )
                      )}</p>`
            }`
            : "";

        return `
            <div class="rpt-toolbar bs-toolbar">
                <div class="bs-toolbar-fields">
                    <label class="books-label">Report
                        <select id="rpt-type" class="books-select">
                            ${RM()
                                .REPORT_TYPES.map(
                                    (t) =>
                                        `<option value="${t.id}"${t.id === state.reportType ? " selected" : ""}>${escapeHtml(t.label)}</option>`
                                )
                                .join("")}
                        </select>
                    </label>
                    ${locField}
                    ${monthField}
                    ${rangeFields}
                </div>
                <button type="button" class="btn books-save" id="rpt-generate"${state.loading ? " disabled" : ""}>
                    ${state.loading ? "Generating…" : "Generate report"}
                </button>
            </div>
            <p class="books-hint rpt-type-desc">${escapeHtml(type.desc)}</p>
            ${state.error ? `<p class="app-error rpt-error">${escapeHtml(state.error)}</p>` : ""}`;
    }

    function renderSummary(report) {
        if (!report.summary?.length) return "";
        return `
            <div class="rpt-summary">
                ${report.summary
                    .map(
                        (s) => `
                    <div class="rpt-summary-stat">
                        <span>${escapeHtml(s.label)}</span>
                        <strong>${formatValue(s.value, s.format)}</strong>
                    </div>`
                    )
                    .join("")}
            </div>`;
    }

    function renderMonthlyRow(r) {
        if (r.section) return `<tr class="rpt-section-row"><td colspan="2"></td></tr>`;
        const val =
            r.fmt === "number" ? formatValue(r.value, "number") : money(r.value);
        const labelCls = r.subRow ? "rpt-sub-row-label" : "";
        return `<tr><td class="${labelCls}">${escapeHtml(r.label)}</td><td class="home-cc-num">${val}</td></tr>`;
    }

    function renderExpenseDetailTable(expenseDetail, totalExpenses) {
        const rows = expenseDetail || [];
        if (!rows.length) {
            return `<p class="books-hint">No expense lines this month. Enter expenses on <strong>Daily books</strong> or monthly utilities / payroll.</p>`;
        }
        const lineTotal = rows.reduce((s, r) => s + RM().num(r.amount), 0);
        return `
            <div class="home-card home-cc-table-wrap an-drill-table-scroll">
                <table class="home-cc-table rpt-table">
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
                                (r) => `
                        <tr>
                            <td>${escapeHtml(r.category)}</td>
                            <td>${escapeHtml(r.dayId ? formatDayId(r.dayId) : "—")}</td>
                            <td>${escapeHtml(r.description)}</td>
                            <td class="home-cc-num">${money(r.amount)}</td>
                        </tr>`
                            )
                            .join("")}
                        <tr class="an-total-row">
                            <td colspan="3"><strong>Line items total</strong></td>
                            <td class="home-cc-num"><strong>${money(lineTotal)}</strong></td>
                        </tr>
                    </tbody>
                </table>
            </div>
            ${
                totalExpenses != null
                    ? `<p class="books-hint">Total expenses (${money(totalExpenses)}) includes utilities, payroll, sales tax, and accountant fees in the monthly breakdown above.</p>`
                    : ""
            }`;
    }

    function renderMonthlyBooksBody(report) {
        return `
            <table class="home-cc-table rpt-table">
                <thead><tr><th>Line item</th><th class="home-cc-num">Amount</th></tr></thead>
                <tbody>
                    ${report.rows.map((r) => renderMonthlyRow(r)).join("")}
                </tbody>
            </table>
            ${
                report.expenseDetail?.length
                    ? `<h4 class="rpt-detail-subtitle">Expense detail</h4>${renderExpenseDetailTable(report.expenseDetail, report.totalExpenses)}`
                    : ""
            }`;
    }

    function renderAllLocationsBody(report) {
        const salesHeader = report.salesHeader || (report.anyGas ? "Merch / sales" : "Sales");
        const prevHint = report.prevMonthLabel
            ? ` Green ▲ / red ▼ show change vs ${escapeHtml(report.prevMonthLabel)} (amount on the line; hover for %).`
            : "";
        const detailRow = (r) => {
            const p = r.prev;
            return `
                        <tr>
                            <td>${escapeHtml(r.location)}</td>
                            ${reportCellWithTrend(r.sales, p?.sales)}
                            ${reportCellWithTrend(r.registerCard, p?.registerCard)}
                            ${reportCellWithTrend(r.registerCash, p?.registerCash)}
                            ${reportCellWithTrend(r.creditCard, p?.creditCard)}
                            ${reportCellWithTrend(r.fuel, p?.fuel)}
                            ${reportCellWithTrend(r.fuelGallons, p?.fuelGallons, { format: "number" })}
                            ${reportCellWithTrend(r.expenses, p?.expenses, { invert: true })}
                            ${reportCellWithTrend(r.net, p?.net, {
                                cellClass: r.net >= 0 ? "rpt-net pos" : "rpt-net neg",
                            })}
                        </tr>`;
        };
        const t = report.totals;
        const pt = report.prevTotals;
        return `
            <p class="books-hint rpt-all-locs-hint"><strong>${escapeHtml(salesHeader)}</strong> and <strong>Net</strong> use the official books totals. Register card, cash sale, credit card, fuel, and gallons are shown for reference — they are not added again to ${escapeHtml(salesHeader.toLowerCase())}.${prevHint}</p>
            <table class="home-cc-table rpt-table rpt-table--trends">
                <thead>
                    <tr>
                        <th>Facility</th>
                        <th class="home-cc-num">${escapeHtml(salesHeader)}</th>
                        <th class="home-cc-num">Register card</th>
                        <th class="home-cc-num">Cash sale</th>
                        <th class="home-cc-num">Credit card</th>
                        <th class="home-cc-num">Fuel ($)</th>
                        <th class="home-cc-num">Gallons</th>
                        <th class="home-cc-num">Expenses</th>
                        <th class="home-cc-num">Net</th>
                    </tr>
                </thead>
                <tbody>
                    ${report.tableRows.map(detailRow).join("")}
                    <tr class="an-total-row">
                        <td><strong>Total</strong></td>
                        ${reportCellWithTrend(t.sales, pt?.sales)}
                        ${reportCellWithTrend(t.registerCard, pt?.registerCard)}
                        ${reportCellWithTrend(t.registerCash, pt?.registerCash)}
                        ${reportCellWithTrend(t.creditCard, pt?.creditCard)}
                        ${reportCellWithTrend(t.fuel, pt?.fuel)}
                        ${reportCellWithTrend(t.fuelGallons, pt?.fuelGallons, { format: "number" })}
                        ${reportCellWithTrend(t.expenses, pt?.expenses, { invert: true })}
                        ${reportCellWithTrend(t.net, pt?.net, {
                            cellClass: t.net >= 0 ? "rpt-net pos" : "rpt-net neg",
                        })}
                    </tr>
                </tbody>
            </table>`;
    }

    function renderAllLocationsCompareBody(report) {
        if (!report.tableRows?.length) {
            return `<p class="data-list-empty">No expense or utility data for this month.</p>`;
        }
        const locs = report.locations || [];
        return `
            <p class="books-hint rpt-compare-hint">Each column is a facility. Compare electric, cash, checks, payroll, and more across locations.</p>
            <div class="rpt-compare-scroll home-card home-cc-table-wrap">
                <table class="home-cc-table rpt-table rpt-compare-table">
                    <thead>
                        <tr>
                            <th class="rpt-compare-sticky">Line item</th>
                            ${locs.map((l) => `<th class="home-cc-num rpt-compare-loc">${escapeHtml(l.name)}</th>`).join("")}
                            <th class="home-cc-num rpt-compare-total-col">Total</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${report.tableRows
                            .map((row) => {
                                const groupRow = row.groupHeader
                                    ? `<tr class="rpt-compare-group-row"><td class="rpt-compare-sticky" colspan="${locs.length + 2}">${escapeHtml(report.groupLabels[row.groupHeader] || row.groupHeader)}</td></tr>`
                                    : "";
                                const rowCls = row.emphasis ? " an-total-row" : "";
                                const cells = row.values
                                    .map((v) => {
                                        const empty = v.value === 0 ? " rpt-compare-zero" : "";
                                        return `<td class="home-cc-num${empty}">${v.value === 0 ? "—" : money(v.value)}</td>`;
                                    })
                                    .join("");
                                const totalCell =
                                    row.total === 0
                                        ? `<td class="home-cc-num rpt-compare-total-col rpt-compare-zero">—</td>`
                                        : `<td class="home-cc-num rpt-compare-total-col"><strong>${money(row.total)}</strong></td>`;
                                return `${groupRow}
                                <tr class="${rowCls.trim()}">
                                    <td class="rpt-compare-sticky">${row.emphasis ? `<strong>${escapeHtml(row.label)}</strong>` : escapeHtml(row.label)}</td>
                                    ${cells}
                                    ${totalCell}
                                </tr>`;
                            })
                            .join("")}
                    </tbody>
                </table>
            </div>`;
    }

    function renderAllLocationsDetailBody(report) {
        if (!report.locationSections.length) {
            return `<p class="data-list-empty">No facilities to report.</p>`;
        }

        return report.locationSections
            .map((section) => {
                const hasGas = section.hasGas;
                const monthlyTable = `
                    <table class="home-cc-table rpt-table rpt-detail-monthly">
                        <thead><tr><th>Line item</th><th class="home-cc-num">Amount</th></tr></thead>
                        <tbody>
                            ${section.monthlyRows.map((r) => renderMonthlyRow(r)).join("")}
                        </tbody>
                    </table>`;

                const expenseBlock = `
                    <h4 class="rpt-detail-subtitle">Expense detail</h4>
                    ${renderExpenseDetailTable(section.expenseDetail, section.totalExpenses)}`;

                const dailyTotals = section.dailyTotals;
                const daysWithData = dailyTotals.daysWithData;
                const monthTotals = hasGas
                    ? `<span><em>Merch</em> <strong>${money(dailyTotals.merchSale)}</strong></span>
                       <span><em>Fuel (gal)</em> <strong>${formatValue(dailyTotals.fuelGallons, "number")}</strong></span>
                       <span><em>Fuel ($)</em> <strong>${money(dailyTotals.fuelDollars)}</strong></span>
                       <span><em>Credit card</em> <strong>${money(dailyTotals.creditCard)}</strong></span>`
                    : `<span><em>Sales</em> <strong>${money(dailyTotals.sales)}</strong></span>`;
                const gasHead = hasGas
                    ? `<th class="home-cc-num">Merch</th>
                       <th class="home-cc-num">Fuel (gal)</th>
                       <th class="home-cc-num">Fuel ($)</th>
                       <th class="home-cc-num">Credit card</th>`
                    : "";
                const salesColHead = hasGas ? "" : `<th class="home-cc-num">Sales</th>`;
                const dailyBlock = daysWithData
                    ? `
                    <div class="books-cash-recon-totals an-daily-month-totals rpt-detail-daily-totals">
                        ${monthTotals}
                        <span><em>Expenses</em> <strong>${money(dailyTotals.expenses)}</strong></span>
                        <span><em>Net</em> <strong class="${dailyTotals.net >= 0 ? "pos" : "neg"}">${money(dailyTotals.net)}</strong></span>
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
                            <tbody>
                                ${section.dailyRows
                                    .map((row) => {
                                        const emptyCls = row.hasData ? "" : " an-daily-row--empty";
                                        const cell = (v) => (row.hasData ? money(v) : "—");
                                        const numCell = (v) =>
                                            row.hasData ? formatValue(v, "number") : "—";
                                        const extraGas = hasGas
                                            ? `<td class="home-cc-num">${cell(row.merchSale)}</td>
                                               <td class="home-cc-num">${numCell(row.fuelGallons)}</td>
                                               <td class="home-cc-num">${cell(row.fuelDollars)}</td>
                                               <td class="home-cc-num">${cell(row.creditCard)}</td>`
                                            : "";
                                        const salesCell = hasGas
                                            ? ""
                                            : `<td class="home-cc-num">${cell(row.sales)}</td>`;
                                        return `
                                        <tr class="an-daily-row${emptyCls}">
                                            <td class="an-daily-day-col">${escapeHtml(formatDayId(row.dayId))}</td>
                                            ${extraGas}
                                            ${salesCell}
                                            <td class="home-cc-num">${cell(row.cashExpense)}</td>
                                            <td class="home-cc-num">${cell(row.checksAch)}</td>
                                            <td class="home-cc-num">${cell(row.otherExpense)}</td>
                                            <td class="home-cc-num">${cell(row.expenses)}</td>
                                            <td class="home-cc-num an-daily-net${row.net >= 0 ? " pos" : " neg"}">${cell(row.net)}</td>
                                        </tr>`;
                                    })
                                    .join("")}
                            </tbody>
                        </table>
                    </div>
                    <p class="books-hint an-daily-footnote">Daily columns are cash, checks, and other from the Daily sheet only. Utilities (electric, water, etc.), payroll, sales tax, and accountant are in the monthly breakdown and expense detail above — not repeated per day.</p>`
                    : `<p class="books-hint">No daily entries this month. Enter data on <strong>Daily books → Daily sheet</strong>.</p>`;

                return `
                    <section class="rpt-location-section">
                        <h3 class="rpt-location-title">${escapeHtml(section.locationName)}</h3>
                        <h4 class="rpt-detail-subtitle">Monthly breakdown</h4>
                        ${monthlyTable}
                        ${expenseBlock}
                        <h4 class="rpt-detail-subtitle">Daily sales &amp; expenses</h4>
                        ${dailyBlock}
                    </section>`;
            })
            .join("");
    }

    function renderComplianceBody(report) {
        return `
            <table class="home-cc-table rpt-table">
                <thead>
                    <tr>
                        <th>Facility</th>
                        <th>Type</th>
                        <th>Name</th>
                        <th>Expires</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    ${report.tableRows
                        .map(
                            (r) => `
                        <tr class="${r.statusClass.includes("expired") ? "comp-table-row--expired" : r.statusClass.includes("expiring") ? "comp-table-row--expiring" : ""}">
                            <td>${escapeHtml(r.facility)}</td>
                            <td>${escapeHtml(r.type)}</td>
                            <td><strong>${escapeHtml(r.name)}</strong></td>
                            <td>${escapeHtml(r.expiry)}${r.hint ? `<span class="comp-expiry-hint">${escapeHtml(r.hint)}</span>` : ""}</td>
                            <td><span class="comp-status-pill ${r.statusClass}">${escapeHtml(r.status)}</span></td>
                        </tr>`
                        )
                        .join("")}
                </tbody>
            </table>`;
    }

    function renderShiftTableBody(report, columns) {
        if (!report.tableRows.length) {
            return `<p class="data-list-empty">No rows in this period. Try a wider date range or enter data in the app.</p>`;
        }
        return `
            <table class="home-cc-table rpt-table">
                <thead><tr>${columns.map((c) => `<th${c.num ? ' class="home-cc-num"' : ""}>${escapeHtml(c.label)}</th>`).join("")}</tr></thead>
                <tbody>
                    ${report.tableRows
                        .map((row) => {
                            return `<tr>${columns
                                .map((c) => {
                                    const v = row[c.key];
                                    const text =
                                        c.money && v != null ? money(v) : v == null ? "—" : escapeHtml(String(v));
                                    return `<td${c.num ? ' class="home-cc-num"' : ""}>${text}</td>`;
                                })
                                .join("")}</tr>`;
                        })
                        .join("")}
                </tbody>
            </table>`;
    }

    function renderReportBody(report) {
        switch (report.type) {
            case "monthly_books":
                return renderMonthlyBooksBody(report);
            case "all_locations_books":
                return renderAllLocationsBody(report);
            case "all_locations_detail":
                return renderAllLocationsDetailBody(report);
            case "all_locations_compare":
                return renderAllLocationsCompareBody(report);
            case "compliance":
                return renderComplianceBody(report);
            case "lottery":
                return renderShiftTableBody(report, [
                    { label: "Date", key: "date" },
                    { label: "Terminal", key: "terminal" },
                    { label: "Employee", key: "employee" },
                    { label: "Sold", key: "sold", num: true, money: true },
                    { label: "Expected", key: "expected", num: true, money: true },
                    { label: "Actual", key: "actual", num: true, money: true },
                    { label: "O/S", key: "overShort", num: true, money: true },
                ]);
            case "payroll":
                return renderShiftTableBody(report, [
                    { label: "Employee", key: "employee" },
                    { label: "Rate", key: "rate", num: true, money: true },
                    { label: "Hours", key: "hours", num: true },
                    { label: "Pay", key: "pay", num: true, money: true },
                    { label: "Shifts", key: "shifts", num: true },
                ]);
            case "register":
                return renderShiftTableBody(report, [
                    { label: "Clock out", key: "date" },
                    { label: "Employee", key: "employee" },
                    { label: "Sales", key: "sales", num: true, money: true },
                    { label: "Expenses", key: "expenses", num: true, money: true },
                    { label: "O/S", key: "overShort", num: true, money: true },
                ]);
            default:
                return "";
        }
    }

    function renderPreview() {
        const report = state.generated;
        if (!report) {
            return `<p class="data-list-empty rpt-empty">Choose a report type and click <strong>Generate report</strong>.</p>`;
        }
        return `
            <section class="rpt-preview home-card" id="rpt-preview">
                <header class="rpt-preview-head">
                    <div>
                        <h2 class="rpt-preview-title">${escapeHtml(report.title)}</h2>
                        <p class="rpt-preview-meta">${escapeHtml(report.headline)}${report.subhead ? ` · ${escapeHtml(report.subhead)}` : ""}</p>
                    </div>
                    <div class="rpt-export-actions">
                        <button type="button" class="btn btn-nav-outline" id="rpt-csv">Download CSV</button>
                        <button type="button" class="btn" id="rpt-print">Print / PDF</button>
                    </div>
                </header>
                ${renderSummary(report)}
                <div class="rpt-preview-body">${renderReportBody(report)}</div>
                <p class="books-hint rpt-footer-hint">Use <strong>Print / PDF</strong> and choose “Save as PDF” in the print dialog.</p>
            </section>`;
    }

    function render(rootId) {
        const root = document.getElementById(rootId || "reports-root");
        if (!root) return;

        if (!locations.length) {
            root.innerHTML =
                '<p class="data-list-empty">Add a facility first, then generate reports from Daily books and compliance data.</p>';
            return;
        }

        root.innerHTML = `
            <div class="rpt-panel" data-rpt-panel>
                ${renderControls()}
                ${renderPreview()}
            </div>`;
    }

    function readControls(root) {
        const typeEl = $("#rpt-type", root);
        if (typeEl) state.reportType = typeEl.value;
        const scopeEl = $("#rpt-location-scope", root);
        if (scopeEl) state.locationScope = scopeEl.value;
        const locEl = $("#rpt-location", root);
        if (locEl) state.locationId = locEl.value;
        const monthEl = $("#rpt-month", root);
        if (monthEl) state.monthId = monthEl.value;
        const presetEl = $("#rpt-preset", root);
        if (presetEl) state.preset = presetEl.value;
        const startEl = $("#rpt-start", root);
        if (startEl) state.customStart = startEl.value;
        const endEl = $("#rpt-end", root);
        if (endEl) state.customEnd = endEl.value;
    }

    async function generateReport() {
        state.error = "";
        state.loading = true;
        render();
        try {
            const type = currentType();
            const locId = effectiveLocationId();
            let report;

            if (state.reportType === "monthly_books") {
                if (!locId) throw new Error("Select a location.");
                const agg = await RS().loadBooksAggregate(userId, locId, state.monthId, hasGas(locId));
                report = RM().buildMonthlyBooksReport(agg, {
                    locationName: locName(locId),
                    monthLabel: monthLabel(state.monthId),
                    monthId: state.monthId,
                });
            } else if (state.reportType === "all_locations_books") {
                const prevMonthId = RM().prevMonthIdFrom(state.monthId);
                const [packs, prevPacks] = await Promise.all([
                    RS().loadAllLocationsBooks(userId, locations, state.monthId),
                    prevMonthId
                        ? RS().loadAllLocationsBooks(userId, locations, prevMonthId)
                        : Promise.resolve([]),
                ]);
                report = RM().buildAllLocationsBooksReport(packs, {
                    monthLabel: monthLabel(state.monthId),
                    monthId: state.monthId,
                    prevMonthLabel: prevMonthId ? monthLabel(prevMonthId) : null,
                }, prevPacks);
            } else if (state.reportType === "all_locations_detail") {
                const packs = await RS().loadAllLocationsBooksDetail(
                    userId,
                    locations,
                    state.monthId
                );
                report = RM().buildAllLocationsDetailReport(packs, {
                    monthLabel: monthLabel(state.monthId),
                    monthId: state.monthId,
                });
            } else if (state.reportType === "all_locations_compare") {
                const packs = await RS().loadAllLocationsBooks(userId, locations, state.monthId);
                report = RM().buildAllLocationsCompareReport(packs, {
                    monthLabel: monthLabel(state.monthId),
                    monthId: state.monthId,
                });
            } else if (state.reportType === "compliance") {
                const all =
                    state.locationScope === "all" && !state.embeddedLocationId;
                const items = all
                    ? await RS().loadComplianceAll(userId, locations)
                    : await RS().loadCompliance(userId, locId);
                if (!all && !items.length && !locId) throw new Error("Select a location.");
                report = RM().buildComplianceReport(items, {
                    locationName: all ? null : locName(locId),
                });
            } else {
                if (!locId) throw new Error("Select a location.");
                const interval = RM().intervalFromPreset(
                    state.preset,
                    new Date(state.customStart + "T12:00:00"),
                    new Date(state.customEnd + "T12:00:00")
                );
                if (RM().spanExceedsLimit(interval)) {
                    throw new Error(`Date range cannot exceed ${RM().MAX_SPAN_DAYS} days.`);
                }
                const { shifts, employees, lotteryForms } = await RS().loadShiftReportData(
                    userId,
                    locId
                );
                const meta = { locationName: locName(locId) };
                if (state.reportType === "lottery") {
                    report = RM().buildLotteryReport(
                        lotteryForms,
                        shifts,
                        employees,
                        interval,
                        meta
                    );
                } else if (state.reportType === "payroll") {
                    report = RM().buildPayrollReport(shifts, employees, interval, meta);
                } else {
                    report = RM().buildRegisterReport(shifts, employees, interval, meta);
                }
            }

            state.generated = report;
        } catch (err) {
            state.error = err.message || "Failed to generate report.";
            state.generated = null;
        } finally {
            state.loading = false;
            render();
        }
    }

    function csvEscape(cell) {
        const s = String(cell == null ? "" : cell);
        if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
        return s;
    }

    function downloadCsv(report) {
        const rows = report.csvRows || [];
        const csv = rows.map((r) => r.map(csvEscape).join(",")).join("\n");
        const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
        const a = document.createElement("a");
        const slug = report.type.replace(/_/g, "-");
        a.href = URL.createObjectURL(blob);
        a.download = `oplix-${slug}-${new Date().toISOString().slice(0, 10)}.csv`;
        a.click();
        URL.revokeObjectURL(a.href);
    }

    function printReport(report) {
        const body = renderReportBody(report);
        const summary = renderSummary(report);
        const html = `
            <div class="rpt-print-doc">
                <h1>${escapeHtml(report.title)}</h1>
                <p class="rpt-print-meta">${escapeHtml(report.headline)}${report.subhead ? ` · ${escapeHtml(report.subhead)}` : ""}</p>
                <p class="rpt-print-meta">Generated ${escapeHtml(new Date().toLocaleString("en-US"))}</p>
                ${summary}
                ${body}
            </div>`;
        const w = window.open("", "_blank");
        if (!w) {
            alert("Allow pop-ups to print or save as PDF.");
            return;
        }
        w.document.write(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${escapeHtml(report.title)}</title>
            <style>
                body { font-family: Inter, system-ui, sans-serif; padding: 24px; color: #0f172a; }
                h1 { font-size: 1.25rem; margin: 0 0 8px; }
                .rpt-print-meta { color: #64748b; font-size: 0.85rem; margin: 0 0 16px; }
                .rpt-summary { display: flex; gap: 24px; margin-bottom: 20px; }
                .rpt-summary-stat span { display: block; font-size: 0.7rem; text-transform: uppercase; color: #64748b; }
                .rpt-summary-stat strong { font-size: 1.1rem; }
                table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
                th, td { border: 1px solid #e2e8f0; padding: 8px 10px; text-align: left; }
                th { background: #f8fafc; }
                .home-cc-num { text-align: right; }
                .an-total-row td { background: #f8fafc; font-weight: 600; }
                @media print { body { padding: 0; } }
            </style></head><body>${html}</body></html>`);
        w.document.close();
        w.focus();
        setTimeout(() => w.print(), 300);
    }

    function bind(root) {
        if (!root || root.dataset.rptBound) return;
        root.dataset.rptBound = "1";

        root.addEventListener("change", (e) => {
            if (!e.target.closest("[data-rpt-panel]")) return;
            readControls(root);
            if (e.target.id === "rpt-type") {
                state.generated = null;
                state.error = "";
            }
            render();
        });

        root.addEventListener("click", (e) => {
            if (e.target.id === "rpt-generate") {
                readControls(root);
                generateReport();
                return;
            }
            if (e.target.id === "rpt-csv" && state.generated) {
                downloadCsv(state.generated);
                return;
            }
            if (e.target.id === "rpt-print" && state.generated) {
                printReport(state.generated);
            }
        });
    }

    function init(uid, locs, options) {
        userId = uid;
        locations = locs || [];
        state.embeddedLocationId = options?.embeddedLocationId || null;
        if (locations.length && !state.locationId) state.locationId = locations[0].id;
        if (state.embeddedLocationId) state.locationId = state.embeddedLocationId;
        const rootId = options?.rootId || "reports-root";
        const root = document.getElementById(rootId);
        render(rootId);
        if (root) {
            root.dataset.rptBound = "";
            bind(root);
        }
    }

    function renderEmbedded(ctx) {
        return `
            <h2 class="loc-section-heading">Reports</h2>
            <p class="books-hint dir-hint">Generate exportable reports for <strong>${escapeHtml(ctx.locationName || "this facility")}</strong>.</p>
            <div id="rpt-embedded-root" data-rpt-embedded></div>`;
    }

    function bindEmbedded(container, ctx) {
        const slot = container.querySelector("#rpt-embedded-root");
        if (!slot) return;
        slot.dataset.rptEmbeddedBound = "1";
        slot.innerHTML = "";
        const locs = ctx.locations || locations;
        init(ctx.userId, locs, {
            rootId: "rpt-embedded-root",
            embeddedLocationId: ctx.locationId,
        });
    }

    window.OplixReports = {
        init,
        onShow() {
            if (userId) render();
        },
        resetToRoot() {
            state.generated = null;
            state.error = "";
            state.loading = false;
            render();
        },
        renderEmbedded,
        bindEmbedded,
    };
})();
