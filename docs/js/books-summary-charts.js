/**
 * Books summary charts — pie + bar pairs (reference layout), CSS + SVG.
 */
(function () {
    const COLOR_CARD = "#2563eb";
    const COLOR_CASH = "#f5c542";

    const COLORS = [
        "#2563eb",
        "#f5c542",
        "#f06b6b",
        "#5ec9b4",
        "#3cb878",
        "#e84c8a",
        "#9b7ede",
        "#6ec4f2",
        "#a67c52",
        "#f97316",
        "#14b8a6",
        "#8b5cf6",
    ];

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

    function filterSlices(slices) {
        return (slices || []).filter((s) => num(s.amount) > 0);
    }

    function shortLabel(label) {
        const s = String(label || "");
        const map = {
            "Merch sale (store)": "Merch",
            "Credit card (pump)": "Credit card",
            "Register card": "Reg card",
            "Credit card": "Credit card",
            "Fuel sales ($)": "Fuel",
            "Register — card": "Reg card",
            "Register — cash": "Reg cash",
            "Checks / ACH": "Check Exp",
            "Cash expense": "Cash exp.",
        };
        if (map[s]) return map[s];
        if (s.length <= 14) return s;
        return s.replace(/\s+\(.+\)$/, "").slice(0, 14);
    }

    function textColorOn(bgHex) {
        const hex = bgHex.replace("#", "");
        const r = parseInt(hex.slice(0, 2), 16);
        const g = parseInt(hex.slice(2, 4), 16);
        const b = parseInt(hex.slice(4, 6), 16);
        const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
        return lum > 0.62 ? "#1e293b" : "#ffffff";
    }

    function niceAxisMax(maxVal) {
        if (maxVal <= 0) return 1000;
        const mag = Math.pow(10, Math.floor(Math.log10(maxVal)));
        const norm = maxVal / mag;
        let nice = mag;
        if (norm <= 1) nice = mag;
        else if (norm <= 2) nice = 2 * mag;
        else if (norm <= 5) nice = 5 * mag;
        else nice = 10 * mag;
        return nice;
    }

    function formatAxisTick(val) {
        const v = num(val);
        if (v >= 1_000_000) return `${(v / 1_000_000).toFixed(0)}M`;
        if (v >= 1000) return `${(v / 1000).toFixed(0)}K`;
        return String(Math.round(v));
    }

    function assignColors(items) {
        return items.map((s, i) => ({
            ...s,
            color: s.color || COLORS[i % COLORS.length],
        }));
    }

    function buildPieGeometry(items, cx, cy, r) {
        const total = items.reduce((s, x) => s + num(x.amount), 0) || 1;
        let angle = -Math.PI / 2;
        return items.map((item) => {
            const slice = (num(item.amount) / total) * Math.PI * 2;
            const start = angle;
            const end = angle + slice;
            angle = end;
            const x1 = cx + r * Math.cos(start);
            const y1 = cy + r * Math.sin(start);
            const x2 = cx + r * Math.cos(end);
            const y2 = cy + r * Math.sin(end);
            const large = slice > Math.PI ? 1 : 0;
            const d = `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} Z`;
            const mid = (start + end) / 2;
            const lx = cx + r * 0.58 * Math.cos(mid);
            const ly = cy + r * 0.58 * Math.sin(mid);
            const label = shortLabel(item.label);
            return {
                d,
                color: item.color,
                label,
                lx,
                ly,
                fill: textColorOn(item.color),
                showLabel: slice > 0.08,
            };
        });
    }

    function renderSvgPie(items) {
        const w = 380;
        const h = 380;
        const cx = w / 2;
        const cy = h / 2;
        const r = 155;
        const slices = buildPieGeometry(items, cx, cy, r);
        return `
            <svg class="bs-ref-svg bs-ref-pie" viewBox="0 0 ${w} ${h}" aria-hidden="true">
                ${slices
                    .map(
                        (s) => `
                    <path d="${s.d}" fill="${s.color}" stroke="#fff" stroke-width="2"/>
                    ${
                        s.showLabel
                            ? `<text x="${s.lx}" y="${s.ly}" class="bs-pie-slice-label" fill="${s.fill}" text-anchor="middle" dominant-baseline="middle">${escapeHtml(s.label)}</text>`
                            : ""
                    }`
                    )
                    .join("")}
            </svg>`;
    }

    const COLOR_FUEL = "#f59e0b";

    function cardCashSlices(agg, booksModel) {
        const M = booksModel || window.OplixBooksModel;
        if (!M || !agg) return [];
        if (agg.hasGasStation) {
            return assignColors(
                M.gasSalesSlicesFromAggregate(agg).map((s, i) => ({
                    ...s,
                    color: [COLOR_CARD, "#6366f1", "#8b5cf6", COLOR_FUEL][i % 4],
                }))
            );
        }
        const b = M.cardCashBreakdownFromAggregate(agg);
        return assignColors([
            { label: "Card", amount: num(b.card), color: COLOR_CARD },
            { label: "Cash", amount: num(b.cash), color: COLOR_CASH },
        ]);
    }

    function cardCashHint(agg) {
        if (agg && agg.hasGasStation) {
            return "Merch sale, credit card, and fuel ($) are tracked separately — not combined into each other.";
        }
        return "Total sales from register card and cash (both registers, both shifts). Pulltab, lottery, wind, and keno are track only.";
    }

    /** Grouped vertical bars: each row is a location or month with Card + Cash bars. */
    function renderSvgGroupedCardCash(entries) {
        const rows = (entries || []).filter((e) => num(e.card) > 0 || num(e.cash) > 0);
        if (!rows.length) return "";

        const w = Math.max(480, rows.length * 120);
        const h = 380;
        const padL = 52;
        const padR = 20;
        const padT = 28;
        const padB = 88;
        const chartW = w - padL - padR;
        const chartH = h - padT - padB;
        const maxVal = niceAxisMax(
            Math.max(...rows.flatMap((r) => [num(r.card), num(r.cash)]), 1)
        );
        const ticks = 5;
        const groupW = chartW / rows.length;
        const barW = Math.min(28, groupW * 0.22);
        const gap = 6;

        const yAxis = Array.from({ length: ticks + 1 }, (_, i) => {
            const t = i / ticks;
            const y = padT + chartH * (1 - t);
            const val = maxVal * t;
            return `
                <line x1="${padL}" y1="${y}" x2="${w - padR}" y2="${y}" class="bs-ref-grid"/>
                <text x="${padL - 10}" y="${y + 4}" class="bs-ref-y-label" text-anchor="end">${formatAxisTick(val)}</text>`;
        }).join("");

        const groups = rows
            .map((row, i) => {
                const card = num(row.card);
                const cash = num(row.cash);
                const cx = padL + groupW * i + groupW / 2;
                const cardX = cx - barW - gap / 2;
                const cashX = cx + gap / 2;
                const cardH = (card / maxVal) * chartH;
                const cashH = (cash / maxVal) * chartH;
                const cardY = padT + chartH - cardH;
                const cashY = padT + chartH - cashH;
                const label = shortLabel(row.label);
                return `
                    <rect x="${cardX}" y="${cardY}" width="${barW}" height="${cardH}" fill="${COLOR_CARD}" rx="2">
                        <title>${escapeHtml(row.label)} Card: ${money(card)}</title>
                    </rect>
                    <rect x="${cashX}" y="${cashY}" width="${barW}" height="${cashH}" fill="${COLOR_CASH}" rx="2">
                        <title>${escapeHtml(row.label)} Cash: ${money(cash)}</title>
                    </rect>
                    <text x="${cx}" y="${h - 52}" class="bs-ref-x-label" text-anchor="middle">${escapeHtml(label)}</text>`;
            })
            .join("");

        const legend = `
            <g class="bs-group-legend">
                <rect x="${padL}" y="8" width="12" height="12" fill="${COLOR_CARD}" rx="2"/>
                <text x="${padL + 18}" y="18" class="bs-ref-x-label">Card</text>
                <rect x="${padL + 72}" y="8" width="12" height="12" fill="${COLOR_CASH}" rx="2"/>
                <text x="${padL + 90}" y="18" class="bs-ref-x-label">Cash</text>
            </g>`;

        return `
            <svg class="bs-ref-svg bs-ref-bars bs-ref-bars--grouped" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">
                ${legend}
                ${yAxis}
                ${groups}
            </svg>`;
    }

    function renderGroupedCardCashComparison(entries, title, emptyMsg) {
        const rows = (entries || []).map((e) => ({
            label: e.label,
            card: num(e.card),
            cash: num(e.cash),
        }));
        const hasData = rows.some((r) => r.card > 0 || r.cash > 0);
        if (!hasData) {
            return `
                <section class="bs-panel bs-panel--chart bs-panel--compare">
                    <div class="bs-panel-head">
                        <h3 class="bs-panel-title">${escapeHtml(title)}</h3>
                    </div>
                    <p class="bs-chart-empty">${escapeHtml(emptyMsg || "No sales data to compare.")}</p>
                </section>`;
        }
        return `
            <section class="bs-panel bs-panel--chart bs-panel--compare">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">${escapeHtml(title)}</h3>
                        <p class="bs-panel-sub">Card and cash sales side by side for each selection.</p>
                    </div>
                    ${renderLegendChips()}
                </div>
                <div class="bs-pie-bar-pair bs-pie-bar-pair--bars-only">
                    <div class="bs-pie-bar-pair__bars bs-pie-bar-pair__bars--full">${renderSvgGroupedCardCash(rows)}</div>
                </div>
            </section>`;
    }

    function metricTile(label, value, accent, drillKey, drillable) {
        const tag = drillable && drillKey ? "button" : "div";
        const drill =
            drillable && drillKey
                ? ` type="button" class="bs-metric bs-metric--drill ${accent}" data-an-drill="${drillKey}"`
                : ` class="bs-metric ${accent}"`;
        return `
            <${tag}${drill}>
                <span class="bs-metric-label">${escapeHtml(label)}</span>
                <strong class="bs-metric-value">${value}</strong>
                ${drillable && drillKey ? '<span class="bs-metric-link">View breakdown</span>' : ""}
            </${tag}>`;
    }

    function renderMetricStrip(agg, options) {
        const M = options?.booksModel || window.OplixBooksModel;
        const b = M.cardCashBreakdownFromAggregate(agg);
        const drillable = options?.drillable !== false;
        const netClass = agg.net >= 0 ? "bs-metric--net-pos" : "bs-metric--net-neg";
        const gas = !!agg.hasGasStation;
        const secondaryGas = gas
            ? `
                    <div class="bs-metric-mini bs-metric-mini--card">
                        <span>Credit card</span>
                        <strong>${money(b.card)}</strong>
                    </div>
                    <div class="bs-metric-mini bs-metric-mini--fuel">
                        <span>Fuel (gal)</span>
                        <strong>${formatNumber(agg.fuelGallons)}</strong>
                    </div>
                    <div class="bs-metric-mini bs-metric-mini--fuel">
                        <span>Fuel ($)</span>
                        <strong>${money(agg.fuelDollars)}</strong>
                    </div>`
            : `
                    <div class="bs-metric-mini bs-metric-mini--card">
                        <span>Card sales</span>
                        <strong>${money(b.card)}</strong>
                    </div>
                    <div class="bs-metric-mini bs-metric-mini--cash">
                        <span>Cash sales</span>
                        <strong>${money(b.cash)}</strong>
                    </div>`;

        return `
            <section class="bs-metrics">
                <div class="bs-metrics-row bs-metrics-row--primary">
                    ${metricTile(gas ? "Total sales (merch)" : "Total sales", money(agg.sales), "bs-metric--sales", "sales", drillable)}
                    ${metricTile("Expenses", money(agg.expenses), "bs-metric--expenses", "expenses", drillable)}
                    <div class="bs-metric ${netClass}">
                        <span class="bs-metric-label">Net</span>
                        <strong class="bs-metric-value">${money(agg.net)}</strong>
                    </div>
                </div>
                <div class="bs-metrics-row bs-metrics-row--secondary${gas ? " bs-metrics-row--secondary-gas" : ""}">
                    ${secondaryGas}
                    ${
                        drillable
                            ? `<button type="button" class="bs-metric-mini bs-metric-mini--drill" data-an-drill="utilities">
                            <span>Utilities</span><strong>${money(agg.utilitiesTotal)}</strong>
                        </button>`
                            : `<div class="bs-metric-mini"><span>Utilities</span><strong>${money(agg.utilitiesTotal)}</strong></div>`
                    }
                    <div class="bs-metric-mini">
                        <span>Payroll</span>
                        <strong>${money(agg.payrollTotal)}</strong>
                    </div>
                </div>
            </section>`;
    }

    function formatNumber(v) {
        return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(num(v));
    }

    function renderCellTrend(current, previous, options) {
        const invert = options?.invert === true;
        const cur = num(current);
        const prev = num(previous);
        if (cur === 0 && prev === 0) return "";
        let pct;
        let isUp;
        if (prev === 0) {
            if (cur === 0) return "";
            pct = 100;
            isUp = true;
        } else {
            pct = ((cur - prev) / Math.abs(prev)) * 100;
            if (Math.abs(pct) < 0.5) {
                return `<span class="home-mtd-trend home-trend home-trend--flat">— 0%</span>`;
            }
            isUp = pct >= 0;
        }
        const visualUp = invert ? !isUp : isUp;
        const cls = visualUp ? "home-trend--up" : "home-trend--down";
        const arrow = isUp ? "▲" : "▼";
        const diff = cur - prev;
        const sign = diff >= 0 ? "+" : "−";
        const fmt = options?.format === "number" ? formatNumber : money;
        const changeLabel = `${sign}${fmt(Math.abs(diff))}`;
        const pctLabel = `${diff >= 0 ? "+" : "−"}${Math.abs(pct).toFixed(0)}%`;
        const vsLabel =
            (options?.compareMode && window.OplixBooksTrendLegend?.compareTitle(options.compareMode)) ||
            (options?.compareTitle ? String(options.compareTitle) : "vs prior");
        return `<span class="home-mtd-trend home-trend ${cls}" title="${escapeHtml(pctLabel)} ${escapeHtml(vsLabel)}">${arrow} ${escapeHtml(changeLabel)}</span>`;
    }

    function renderTableValueCell(formattedValue, trendHtml, cellClass) {
        const cls = ["home-cc-num", cellClass].filter(Boolean).join(" ");
        if (!trendHtml) {
            return `<td class="${cls}">${formattedValue}</td>`;
        }
        return `<td class="${cls} home-cc-num--mtd">
                <span class="home-mtd-value">${formattedValue}</span>
                ${trendHtml}
            </td>`;
    }

    function renderHistoryCell(col, raw, prevRaw) {
        const formatted = formatHistoryValue(col, raw);
        if (prevRaw == null) {
            return renderTableValueCell(formatted, "");
        }
        const trend = renderCellTrend(raw, prevRaw, {
            invert: col.trendInvert,
            format: col.format,
            compareMode: "month",
        });
        return renderTableValueCell(formatted, trend);
    }

    function keyMetricCell(label, value, opts) {
        const drillable = opts?.drill && opts?.drillable !== false;
        const tag = drillable ? "button" : "div";
        const cls = ["bs-key-metric", drillable ? "bs-key-metric--drill" : "", opts?.tone || ""]
            .filter(Boolean)
            .join(" ");
        const drill = drillable ? ` type="button" data-an-drill="${opts.drill}"` : "";
        return `
            <${tag} class="${cls}"${drill}>
                <span class="bs-key-metric-label">${escapeHtml(label)}</span>
                <strong class="bs-key-metric-value">${value}</strong>
            </${tag}>`;
    }

    function renderKeyMetricsPanel(agg, options) {
        const M = options?.booksModel || window.OplixBooksModel;
        const drillable = options?.drillable !== false;
        const cc = M.cardCashBreakdownFromAggregate(agg);
        const gas = !!agg?.hasGasStation;
        const opt = { drillable };

        const salesRows = gas
            ? [
                  keyMetricCell("Merch sales", money(agg.sales), { ...opt, drill: "sales" }),
                  keyMetricCell("Credit card", money(cc.card), opt),
                  keyMetricCell("Fuel ($)", money(agg.fuelDollars), opt),
                  keyMetricCell("Fuel (gal.)", formatNumber(agg.fuelGallons), opt),
              ]
            : [
                  keyMetricCell("Total sales", money(agg.sales), { ...opt, drill: "sales" }),
                  keyMetricCell("Card sales", money(cc.card), opt),
                  keyMetricCell("Cash sales", money(cc.cash), opt),
              ];

        const netTone = agg.net >= 0 ? "bs-key-metric--pos" : "bs-key-metric--neg";

        const rows = [
            ...salesRows,
            keyMetricCell("Total expenses", money(agg.expenses), { ...opt, drill: "expenses" }),
            keyMetricCell("Net", money(agg.net), { ...opt, tone: netTone }),
            keyMetricCell("Utilities", money(agg.utilitiesTotal), { ...opt, drill: "utilities" }),
            keyMetricCell("Payroll", money(agg.payrollTotal), opt),
            keyMetricCell("Sales tax", money(agg.salesTax), opt),
            keyMetricCell("Accountant", money(agg.accountant), opt),
            keyMetricCell("Over / short", money(agg.totalOverShort), opt),
            keyMetricCell("Receivables", money(agg.receivablesTotal), opt),
            keyMetricCell("Cash expense", money(agg.cashExpense), opt),
            keyMetricCell("Checks / ACH", money(agg.checksAch), opt),
            keyMetricCell("Other expense", money(agg.otherExpense), opt),
            ...(M.num(agg.monthAdjustmentsExpense)
                ? [keyMetricCell("Month adj. (expense)", money(agg.monthAdjustmentsExpense), opt)]
                : []),
            ...(M.num(agg.monthAdjustmentsCredit)
                ? [keyMetricCell("Month adj. (credit)", money(agg.monthAdjustmentsCredit), opt)]
                : []),
        ];

        const trackRows = [
            ...(M.num(agg.pulltabCash) ? [keyMetricCell("Pulltab (track)", money(agg.pulltabCash), opt)] : []),
            ...(M.num(agg.lotteryCash) ? [keyMetricCell("Lottery (track)", money(agg.lotteryCash), opt)] : []),
            ...(M.num(agg.windStationCash)
                ? [keyMetricCell("Wind station (track)", money(agg.windStationCash), opt)]
                : []),
            ...(M.num(agg.kenoStationCash)
                ? [keyMetricCell("Keno station (track)", money(agg.kenoStationCash), opt)]
                : []),
            ...(M.num(agg.waynePass) ? [keyMetricCell("Wayne Pass (track)", money(agg.waynePass), opt)] : []),
        ];

        return `
            <section class="bs-panel bs-panel--key-metrics">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">Key metrics</h3>
                        <p class="bs-panel-sub">Full monthly totals from Daily books for this selection.</p>
                    </div>
                </div>
                <div class="bs-key-metrics-grid">${rows.join("")}</div>
                ${
                    trackRows.length
                        ? `<h4 class="bs-track-only-title">Track only</h4>
                <p class="books-hint bs-track-only-hint">Recorded for reference — not included in sales or net.</p>
                <div class="bs-key-metrics-grid bs-key-metrics-grid--track">${trackRows.join("")}</div>`
                        : ""
                }
            </section>`;
    }

    function historyDetailColumns(packs, booksModel) {
        const M = booksModel || window.OplixBooksModel;
        const hasGas = (packs || []).some((p) => p.aggregate?.hasGasStation);
        const cols = [
            { label: "Register — card", get: (a) => a.registerCard },
            { label: "Register — cash", get: (a) => a.registerCash },
            { label: "Lottery (track only)", get: (a) => a.lotteryCash },
            { label: "Pulltab (track only)", get: (a) => a.pulltabCash },
            { label: "Wind station (track only)", get: (a) => a.windStationCash },
            { label: "Keno station (track only)", get: (a) => a.kenoStationCash },
            { label: "Wayne Pass (track only)", get: (a) => a.waynePass },
            { label: "Credit card (pump)", get: (a) => a.creditCard },
            { label: "Fuel ($)", get: (a) => a.fuelDollars },
            { label: "Fuel (gal.)", get: (a) => a.fuelGallons, format: "number" },
        ];

        if (!hasGas) {
            cols.splice(4, 4);
        } else {
            cols.splice(0, 3);
            cols.unshift(
                { label: "Merch sale", get: (a) => a.merchSale },
                { label: "Register — card", get: (a) => a.registerCard },
                { label: "Register — cash", get: (a) => a.registerCash }
            );
        }

        cols.push(
            { label: "Cash expense", get: (a) => a.cashExpense, trendInvert: true },
            { label: "Checks / ACH", get: (a) => a.checksAch, trendInvert: true },
            { label: "Other expense", get: (a) => a.otherExpense, trendInvert: true },
            { label: "Sales tax", get: (a) => a.salesTax, trendInvert: true },
            { label: "Accountant", get: (a) => a.accountant, trendInvert: true },
            { label: "Month adj. (expense)", get: (a) => a.monthAdjustmentsExpense, trendInvert: true },
            { label: "Month adj. (credit)", get: (a) => a.monthAdjustmentsCredit },
            { label: "Payroll · Week 1", get: (a) => a.payroll?.week1, trendInvert: true },
            { label: "Payroll · Week 2", get: (a) => a.payroll?.week2, trendInvert: true },
            { label: "Payroll · Week 3", get: (a) => a.payroll?.week3, trendInvert: true },
            { label: "Payroll · Week 4", get: (a) => a.payroll?.week4, trendInvert: true },
            { label: "Receivables", get: (a) => a.receivablesTotal },
            { label: "Over / short", get: (a) => a.totalOverShort, trendInvert: true },
            { label: "Register O/S", get: (a) => a.registerOverShort, trendInvert: true },
            { label: "Lottery O/S", get: (a) => a.lotteryOverShort, trendInvert: true },
            { label: "Pulltab O/S", get: (a) => a.pulltabOverShort, trendInvert: true }
        );

        const utilityKeys = new Set();
        M.UTILITY_KEYS.forEach((u) => utilityKeys.add(u.key));
        (packs || []).forEach((p) => {
            Object.keys(p.aggregate?.utilities || {}).forEach((k) => utilityKeys.add(k));
        });

        [...utilityKeys]
            .sort((a, b) => M.labelForUtilityKey(a, []).localeCompare(M.labelForUtilityKey(b, [])))
            .forEach((key) => {
                cols.push({
                    label: M.labelForUtilityKey(key, []),
                    get: (a) => num(a.utilities?.[key]),
                    trendInvert: true,
                });
            });

        return cols.filter((col) =>
            (packs || []).some((p) => num(col.get(p.aggregate)) !== 0)
        );
    }

    function formatHistoryValue(col, value) {
        if (col.format === "number") return formatNumber(value);
        return money(value);
    }

    function renderKeyMetricsHistory(packs, options) {
        const sorted = (packs || [])
            .slice()
            .sort((a, b) => b.monthId.localeCompare(a.monthId));
        if (!sorted.length) return "";

        const M = options?.booksModel || window.OplixBooksModel;
        const monthLabelFn = options?.monthLabel || ((id) => id);
        const locationName = options?.locationName || "Facility";
        const cols = historyDetailColumns(sorted, M);

        if (!cols.length) {
            return `
                <section class="an-key-metrics-history">
                    <header class="an-key-metrics-history-head">
                        <h3 class="an-key-metrics-history-title">Monthly detail · past 12 months · ${escapeHtml(locationName)}</h3>
                        ${window.OplixBooksTrendLegend ? OplixBooksTrendLegend.legendHtml("month") : '<p class="an-key-metrics-history-lead">Expense, sales source, and utility breakdowns — month-over-month trends.</p>'}
                    </header>
                    <p class="an-key-metrics-empty books-hint">No breakdown lines recorded for the past 12 months.</p>
                </section>`;
        }

        return `
            <section class="an-key-metrics-history">
                <header class="an-key-metrics-history-head">
                    <h3 class="an-key-metrics-history-title">Monthly detail · past 12 months · ${escapeHtml(locationName)}</h3>
                    ${window.OplixBooksTrendLegend ? OplixBooksTrendLegend.legendHtml("month") : '<p class="an-key-metrics-history-lead">Expense, sales source, and utility breakdowns — month-over-month trends.</p>'}
                </header>
                <div class="home-card an-key-metrics-table-wrap">
                    <table class="home-cc-table an-key-metrics-table">
                        <thead>
                            <tr>
                                <th scope="col" class="an-key-metrics-table-month">Month</th>
                                ${cols
                                    .map((c) => `<th scope="col" class="home-cc-num">${escapeHtml(c.label)}</th>`)
                                    .join("")}
                            </tr>
                        </thead>
                        <tbody>
                            ${sorted
                                .map((p, rowIndex) => {
                                    const agg = p.aggregate;
                                    const prevAgg = sorted[rowIndex + 1]?.aggregate;
                                    return `<tr>
                                        <th scope="row" class="an-key-metrics-table-month">${escapeHtml(monthLabelFn(p.monthId))}</th>
                                        ${cols
                                            .map((c) => {
                                                const raw = c.get(agg);
                                                const prevRaw = prevAgg ? c.get(prevAgg) : null;
                                                return renderHistoryCell(c, raw, prevRaw);
                                            })
                                            .join("")}
                                    </tr>`;
                                })
                                .join("")}
                        </tbody>
                    </table>
                </div>
            </section>`;
    }

    function renderSvgVerticalBars(items) {
        const w = 420;
        const h = 380;
        const padL = 52;
        const padR = 16;
        const padT = 24;
        const padB = 72;
        const chartW = w - padL - padR;
        const chartH = h - padT - padB;
        const maxVal = niceAxisMax(Math.max(...items.map((x) => num(x.amount)), 1));
        const ticks = 5;
        const n = items.length;
        const barW = Math.min(48, (chartW / n) * 0.72);
        const slot = chartW / n;

        const yAxis = Array.from({ length: ticks + 1 }, (_, i) => {
            const t = i / ticks;
            const y = padT + chartH * (1 - t);
            const val = maxVal * t;
            return `
                <line x1="${padL}" y1="${y}" x2="${w - padR}" y2="${y}" class="bs-ref-grid"/>
                <text x="${padL - 10}" y="${y + 4}" class="bs-ref-y-label" text-anchor="end">${formatAxisTick(val)}</text>`;
        }).join("");

        const bars = items
            .map((item, i) => {
                const v = num(item.amount);
                const barH = (v / maxVal) * chartH;
                const x = padL + slot * i + (slot - barW) / 2;
                const y = padT + chartH - barH;
                const label = shortLabel(item.label);
                const lx = padL + slot * i + slot / 2;
                return `
                    <rect x="${x}" y="${y}" width="${barW}" height="${barH}" fill="${item.color}" rx="2">
                        <title>${escapeHtml(item.label)}: ${money(v)}</title>
                    </rect>
                    <text x="${lx}" y="${h - 18}" class="bs-ref-x-label" text-anchor="middle">${escapeHtml(label)}</text>`;
            })
            .join("");

        return `
            <svg class="bs-ref-svg bs-ref-bars" viewBox="0 0 ${w} ${h}" aria-hidden="true">
                ${yAxis}
                ${bars}
            </svg>`;
    }

    function renderLegendChips(gasMode) {
        if (gasMode) {
            return `
            <div class="bs-legend-chips" aria-hidden="true">
                <span class="bs-chip"><i class="bs-chip-dot" style="background:${COLOR_CARD}"></i>Merch</span>
                <span class="bs-chip"><i class="bs-chip-dot" style="background:#6366f1"></i>Register card</span>
                <span class="bs-chip"><i class="bs-chip-dot" style="background:#8b5cf6"></i>Credit card</span>
                <span class="bs-chip"><i class="bs-chip-dot" style="background:${COLOR_FUEL}"></i>Fuel</span>
            </div>`;
        }
        return `
            <div class="bs-legend-chips" aria-hidden="true">
                <span class="bs-chip"><i class="bs-chip-dot" style="background:${COLOR_CARD}"></i>Card</span>
                <span class="bs-chip"><i class="bs-chip-dot" style="background:${COLOR_CASH}"></i>Cash</span>
            </div>`;
    }

    function renderPieBarPair(title, slices, emptyMsg, panelOpts) {
        const items = assignColors(filterSlices(slices));
        const opts = panelOpts || {};
        const gasMode = !!opts.gasMode;
        if (!items.length) {
            return `
                <section class="bs-panel bs-panel--chart">
                    <div class="bs-panel-head">
                        <h3 class="bs-panel-title">${escapeHtml(title)}</h3>
                    </div>
                    <p class="bs-chart-empty">${escapeHtml(emptyMsg || "No data for this period.")}</p>
                </section>`;
        }

        const cardAmt = num(items.find((s) => s.label === "Card")?.amount);
        const cashAmt = num(items.find((s) => s.label === "Cash")?.amount);
        const merchAmt = num(items.find((s) => s.label === "Merch")?.amount);
        const regCardAmt = num(items.find((s) => s.label === "Register card")?.amount);
        const fuelAmt = num(items.find((s) => s.label === "Fuel")?.amount);
        const total = cardAmt + cashAmt;

        const panelStats = gasMode
            ? `
                <div class="bs-panel-stat">
                    <span>Merch (total sales)</span>
                    <strong>${money(opts.total != null ? opts.total : merchAmt)}</strong>
                </div>
                <div class="bs-panel-stat bs-panel-stat--card">
                    <span>Credit card</span>
                    <strong>${money(opts.registerCard != null ? opts.registerCard : regCardAmt)}</strong>
                </div>
                <div class="bs-panel-stat bs-panel-stat--fuel">
                    <span>Fuel (gal)</span>
                    <strong>${formatNumber(opts.fuelGallons != null ? opts.fuelGallons : 0)}</strong>
                </div>
                <div class="bs-panel-stat bs-panel-stat--fuel">
                    <span>Fuel ($)</span>
                    <strong>${money(fuelAmt)}</strong>
                </div>`
            : `
                <div class="bs-panel-stat">
                    <span>Total sales</span>
                    <strong>${money(opts.total != null ? opts.total : total)}</strong>
                </div>
                <div class="bs-panel-stat bs-panel-stat--card">
                    <span>Card</span>
                    <strong>${money(cardAmt)}</strong>
                </div>
                <div class="bs-panel-stat bs-panel-stat--cash">
                    <span>Cash</span>
                    <strong>${money(cashAmt)}</strong>
                </div>`;

        return `
            <section class="bs-panel bs-panel--chart">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">${escapeHtml(title)}</h3>
                        ${opts.subtitle ? `<p class="bs-panel-sub">${escapeHtml(opts.subtitle)}</p>` : ""}
                    </div>
                    ${renderLegendChips(gasMode)}
                </div>
                <div class="bs-panel-stats${gasMode ? " bs-panel-stats--gas" : ""}">
                    ${panelStats}
                </div>
                <div class="bs-pie-bar-pair">
                    <div class="bs-pie-bar-pair__col">
                        <span class="bs-pie-bar-label">Share</span>
                        <div class="bs-pie-bar-pair__pie">${renderSvgPie(items)}</div>
                    </div>
                    <div class="bs-pie-bar-divider" aria-hidden="true"></div>
                    <div class="bs-pie-bar-pair__col">
                        <span class="bs-pie-bar-label">Amounts</span>
                        <div class="bs-pie-bar-pair__bars">${renderSvgVerticalBars(items)}</div>
                    </div>
                </div>
                ${opts.footnote ? `<p class="bs-panel-foot">${escapeHtml(opts.footnote)}</p>` : ""}
            </section>`;
    }

    function renderDailyTrend(dailySeries, formatDay) {
        const series = [...(dailySeries || [])]
            .filter((d) => d.dayId)
            .sort((a, b) => String(a.dayId).localeCompare(String(b.dayId)));
        if (!series.length) {
            return `
                <article class="bs-chart-card bs-chart-card--wide">
                    <h3 class="bs-chart-title">Daily sales</h3>
                    <p class="bs-chart-empty">No daily entries yet — save days in Daily books.</p>
                </article>`;
        }

        const items = series.map((d, i) => ({
            label: formatDay ? formatDay(d.dayId) : d.dayId,
            amount: num(d.sales),
            color: COLORS[i % COLORS.length],
        }));

        return renderPieBarPair("Daily sales by day", items, "");
    }

    function renderSalesExpenseBars(agg) {
        const items = assignColors(
            filterSlices([
                { label: "Sales", amount: agg.sales, color: "#2563eb" },
                { label: "Expenses", amount: agg.expenses, color: "#f06b6b" },
            ])
        );
        return renderPieBarPair("Sales vs expenses", items, "");
    }

    function renderDashboard(agg, options) {
        const M = options?.booksModel;
        const gas = !!agg?.hasGasStation;
        const comparison = options?.comparison;
        const compareHtml =
            comparison && M
                ? renderCompareCardCash(comparison, M, { inline: true })
                : "";
        const salesChartHtml = gas
            ? renderPieBarPair(
                  "Sales by type",
                  cardCashSlices(agg, M),
                  "No merch sales recorded this period.",
                  {
                      subtitle: "Merch, register card, credit card, and fuel tracked separately",
                      footnote: cardCashHint(agg),
                      total: agg.sales,
                      registerCard: agg.registerCard,
                      fuelGallons: agg.fuelGallons,
                      gasMode: true,
                  }
              )
            : "";

        return `
            <div class="bs-page">
                <header class="bs-page-header">
                    <h2 class="bs-page-title">${escapeHtml(options?.title || "Books summary")}</h2>
                    <p class="bs-page-lead">Monthly totals from Daily books for the selection above.</p>
                </header>
                ${renderMetricStrip(agg, {
                    drillable: options?.drillable,
                    booksModel: M,
                })}
                ${salesChartHtml}
                ${compareHtml}
            </div>`;
    }

    function renderCompareCardCash(comparison, booksModel, opts) {
        const M = booksModel || window.OplixBooksModel;
        const baseAgg = comparison.baseAggregate || comparison.base;
        const compareAgg = comparison.compareAggregate || comparison.compare;
        if (baseAgg?.hasGasStation || compareAgg?.hasGasStation) {
            const rows = [
                {
                    label: comparison.labels.base.split("·")[0].trim(),
                    ...M.gasSalesSlicesFromAggregate(baseAgg).reduce(
                        (o, s) => ({ ...o, [s.label]: s.amount }),
                        {}
                    ),
                },
                {
                    label: comparison.labels.compare.split("·")[0].trim(),
                    ...M.gasSalesSlicesFromAggregate(compareAgg).reduce(
                        (o, s) => ({ ...o, [s.label]: s.amount }),
                        {}
                    ),
                },
            ];
            const inner = renderGroupedGasSalesComparison(
                rows,
                "Sales by type — comparison",
                "No sales to compare."
            );
            return opts?.inline ? inner : `<div class="bs-page-section">${inner}</div>`;
        }
        const rows = [
            {
                label: comparison.labels.base.split("·")[0].trim(),
                ...M.cardCashBreakdownFromAggregate(baseAgg),
            },
            {
                label: comparison.labels.compare.split("·")[0].trim(),
                ...M.cardCashBreakdownFromAggregate(compareAgg),
            },
        ].map((r) => ({ label: r.label, card: r.card, cash: r.cash }));
        const inner = renderGroupedCardCashComparison(
            rows,
            "Card vs cash — comparison",
            "No sales to compare."
        );
        return opts?.inline ? inner : `<div class="bs-page-section">${inner}</div>`;
    }

    function renderGroupedGasSalesComparison(entries, title, emptyMsg) {
        const rows = (entries || []).map((e) => ({
            label: e.label,
            merch: num(e.Merch),
            regCard: num(e["Register card"]),
            pumpCredit: num(e["Credit card"]),
            fuel: num(e.Fuel),
        }));
        const hasData = rows.some(
            (r) => r.merch > 0 || r.regCard > 0 || r.pumpCredit > 0 || r.fuel > 0
        );
        if (!hasData) {
            return `
                <section class="bs-panel bs-panel--chart">
                    <div class="bs-panel-head">
                        <h3 class="bs-panel-title">${escapeHtml(title)}</h3>
                    </div>
                    <p class="bs-chart-empty">${escapeHtml(emptyMsg || "No sales data to compare.")}</p>
                </section>`;
        }
        return `
            <section class="bs-panel bs-panel--chart">
                <div class="bs-panel-head">
                    <div class="bs-panel-head-text">
                        <h3 class="bs-panel-title">${escapeHtml(title)}</h3>
                        <p class="bs-panel-sub">Merch, register card, credit card, and fuel for each period.</p>
                    </div>
                </div>
                <div class="bs-pie-bar-pair bs-pie-bar-pair--bars-only">
                    <div class="bs-pie-bar-pair__bars bs-pie-bar-pair__bars--full">${renderSvgGroupedGasSales(rows)}</div>
                </div>
            </section>`;
    }

    function renderSvgGroupedGasSales(rows) {
        const w = Math.max(480, rows.length * 140);
        const h = 380;
        const padL = 52;
        const padR = 20;
        const padT = 36;
        const padB = 88;
        const chartW = w - padL - padR;
        const chartH = h - padT - padB;
        const maxVal = niceAxisMax(
            Math.max(...rows.flatMap((r) => [r.merch, r.regCard, r.pumpCredit, r.fuel]), 1)
        );
        const ticks = 5;
        const groupW = chartW / rows.length;
        const barW = Math.min(18, groupW * 0.14);
        const gap = 3;
        const colors = [COLOR_CARD, "#6366f1", "#8b5cf6", COLOR_FUEL];
        const keys = ["merch", "regCard", "pumpCredit", "fuel"];
        const labels = ["Merch", "Reg card", "Credit card", "Fuel"];

        const yAxis = Array.from({ length: ticks + 1 }, (_, i) => {
            const t = i / ticks;
            const y = padT + chartH * (1 - t);
            const val = maxVal * t;
            return `
                <line x1="${padL}" y1="${y}" x2="${w - padR}" y2="${y}" class="bs-ref-grid"/>
                <text x="${padL - 10}" y="${y + 4}" class="bs-ref-y-label" text-anchor="end">${formatAxisTick(val)}</text>`;
        }).join("");

        const groups = rows
            .map((row, i) => {
                const cx = padL + groupW * i + groupW / 2;
                const vals = [row.merch, row.regCard, row.pumpCredit, row.fuel];
                const totalW = keys.length * barW + (keys.length - 1) * gap;
                let x0 = cx - totalW / 2;
                const bars = vals
                    .map((v, j) => {
                        const barH = (v / maxVal) * chartH;
                        const y = padT + chartH - barH;
                        const x = x0;
                        x0 += barW + gap;
                        return `
                    <rect x="${x}" y="${y}" width="${barW}" height="${barH}" fill="${colors[j]}" rx="2">
                        <title>${escapeHtml(row.label)} ${labels[j]}: ${money(v)}</title>
                    </rect>`;
                    })
                    .join("");
                return `
                    ${bars}
                    <text x="${cx}" y="${h - 52}" class="bs-ref-x-label" text-anchor="middle">${escapeHtml(shortLabel(row.label))}</text>`;
            })
            .join("");

        const legend = `
            <g class="bs-group-legend">
                ${labels
                    .map(
                        (lab, j) => `
                <rect x="${padL + j * 78}" y="8" width="12" height="12" fill="${colors[j]}" rx="2"/>
                <text x="${padL + 18 + j * 78}" y="18" class="bs-ref-x-label">${lab}</text>`
                    )
                    .join("")}
            </g>`;

        return `
            <svg class="bs-ref-svg bs-ref-bars bs-ref-bars--grouped" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">
                ${legend}
                ${yAxis}
                ${groups}
            </svg>`;
    }

    function renderMultiLocationCardCash(packs, locNameFn, title, booksModel) {
        const M = booksModel || window.OplixBooksModel;
        const allGas = (packs || []).length > 0 && (packs || []).every((p) => p.aggregate?.hasGasStation);
        if (allGas) {
            const entries = (packs || []).map((p) => {
                const slices = M.gasSalesSlicesFromAggregate(p.aggregate);
                return {
                    label: locNameFn(p.locationId),
                    ...slices.reduce((o, s) => ({ ...o, [s.label]: s.amount }), {}),
                };
            });
            return `
            <div class="bs-page">
                <header class="bs-page-header">
                    <h2 class="bs-page-title">${escapeHtml(title)}</h2>
                    <p class="bs-page-lead">Merch, register card, credit card, and fuel by facility for the selected month.</p>
                </header>
                ${renderGroupedGasSalesComparison(entries, "Sales by facility", "No sales data for these locations.")}
            </div>`;
        }
        const entries = (packs || []).map((p) => {
            const b = M.cardCashBreakdownFromAggregate(p.aggregate);
            return {
                label: locNameFn(p.locationId),
                card: b.card,
                cash: b.cash,
            };
        });
        return `
            <div class="bs-page">
                <header class="bs-page-header">
                    <h2 class="bs-page-title">${escapeHtml(title)}</h2>
                    <p class="bs-page-lead">Card and cash sales across all facilities for the selected month.</p>
                </header>
                ${renderGroupedCardCashComparison(
                    entries,
                    "Sales by facility",
                    "No sales data for these locations."
                )}
            </div>`;
    }

    function shortCompareLabel(label) {
        const parts = String(label || "")
            .split("·")
            .map((s) => s.trim())
            .filter(Boolean);
        if (parts.length >= 2) return `${parts[0]} · ${parts[1]}`;
        return parts[0] || "Selection";
    }

    const EXPENSE_COMPARE_KEYS = new Set([
        "expenses",
        "utilitiesTotal",
        "payrollTotal",
        "cashExpense",
        "checksAch",
        "otherExpense",
    ]);

    function compareChangeClass(key, diff) {
        if (!diff) return "";
        const invert = EXPENSE_COMPARE_KEYS.has(key);
        if (diff > 0) return invert ? "neg" : "pos";
        return invert ? "pos" : "neg";
    }

    function formatCompareChange(row, formatFn) {
        const fmt = formatFn || money;
        const sign = row.diff >= 0 ? "+" : "";
        return `${sign}${fmt(row.diff)} (${sign}${row.pct.toFixed(1)}%)`;
    }

    function renderCompareBarRow(tag, amount, maxVal, color) {
        const pct = maxVal > 0 ? Math.max((num(amount) / maxVal) * 100, amount > 0 ? 4 : 0) : 0;
        return `
            <div class="bs-compare-bar-row">
                <span class="bs-compare-bar-tag" title="${escapeHtml(tag)}">${escapeHtml(shortLabel(tag))}</span>
                <div class="bs-compare-track">
                    <div class="bs-compare-fill" style="width:${pct}%;background:${color}"></div>
                </div>
                <span class="bs-compare-amt">${money(amount)}</span>
            </div>`;
    }

    function renderCompareMetricBlock(row, baseTag, compareTag, formatFn) {
        const fmt = formatFn || money;
        const maxVal = Math.max(num(row.base), num(row.compare), 1);
        const cls = compareChangeClass(row.key, row.diff);
        return `
            <div class="bs-compare-metric">
                <div class="bs-compare-metric-head">
                    <span>${escapeHtml(row.label)}</span>
                    <span class="bs-compare-pct ${cls}">${escapeHtml(formatCompareChange(row, fmt))}</span>
                </div>
                ${renderCompareBarRow(baseTag, row.base, maxVal, "#6366f1")}
                ${renderCompareBarRow(compareTag, row.compare, maxVal, "#0ea5e9")}
            </div>`;
    }

    function renderCompareSnapshotCard(label, agg, booksModel) {
        const M = booksModel || window.OplixBooksModel;
        const cc = M.cardCashBreakdownFromAggregate(agg);
        const netCls = agg.net >= 0 ? "pos" : "neg";
        return `
            <article class="an-compare-snapshot">
                <h4 class="an-compare-snapshot-title">${escapeHtml(label)}</h4>
                <div class="an-compare-snapshot-grid">
                    <div><span>Sales</span><strong>${money(agg.sales)}</strong></div>
                    <div><span>Card</span><strong>${money(cc.card)}</strong></div>
                    <div><span>Cash</span><strong>${money(cc.cash)}</strong></div>
                    <div><span>Expenses</span><strong>${money(agg.expenses)}</strong></div>
                    <div><span>Utilities</span><strong>${money(agg.utilitiesTotal)}</strong></div>
                    <div><span>Payroll</span><strong>${money(agg.payrollTotal)}</strong></div>
                </div>
                <div class="an-compare-snapshot-net ${netCls}">
                    <span>Net</span>
                    <strong>${money(agg.net)}</strong>
                </div>
            </article>`;
    }

    function renderCompareOverview(cmp, baseAgg, compareAgg, booksModel) {
        const baseTag = shortCompareLabel(cmp.labels.base);
        const compareTag = shortCompareLabel(cmp.labels.compare);
        const headlineKeys = [
            "sales",
            "expenses",
            "net",
            "utilitiesTotal",
            "payrollTotal",
            "fuelDollars",
            "totalOverShort",
        ];
        const metricMap = Object.fromEntries((cmp.metrics || []).map((r) => [r.key, r]));
        const ccBase = booksModel.cardCashBreakdownFromAggregate(baseAgg);
        const ccCompare = booksModel.cardCashBreakdownFromAggregate(compareAgg);
        const cardRow = {
            key: "cardSales",
            label: "Card sales",
            base: ccBase.card,
            compare: ccCompare.card,
            diff: ccBase.card - ccCompare.card,
            pct:
                ccCompare.card !== 0
                    ? ((ccBase.card - ccCompare.card) / ccCompare.card) * 100
                    : ccBase.card
                      ? 100
                      : 0,
        };
        const cashRow = {
            key: "cashSales",
            label: "Cash sales",
            base: ccBase.cash,
            compare: ccCompare.cash,
            diff: ccBase.cash - ccCompare.cash,
            pct:
                ccCompare.cash !== 0
                    ? ((ccBase.cash - ccCompare.cash) / ccCompare.cash) * 100
                    : ccBase.cash
                      ? 100
                      : 0,
        };

        const metricBlocks = headlineKeys
            .map((key) => metricMap[key])
            .filter(Boolean)
            .map((row) => renderCompareMetricBlock(row, baseTag, compareTag, row.format === "number" ? (v) => new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(num(v)) : money))
            .join("");

        const cardCashBlocks = [cardRow, cashRow]
            .map((row) => renderCompareMetricBlock(row, baseTag, compareTag))
            .join("");

        const utilityRows = (cmp.utilities || [])
            .filter((u) => num(u.base) > 0 || num(u.compare) > 0)
            .slice(0, 6)
            .map((row) =>
                renderCompareMetricBlock(
                    { ...row, key: "utilitiesTotal", label: row.label },
                    baseTag,
                    compareTag
                )
            )
            .join("");

        const netRow = metricMap.net;
        const netBanner =
            netRow && (num(netRow.base) || num(netRow.compare))
                ? `
            <div class="bs-net-banner ${netRow.diff >= 0 ? "bs-net-banner--pos" : "bs-net-banner--neg"}">
                <span>Net change · ${escapeHtml(baseTag)} vs ${escapeHtml(compareTag)}</span>
                <strong>${netRow.diff >= 0 ? "+" : ""}${money(netRow.diff)} (${netRow.pct >= 0 ? "+" : ""}${netRow.pct.toFixed(1)}%)</strong>
            </div>`
                : "";

        return `
            <section class="bs-compare-section an-compare-results">
                <header class="an-compare-results-head">
                    <h3 class="an-compare-results-title">Comparison</h3>
                    <p class="an-compare-results-lead">${escapeHtml(baseTag)} compared with ${escapeHtml(compareTag)}. Change shows primary minus compare.</p>
                </header>
                <div class="an-compare-snapshots">
                    ${renderCompareSnapshotCard(baseTag, baseAgg, booksModel)}
                    ${renderCompareSnapshotCard(compareTag, compareAgg, booksModel)}
                </div>
                ${netBanner}
                <div class="bs-panel bs-panel--chart">
                    <div class="bs-panel-head">
                        <h4 class="bs-panel-title">Key metrics</h4>
                    </div>
                    <div class="bs-compare-card">${metricBlocks}${cardCashBlocks}</div>
                </div>
                ${renderCompareCardCash(
                    {
                        labels: cmp.labels,
                        baseAggregate: baseAgg,
                        compareAggregate: compareAgg,
                    },
                    booksModel,
                    { inline: true }
                )}
                ${
                    utilityRows
                        ? `
                <div class="bs-panel bs-panel--chart">
                    <div class="bs-panel-head">
                        <h4 class="bs-panel-title">Utilities</h4>
                    </div>
                    <div class="bs-compare-card">${utilityRows}</div>
                </div>`
                        : ""
                }
            </section>`;
    }

    function renderMultiLocationUtilityCompare(packs, utilityKey, utilityLabel, locNameFn, booksModel) {
        const M = booksModel || window.OplixBooksModel;
        const rows = (packs || [])
            .map((p) => ({
                label: locNameFn(p.locationId),
                amount: M.num(p.aggregate.utilities?.[utilityKey]),
            }))
            .filter((r) => r.amount > 0)
            .sort((a, b) => b.amount - a.amount);
        const total = rows.reduce((s, r) => s + r.amount, 0);
        const maxVal = Math.max(...rows.map((r) => r.amount), 1);

        if (!rows.length) {
            return `
                <section class="an-compare-results">
                    <header class="an-compare-results-head">
                        <h3 class="an-compare-results-title">${escapeHtml(utilityLabel)} by facility</h3>
                        <p class="an-compare-results-lead">No ${escapeHtml(utilityLabel.toLowerCase())} recorded for this month.</p>
                    </header>
                </section>`;
        }

        return `
            <section class="an-compare-results">
                <header class="an-compare-results-head">
                    <h3 class="an-compare-results-title">${escapeHtml(utilityLabel)} by facility</h3>
                    <p class="an-compare-results-lead">Total across all locations: ${money(total)}</p>
                </header>
                <div class="bs-panel bs-panel--chart">
                    <div class="bs-compare-card">
                        ${rows
                            .map(
                                (row) => `
                            <div class="bs-compare-metric">
                                <div class="bs-compare-metric-head">
                                    <span>${escapeHtml(row.label)}</span>
                                    <span class="bs-compare-pct">${money(row.amount)}</span>
                                </div>
                                ${renderCompareBarRow(row.label, row.amount, maxVal, "#6366f1")}
                            </div>`
                            )
                            .join("")}
                    </div>
                </div>
            </section>`;
    }

    window.OplixBooksSummaryCharts = {
        COLORS,
        COLOR_CARD,
        COLOR_CASH,
        renderDashboard,
        renderCompareCardCash,
        renderCompareOverview,
        renderMultiLocationUtilityCompare,
        renderKeyMetricsHistory,
        renderMultiLocationCardCash,
        renderGroupedCardCashComparison,
        renderPieBarPair,
        cardCashSlices,
        money,
        renderCellTrend,
        renderTableValueCell,
    };
})();
