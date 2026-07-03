/**
 * Shared HTML sections for books reports and summary (recon, payouts, payroll).
 */
(function () {
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

    function num(v) {
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 0;
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

    function varianceClass(value) {
        const v = num(value);
        if (Math.abs(v) < 0.005) return "rpt-var--zero";
        return v < 0 ? "rpt-var--neg" : "rpt-var--pos";
    }

    function renderReconCategoryTable(category) {
        const rows = category?.dailyRows || [];
        if (!rows.length) return "";

        const showExpenses = num(category.totalCashExpenses) > 0;
        const tableRows = rows
            .map((row) => {
                const depositCell = row.deposit == null ? "—" : money(row.deposit);
                const varianceCell =
                    row.deposit != null ? money(row.depositVariance) : money(row.variance);
                const varVal = row.deposit != null ? row.depositVariance : row.variance;
                const label = row.status?.label || "—";
                const tone = row.status?.tone || "missing";
                return `
                    <tr>
                        <td>${escapeHtml(formatDayId(row.dayId))}</td>
                        <td class="home-cc-num">${money(row.countedTotal)}</td>
                        ${showExpenses ? `<td class="home-cc-num">${money(row.cashExpensesTotal || 0)}</td>` : ""}
                        <td class="home-cc-num">${money(row.expectedDeposit)}</td>
                        <td class="home-cc-num">${depositCell}</td>
                        <td class="home-cc-num ${varianceClass(varVal)}">${varianceCell}</td>
                        <td><span class="bs-cash-recon-badge bs-cash-recon-badge--${escapeHtml(tone)}">${escapeHtml(label)}</span></td>
                    </tr>`;
            })
            .join("");

        const summaryLine =
            category.daysWithExpected > 0
                ? `<p class="books-hint"><strong>${category.daysReconciled}</strong> of <strong>${category.daysWithExpected}</strong> days reconciled${
                      category.daysNeedingAttention > 0
                          ? ` · <span class="bs-cash-recon-attn">${category.daysNeedingAttention} need attention</span>`
                          : ""
                  }</p>`
                : "";

        return `
            <div class="rpt-recon-category">
                <h4 class="rpt-detail-subtitle">${escapeHtml(category.title)}</h4>
                ${category.subtitle ? `<p class="books-hint">${escapeHtml(category.subtitle)}</p>` : ""}
                ${summaryLine}
                <div class="books-cash-recon-totals bs-cash-recon-month-totals">
                    <span><em>Received</em> <strong>${money(category.totalCounted)}</strong></span>
                    ${showExpenses ? `<span><em>Cash expenses</em> <strong>${money(category.totalCashExpenses)}</strong></span>` : ""}
                    <span><em>Expected deposit</em> <strong>${money(category.totalExpectedDeposit)}</strong></span>
                    <span><em>Deposited</em> <strong>${money(category.totalDeposit)}</strong></span>
                    <span><em>Variance</em> <strong class="${varianceClass(category.totalDepositVariance || category.totalVariance)}">${money(category.totalDepositVariance || category.totalVariance)}</strong></span>
                </div>
                <div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table rpt-table">
                        <thead>
                            <tr>
                                <th>Day</th>
                                <th class="home-cc-num">Received</th>
                                ${showExpenses ? `<th class="home-cc-num">Expenses</th>` : ""}
                                <th class="home-cc-num">Expected</th>
                                <th class="home-cc-num">Deposited</th>
                                <th class="home-cc-num">Variance</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>${tableRows}</tbody>
                    </table>
                </div>
            </div>`;
    }

    function renderCashReconCategories(categories) {
        const list = categories || [];
        if (!list.length) {
            return `<p class="books-hint">No cash reconciliation entries this month. Enter data on <strong>Daily books → Cash reconciliation</strong>.</p>`;
        }
        return list
            .map((c) =>
                renderReconCategoryTable({
                    title: c.title,
                    subtitle: c.subtitle,
                    ...(c.data || {}),
                })
            )
            .join("");
    }

    function renderRegisterPayouts(payouts) {
        const rows = payouts || [];
        if (!rows.length) {
            return `<p class="books-hint">No register payouts recorded this month.</p>`;
        }
        return `
            <table class="home-cc-table rpt-table">
                <thead>
                    <tr>
                        <th>Payout</th>
                        <th class="home-cc-num">Amount</th>
                        <th>Notes</th>
                    </tr>
                </thead>
                <tbody>
                    ${rows
                        .map(
                            (r) => `
                    <tr>
                        <td>${escapeHtml(r.label)}</td>
                        <td class="home-cc-num">${money(r.amount)}</td>
                        <td>${r.trackOnly ? "Track only — reduces expected deposit" : "Reduces expected deposit"}</td>
                    </tr>`
                        )
                        .join("")}
                </tbody>
            </table>`;
    }

    function renderBooksPayroll(payrollRows, payrollTotal) {
        const rows = payrollRows || [];
        if (!rows.length && !payrollTotal) {
            return `<p class="books-hint">No payroll entered this month. Use <strong>Daily books → Utilities &amp; payroll</strong> or the Payroll tab.</p>`;
        }
        const hasHours = rows.some((r) => r.hours != null);
        return `
            <table class="home-cc-table rpt-table">
                <thead>
                    <tr>
                        <th>${hasHours ? "Employee" : "Period"}</th>
                        ${hasHours ? `<th class="home-cc-num">Hours</th><th class="home-cc-num">Rate</th>` : ""}
                        <th class="home-cc-num">Pay</th>
                    </tr>
                </thead>
                <tbody>
                    ${rows
                        .map(
                            (r) => `
                    <tr>
                        <td>${escapeHtml(r.label)}</td>
                        ${hasHours ? `<td class="home-cc-num">${r.hours != null ? r.hours : "—"}</td><td class="home-cc-num">${r.rate != null ? money(r.rate) : "—"}</td>` : ""}
                        <td class="home-cc-num">${money(r.amount)}</td>
                    </tr>`
                        )
                        .join("")}
                    ${
                        payrollTotal
                            ? `<tr class="an-total-row">
                        <td colspan="${hasHours ? 3 : 1}"><strong>Total</strong></td>
                        <td class="home-cc-num"><strong>${money(payrollTotal)}</strong></td>
                    </tr>`
                            : ""
                    }
                </tbody>
            </table>`;
    }

    function renderBooksSupplement(supplement, options) {
        if (!supplement) return "";
        const parts = [];
        const payouts = supplement.registerPayouts || [];
        const payroll = supplement.booksPayroll || [];
        const recon = supplement.cashReconCategories || [];

        if (options?.includeRecon !== false && recon.length) {
            parts.push(`
                <h4 class="rpt-detail-subtitle">Cash reconciliation</h4>
                ${renderCashReconCategories(recon)}`);
        }
        if (options?.includePayouts !== false && payouts.length) {
            parts.push(`
                <h4 class="rpt-detail-subtitle">Register payouts</h4>
                <p class="books-hint">Track-only payouts still reduce expected deposit for reconciliation.</p>
                ${renderRegisterPayouts(payouts)}`);
        }
        if (options?.includePayroll !== false && (payroll.length || options?.payrollTotal)) {
            parts.push(`
                <h4 class="rpt-detail-subtitle">Books payroll</h4>
                ${renderBooksPayroll(payroll, options?.payrollTotal)}`);
        }
        return parts.join("");
    }

    function renderPayablesTable(title, rows, nameCol) {
        if (!rows?.length) {
            return `<h4 class="rpt-detail-subtitle">${escapeHtml(title)}</h4><p class="books-hint">None.</p>`;
        }
        return `
            <h4 class="rpt-detail-subtitle">${escapeHtml(title)}</h4>
            <table class="home-cc-table rpt-table">
                <thead>
                    <tr>
                        <th>Facility</th>
                        <th>${escapeHtml(nameCol)}</th>
                        <th class="home-cc-num">Amount</th>
                        <th>Due</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    ${rows
                        .map(
                            (r) => `
                    <tr class="${r.overdue ? "rpt-row--overdue" : ""}">
                        <td>${escapeHtml(r.location)}</td>
                        <td>${escapeHtml(r.name)}</td>
                        <td class="home-cc-num">${money(r.amount)}</td>
                        <td>${escapeHtml(r.dueDate)}</td>
                        <td>${r.overdue ? '<span class="rpt-overdue">Overdue</span>' : "Open"}</td>
                    </tr>`
                        )
                        .join("")}
                </tbody>
            </table>`;
    }

    function renderPayablesReceivablesReport(report) {
        return `
            ${renderPayablesTable("Open payables", report.payablesOpen, "Pay to")}
            ${renderPayablesTable("Open receivables", report.receivablesOpen, "Receive from")}`;
    }

    function renderAllLocationsCashReconTable(report) {
        const rows = report.tableRows || [];
        if (!rows.length) {
            return `<p class="data-list-empty">No register cash reconciliation data for this month.</p>`;
        }
        const t = report.totals || {};
        return `
            <p class="books-hint">Register cash reconciliation rollup. Open a facility in Summary for day-by-day detail.</p>
            <table class="home-cc-table rpt-table">
                <thead>
                    <tr>
                        <th>Facility</th>
                        <th class="home-cc-num">Days reconciled</th>
                        <th class="home-cc-num">Need attention</th>
                        <th class="home-cc-num">Expected deposit</th>
                        <th class="home-cc-num">Deposited</th>
                        <th class="home-cc-num">Variance</th>
                        <th>Worst day</th>
                    </tr>
                </thead>
                <tbody>
                    ${rows
                        .map(
                            (r) => `
                    <tr>
                        <td>${escapeHtml(r.location)}</td>
                        <td class="home-cc-num">${r.daysReconciled} / ${r.daysWithExpected}</td>
                        <td class="home-cc-num">${r.daysNeedingAttention}</td>
                        <td class="home-cc-num">${money(r.totalExpectedDeposit)}</td>
                        <td class="home-cc-num">${money(r.totalDeposit)}</td>
                        <td class="home-cc-num ${varianceClass(r.totalDepositVariance)}">${money(r.totalDepositVariance)}</td>
                        <td>${r.worstDay ? `${escapeHtml(formatDayId(r.worstDay))} (${money(r.worstVariance)})` : "—"}</td>
                    </tr>`
                        )
                        .join("")}
                    <tr class="an-total-row">
                        <td><strong>Total</strong></td>
                        <td class="home-cc-num"><strong>${t.daysReconciled} / ${t.daysWithExpected}</strong></td>
                        <td class="home-cc-num"><strong>${t.daysNeedingAttention}</strong></td>
                        <td class="home-cc-num"><strong>${money(t.totalExpectedDeposit)}</strong></td>
                        <td class="home-cc-num"><strong>${money(t.totalDeposit)}</strong></td>
                        <td class="home-cc-num"><strong class="${varianceClass(t.totalDepositVariance)}">${money(t.totalDepositVariance)}</strong></td>
                        <td></td>
                    </tr>
                </tbody>
            </table>`;
    }

    function renderBooksPayrollPayoutsReport(report) {
        return (report.sections || [])
            .map((s) => {
                const supplement = {
                    registerPayouts: s.registerPayouts,
                    booksPayroll: s.booksPayroll,
                    cashReconCategories: [],
                };
                return `
                <section class="rpt-location-section">
                    <h3 class="rpt-location-title">${escapeHtml(s.locationName)}</h3>
                    ${renderBooksSupplement(supplement, {
                        includeRecon: false,
                        payrollTotal: s.payrollTotal,
                    })}
                </section>`;
            })
            .join("");
    }

    function renderPayablesReceivablesSnapshot(openPayables, openReceivables, overduePayables, overdueReceivables) {
        return `
            <section class="an-ap-ar-snapshot bs-panel">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">Payables &amp; receivables</h3>
                        <p class="bs-panel-sub">Open items from Daily books — manage on Payables and Receivables tabs.</p>
                    </div>
                </div>
                <div class="an-ap-ar-grid">
                    <div class="an-ap-ar-stat">
                        <span>Open payables</span>
                        <strong>${money(openPayables)}</strong>
                        ${overduePayables ? `<em class="rpt-overdue">${overduePayables} overdue</em>` : ""}
                    </div>
                    <div class="an-ap-ar-stat">
                        <span>Open receivables</span>
                        <strong>${money(openReceivables)}</strong>
                        ${overdueReceivables ? `<em class="rpt-overdue">${overdueReceivables} overdue</em>` : ""}
                    </div>
                </div>
            </section>`;
    }

    window.OplixReportsBooksSections = {
        renderBooksSupplement,
        renderCashReconCategories,
        renderPayablesReceivablesReport,
        renderAllLocationsCashReconTable,
        renderBooksPayrollPayoutsReport,
        renderPayablesReceivablesSnapshot,
        formatDayId,
        money,
    };
})();
