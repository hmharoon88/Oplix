/**
 * Daily books — monthly books entry (daily sheet, utilities, payroll, receivables, cash reconciliation).
 */
(function () {
    const M = () => window.OplixBooksModel;
    const Store = () => window.OplixBooksStore;
    const DirStore = () => window.OplixLocationDirectoryStore;
    const DirModel = () => window.OplixLocationDirectoryModel;
    const FC = () => window.OplixBooksFieldConfig;

    let userId = null;
    let locations = [];
    let viewMode = "daily";
    let state = {
        locationId: "",
        monthId: M().monthIdFromDate(new Date()),
        dayId: M().dayIdFromDate(new Date()),
        tab: "daily",
        month: M().defaultMonthDoc(),
        day: M().defaultDayDoc(),
        daysById: {},
        utilityProviders: [],
        payables: [],
        receivables: [],
        dirty: false,
        expenseDescriptions: [],
        entryDayId: M().dayIdFromDate(new Date()),
    };

    function booksRoot() {
        return viewMode === "monthly" ? $("monthly-books-root") : $("data-input-root");
    }

    function setBooksStatus(text) {
        ["di-status", "mb-status"].forEach((id) => {
            const el = document.getElementById(id);
            if (el) el.textContent = text;
        });
    }

    function getBooksStatus() {
        return document.getElementById("di-status")?.textContent || document.getElementById("mb-status")?.textContent || "";
    }

    function isLocationSelect(id) {
        return id === "di-location" || id === "mb-location";
    }

    function isMonthSelect(id) {
        return id === "di-month" || id === "mb-month";
    }

    function isReloadButton(id) {
        return id === "di-reload" || id === "mb-reload";
    }

    function renderBooksToolbar(prefix) {
        return `
            <div class="books-toolbar">
                <label class="books-label">Facility
                    <select id="${prefix}-location" class="books-select">
                        ${locations.map((l) => `<option value="${l.id}"${l.id === state.locationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`).join("")}
                    </select>
                </label>
                <label class="books-label">Month
                    <select id="${prefix}-month" class="books-select">${monthOptions()}</select>
                </label>
                <button type="button" class="btn btn-nav-outline" id="${prefix}-reload">Load</button>
                <span class="books-status" id="${prefix}-status"></span>
            </div>`;
    }

    async function openMonthlyBooksPanel() {
        if (!confirmDiscardDirty()) return;
        syncFromForm();
        if (window.showDashboardPanel) await showDashboardPanel("monthly-books");
    }

    function currentUserLabel() {
        const authUser = window.oplixAuth?.currentUser;
        return authUser?.email || authUser?.displayName || userId || "unknown";
    }

    function formatDayLabel(dayId) {
        const [y, m, d] = String(dayId).split("-").map(Number);
        const date = new Date(y, m - 1, d);
        return date.toLocaleDateString("en-US", {
            weekday: "long",
            month: "long",
            day: "numeric",
            year: "numeric",
        });
    }

    function refreshEntryDayId() {
        state.entryDayId = M().defaultEntryDayId(state.monthId, state.daysById);
    }

    function isViewingClosedDay() {
        return M().isDayClosed(state.day);
    }

    function isViewingClosedMonth() {
        return M().isMonthClosed(state.month);
    }

    function isBooksLocked() {
        return isViewingClosedDay() || isViewingClosedMonth();
    }

    function formatMonthLabel(monthId) {
        const [y, m] = String(monthId).split("-").map(Number);
        return new Date(y, m - 1, 1).toLocaleDateString("en-US", { month: "long", year: "numeric" });
    }

    function monthAggregate() {
        return M().aggregateMonth(state.month, state.daysById, {
            hasGasStation: hasGasStation(),
            booksFieldConfig: booksFieldConfig(),
        });
    }

    function confirmDiscardDirty() {
        if (!state.dirty) return true;
        return window.confirm("You have unsaved changes on this day. Discard them?");
    }

    function switchDay(dayId) {
        if (dayId === state.dayId) return true;
        if (!confirmDiscardDirty()) return false;
        state.dayId = dayId;
        state.day = M().normalizeDayDoc(state.daysById[state.dayId]);
        state.dirty = false;
        render();
        return true;
    }

    async function closeCurrentDay(options = {}) {
        if (isViewingClosedDay() || isViewingClosedMonth()) return;
        if (state.dirty) {
            normalizeAllAmountFields();
            syncFromForm();
        }
        const hasData = M().dayHasEntryData({ ...state.day, _dayId: state.dayId }, { hasGasStation: hasGasStation() });
        if (!options.skipConfirm) {
            if (!hasData) {
                const ok = window.confirm(
                    "This day has no entry data yet. Close it anyway? You can reopen later to enter numbers."
                );
                if (!ok) return;
            } else if (
                !window.confirm(
                    "Close this day? It will be read-only until you reopen it. Use this after entry is complete."
                )
            ) {
                return;
            }
        }
        if (state.dirty) await saveDay({ silent: true, skipClosePrompt: true });
        state.day.closed = true;
        state.day.closedAt = new Date().toISOString();
        state.day.closedBy = currentUserLabel();
        setBooksStatus("Closing day…");
        await Store().saveDay(userId, state.locationId, state.monthId, state.dayId, state.day);
        state.daysById[state.dayId] = { ...state.day, _dayId: state.dayId };
        window.OplixAnalytics?.invalidateCache?.();
        refreshEntryDayId();
        state.dirty = false;
        switchDay(state.entryDayId);
        setBooksStatus("Day closed.");
        setTimeout(() => {
            if (getBooksStatus() === "Day closed.") setBooksStatus("");
        }, 2000);
    }

    async function reopenCurrentDay() {
        if (!isViewingClosedDay() || isViewingClosedMonth()) return;
        if (
            !window.confirm(
                "Reopen this day for editing? Anyone with access can change numbers until it is closed again."
            )
        ) {
            return;
        }
        state.day.closed = false;
        state.day.closedAt = null;
        state.day.closedBy = null;
        setBooksStatus("Reopening…");
        await Store().saveDay(userId, state.locationId, state.monthId, state.dayId, state.day);
        state.daysById[state.dayId] = { ...state.day, _dayId: state.dayId };
        window.OplixAnalytics?.invalidateCache?.();
        refreshEntryDayId();
        state.dirty = false;
        render();
        setBooksStatus("Day reopened.");
        setTimeout(() => {
            if (getBooksStatus() === "Day reopened.") setBooksStatus("");
        }, 2000);
    }

    async function closeCurrentMonth() {
        if (isViewingClosedMonth()) return;
        normalizeAllAmountFields();
        syncFromForm();
        const health = M().booksHealthSummary(state.monthId, state.daysById, state.month, {
            hasGasStation: hasGasStation(),
        });
        const openPay = (state.payables || []).filter((p) => !p.isPaid).length;
        const warnings = [];
        if (health.unclosedWithData > 0) {
            warnings.push(
                `${health.unclosedWithData} day${health.unclosedWithData === 1 ? "" : "s"} with entry not closed`
            );
        }
        if (openPay > 0) {
            warnings.push(`${openPay} open payable${openPay === 1 ? "" : "s"}`);
        }
        let msg = `Close ${formatMonthLabel(state.monthId)} for ${currentLocation()?.name || "this facility"}?\n\nThe whole month will be read-only until reopened.`;
        if (warnings.length) {
            msg += `\n\nStill open:\n• ${warnings.join("\n• ")}`;
            if (health.unclosedWithData > 0) {
                msg += "\n\nClose those days first, or continue anyway.";
            }
        }
        if (!window.confirm(msg)) return;
        if (health.unclosedWithData > 0) {
            if (
                !window.confirm(
                    `${health.unclosedWithData} day(s) with entry are still open. Close the month anyway?`
                )
            ) {
                return;
            }
        }
        if (state.dirty) await saveMonth({ silent: true });
        state.month.closed = true;
        state.month.closedAt = new Date().toISOString();
        state.month.closedBy = currentUserLabel();
        setBooksStatus("Closing month…");
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        window.OplixAnalytics?.invalidateCache?.();
        state.dirty = false;
        render();
        setBooksStatus("Month closed.");
        setTimeout(() => {
            if (getBooksStatus() === "Month closed.") setBooksStatus("");
        }, 2000);
    }

    async function reopenCurrentMonth() {
        if (!isViewingClosedMonth()) return;
        if (
            !window.confirm(
                "Reopen this month for editing? Daily sheets, utilities, payables, and adjustments can be changed again."
            )
        ) {
            return;
        }
        state.month.closed = false;
        state.month.closedAt = null;
        state.month.closedBy = null;
        setBooksStatus("Reopening month…");
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        window.OplixAnalytics?.invalidateCache?.();
        state.dirty = false;
        render();
        setBooksStatus("Month reopened.");
        setTimeout(() => {
            if (getBooksStatus() === "Month reopened.") setBooksStatus("");
        }, 2000);
    }

    function renderMonthStatusBanner(options = {}) {
        const { onMonthlyPanel = false, onDailyPanel = false } = options;
        const label = formatMonthLabel(state.monthId);
        if (isViewingClosedMonth()) {
            const at = state.month.closedAt
                ? new Date(state.month.closedAt).toLocaleString("en-US", {
                      dateStyle: "medium",
                      timeStyle: "short",
                  })
                : "";
            const by = state.month.closedBy || "";
            return `<div class="books-day-banner books-day-banner--closed books-month-banner" role="status">
                <div class="books-day-banner-text">
                    <strong>${escapeHtml(label)}</strong>
                    <span class="books-day-banner-tag">Month closed</span>
                    ${at ? `<span class="books-day-banner-meta">Closed ${escapeHtml(at)}${by ? ` · ${escapeHtml(by)}` : ""}</span>` : ""}
                </div>
                <div class="books-day-banner-actions">
                    ${onDailyPanel ? `<button type="button" class="btn btn-nav-outline" id="di-open-monthly-books">Open Monthly books</button>` : ""}
                    ${onMonthlyPanel || onDailyPanel ? `<button type="button" class="btn" id="di-reopen-month">Reopen month</button>` : ""}
                </div>
            </div>`;
        }
        if (!onMonthlyPanel) return "";
        return `<div class="books-day-banner books-day-banner--open books-month-banner" role="status">
            <div class="books-day-banner-text">
                <span class="books-day-banner-tag books-day-banner-tag--entry">Month open</span>
                <strong>${escapeHtml(label)}</strong>
                <span class="books-day-banner-meta">Review final math below, add month adjustments, then close the month.</span>
            </div>
        </div>`;
    }

    function renderDayStatusBanner() {
        const label = formatDayLabel(state.dayId);
        if (isViewingClosedDay()) {
            const at = state.day.closedAt
                ? new Date(state.day.closedAt).toLocaleString("en-US", {
                      dateStyle: "medium",
                      timeStyle: "short",
                  })
                : "";
            const by = state.day.closedBy || "";
            return `<div class="books-day-banner books-day-banner--closed" role="status">
                <div class="books-day-banner-text">
                    <strong>${escapeHtml(label)}</strong>
                    <span class="books-day-banner-tag">Closed</span>
                    ${at ? `<span class="books-day-banner-meta">Closed ${escapeHtml(at)}${by ? ` · ${escapeHtml(by)}` : ""}</span>` : ""}
                </div>
                <div class="books-day-banner-actions">
                    <button type="button" class="btn btn-nav-outline" id="di-return-entry">Return to entry day</button>
                    ${isViewingClosedMonth() ? "" : `<button type="button" class="btn" id="di-reopen-day">Reopen day</button>`}
                </div>
            </div>`;
        }
        const showReturn = state.dayId !== state.entryDayId;
        return `<div class="books-day-banner books-day-banner--open" role="status">
            <div class="books-day-banner-text">
                <span class="books-day-banner-tag books-day-banner-tag--entry">Entry</span>
                <strong>${escapeHtml(label)}</strong>
            </div>
            <div class="books-day-banner-actions">
                ${showReturn ? `<button type="button" class="btn btn-nav-outline" id="di-return-entry">Return to entry day</button>` : ""}
                ${isViewingClosedMonth() ? "" : `<button type="button" class="btn btn-nav-outline" id="di-close-day">Close day</button>`}
            </div>
        </div>`;
    }

    function renderClosedDayTiles() {
        const closedIds = M().listClosedDayIds(state.monthId, state.daysById);
        if (!closedIds.length) {
            return `<section class="books-closed-days" aria-label="Closed days">
                <h3 class="books-subtitle books-closed-days-title">Closed days</h3>
                <p class="books-hint">No closed days this month. Use <strong>Close day</strong> after saving entry to lock a day.</p>
            </section>`;
        }
        const tiles = closedIds
            .map((id) => {
                const [y, m, d] = id.split("-").map(Number);
                const date = new Date(y, m - 1, d);
                const short = date.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
                const active = id === state.dayId ? " books-closed-day-tile--active" : "";
                return `<button type="button" class="books-closed-day-tile${active}" data-di-closed-tile="${escapeHtml(id)}" title="${escapeHtml(formatDayLabel(id))}">${escapeHtml(short)}</button>`;
            })
            .join("");
        return `<section class="books-closed-days" aria-label="Closed days">
            <h3 class="books-subtitle books-closed-days-title">Closed days</h3>
            <p class="books-hint">Tap a closed day to view. Reopen to edit.</p>
            <div class="books-closed-days-tiles">${tiles}</div>
        </section>`;
    }

    const EXPENSE_DESC_LISTS = new Set(["cashExpenses", "checksAch", "otherExpenses"]);
    const EXPENSE_DESC_DATALIST_ID = "di-expense-desc-list";

    function expenseDescStorageKey() {
        return `oplix.expenseDescriptions.${userId || "anon"}.${state.locationId || "none"}`;
    }

    function loadStoredExpenseDescriptions() {
        try {
            const raw = localStorage.getItem(expenseDescStorageKey());
            const parsed = raw ? JSON.parse(raw) : [];
            return Array.isArray(parsed) ? parsed : [];
        } catch {
            return [];
        }
    }

    function saveStoredExpenseDescriptions(list) {
        try {
            localStorage.setItem(expenseDescStorageKey(), JSON.stringify(list.slice(0, 300)));
        } catch {
            /* ignore quota */
        }
    }

    function collectExpenseDescriptionsFromDays(daysById) {
        const out = [];
        Object.values(daysById || {}).forEach((rawDay) => {
            const day = M().normalizeDayDoc(rawDay);
            EXPENSE_DESC_LISTS.forEach((key) => {
                (day[key] || []).forEach((row) => {
                    const d = String(row.description || "").trim();
                    if (d) out.push(d);
                });
            });
        });
        return out;
    }

    function mergeExpenseDescriptions(...sources) {
        const seen = new Set();
        const out = [];
        sources.forEach((list) => {
            (list || []).forEach((item) => {
                const d = String(item || "").trim();
                if (!d) return;
                const key = d.toLowerCase();
                if (seen.has(key)) return;
                seen.add(key);
                out.push(d);
            });
        });
        return out.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
    }

    function refreshExpenseDescriptions() {
        if (!state.locationId) {
            state.expenseDescriptions = [];
            return;
        }
        state.expenseDescriptions = mergeExpenseDescriptions(
            loadStoredExpenseDescriptions(),
            collectExpenseDescriptionsFromDays(state.daysById)
        );
        saveStoredExpenseDescriptions(state.expenseDescriptions);
    }

    function rememberExpenseDescriptionsFromDay(day) {
        const normalized = M().normalizeDayDoc(day);
        const fresh = collectExpenseDescriptionsFromDays({ _: normalized });
        if (!fresh.length) return;
        state.expenseDescriptions = mergeExpenseDescriptions(fresh, state.expenseDescriptions);
        saveStoredExpenseDescriptions(state.expenseDescriptions);
    }

    function addExpenseDescription(text) {
        const d = String(text || "").trim();
        if (!d) return;
        state.expenseDescriptions = mergeExpenseDescriptions([d], state.expenseDescriptions);
        saveStoredExpenseDescriptions(state.expenseDescriptions);
    }

    function renderExpenseDescDatalist() {
        const items = state.expenseDescriptions || [];
        if (!items.length) return "";
        return `<datalist id="${EXPENSE_DESC_DATALIST_ID}">
            ${items.map((d) => `<option value="${escapeHtml(d)}"></option>`).join("")}
        </datalist>`;
    }

    function mergedUtilityKeys() {
        return M().mergeUtilityKeys(state.utilityProviders, state.month.utilities);
    }

    function canDeleteUtility(key) {
        return !M().isStandardUtilityKey(key);
    }

    async function addUtility() {
        const label = window.prompt("Utility name (e.g. Sewer, Phone):");
        if (!label || !String(label).trim()) return;
        const customLabel = String(label).trim();
        const utilityType = M().slugUtilityKey(customLabel);
        if (mergedUtilityKeys().some((u) => u.key === utilityType)) {
            window.alert("That utility already exists for this facility.");
            return;
        }
        if (!DirStore() || !DirModel()) {
            window.alert("Utility directory is unavailable.");
            return;
        }
        syncFromForm();
        setBooksStatus("Adding utility…");
        const payload = DirModel().normalizeUtilityProvider({
            utilityType,
            customLabel,
            isDefault: false,
            active: true,
        });
        await DirStore().save(
            userId,
            state.locationId,
            DirModel().COLLECTIONS.utilityProviders,
            utilityType,
            payload
        );
        state.month.utilities[utilityType] = 0;
        await loadUtilityProviders();
        state.month.utilities = M().normalizeMonthUtilities(
            state.month.utilities,
            mergedUtilityKeys()
        );
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        setBooksStatus("Utility added.");
        render();
        setTimeout(() => {
            if (getBooksStatus() === "Utility added.") setBooksStatus("");
        }, 2000);
    }

    async function deleteUtility(key) {
        if (!canDeleteUtility(key)) {
            window.alert("Default utilities (Internet, Water, Electric, etc.) cannot be removed.");
            return;
        }
        const row = mergedUtilityKeys().find((u) => u.key === key);
        const label = row?.label || key;
        if (!window.confirm(`Remove "${label}" from this facility? Monthly amounts for it will be cleared.`)) {
            return;
        }
        syncFromForm();
        setBooksStatus("Removing…");
        if (DirStore() && DirModel()) {
            const hasProvider = state.utilityProviders.some(
                (p) => (p.utilityType || p.id) === key
            );
            if (hasProvider) {
                await DirStore().remove(
                    userId,
                    state.locationId,
                    DirModel().COLLECTIONS.utilityProviders,
                    key
                );
            }
        }
        delete state.month.utilities[key];
        await loadUtilityProviders();
        state.month.utilities = M().normalizeMonthUtilities(
            state.month.utilities,
            mergedUtilityKeys()
        );
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        setBooksStatus("Utility removed.");
        render();
        setTimeout(() => {
            if (getBooksStatus() === "Utility removed.") setBooksStatus("");
        }, 2000);
    }

    async function loadPayables() {
        if (!state.locationId || !window.OplixPayablesStore) {
            state.payables = [];
            return;
        }
        state.payables = await OplixPayablesStore.list(userId, state.locationId);
    }

    async function loadReceivables() {
        if (!state.locationId || !window.OplixReceivablesStore) {
            state.receivables = [];
            return;
        }
        state.receivables = await OplixReceivablesStore.list(userId, state.locationId);
    }

    async function syncMonthFromReceivable(receivable) {
        if (!window.OplixBooksLinks?.persistReceivableBooksSync) return;
        const result = await OplixBooksLinks.persistReceivableBooksSync(
            userId,
            state.locationId,
            receivable,
            state.monthId
        );
        if (result && result.monthId === state.monthId) state.month = result.month;
    }

    function renderBooksHealthStrip() {
        const h = M().booksHealthSummary(state.monthId, state.daysById, state.month, {
            hasGasStation: hasGasStation(),
        });
        const openPay = (state.payables || []).filter((p) => !p.isPaid).length;
        const monthTag = isViewingClosedMonth()
            ? `<span class="books-health-warn">Month closed</span>`
            : "";
        const warn =
            h.unclosedWithData > 0
                ? `<span class="books-health-warn">${h.unclosedWithData} day${h.unclosedWithData === 1 ? "" : "s"} with entry not closed</span>`
                : "";
        return `<div class="books-health-strip" role="status">
            <span><strong>${h.daysWithData}</strong> / ${h.daysInMonth} days with entry</span>
            <span><strong>${h.daysClosed}</strong> closed</span>
            <span><strong>${openPay}</strong> open payables</span>
            <span><strong>${h.monthReceivablesLines}</strong> month credits (Net)</span>
            ${monthTag}
            ${warn}
        </div>`;
    }

    function renderMonthlyCloseChecklist(health, openPay) {
        const items = [
            {
                ok: health.daysWithData > 0,
                label: `${health.daysWithData} day${health.daysWithData === 1 ? "" : "s"} with entry`,
            },
            {
                ok: health.unclosedWithData === 0,
                warn: health.unclosedWithData > 0,
                label:
                    health.unclosedWithData > 0
                        ? `${health.unclosedWithData} day${health.unclosedWithData === 1 ? "" : "s"} with entry not closed`
                        : "All entered days closed",
            },
            {
                ok: openPay === 0,
                warn: openPay > 0,
                label: openPay > 0 ? `${openPay} open payable${openPay === 1 ? "" : "s"}` : "No open payables",
            },
            {
                ok: true,
                label: `${health.monthReceivablesLines} month credit line${health.monthReceivablesLines === 1 ? "" : "s"} (Net)`,
            },
        ];
        return `<ul class="books-month-checklist">
            ${items
                .map((item) => {
                    const cls = item.warn ? " books-month-checklist-item--warn" : item.ok ? " books-month-checklist-item--ok" : "";
                    const icon = item.warn ? "!" : item.ok ? "✓" : "·";
                    return `<li class="books-month-checklist-item${cls}"><span class="books-month-check-icon">${icon}</span>${escapeHtml(item.label)}</li>`;
                })
                .join("")}
        </ul>`;
    }

    function renderMonthAdjustments(closed) {
        const list = state.month.monthAdjustments || [];
        const fieldsetAttr = closed ? " disabled" : "";
        return `
            <fieldset class="books-fieldset"${fieldsetAttr}>
                <h3 class="books-subtitle">Month adjustments</h3>
                <p class="books-hint">Catch-all lines for anything not on daily sheets or other tabs — bank fees, corrections, one-off credits. Expenses reduce Net; credits increase Net.</p>
                <div class="books-lines books-month-adj-lines" data-di-list="monthAdjustments">
                    <div class="books-lines-head books-month-adj-head">
                        <span>Description</span>
                        <span>Type</span>
                        <span>Amount</span>
                        <span></span>
                    </div>
                    ${list
                        .map((row) => {
                            const kind = row.kind === "credit" ? "credit" : "expense";
                            return `
                    <div class="books-lines-row books-month-adj-row" data-di-row="${escapeHtml(row.id)}">
                        <input type="text" class="books-input" name="description" value="${escapeHtml(row.description || "")}" placeholder="e.g. Bank fee, correction">
                        <select class="books-select" name="kind">
                            <option value="expense"${kind === "expense" ? " selected" : ""}>Expense</option>
                            <option value="credit"${kind === "credit" ? " selected" : ""}>Credit</option>
                        </select>
                        <input ${amountInputAttrs("amount", row.amount)}>
                        <button type="button" class="books-rm" data-di-rm="${escapeHtml(row.id)}" data-di-list="monthAdjustments">×</button>
                    </div>`;
                        })
                        .join("")}
                    ${closed ? "" : `<button type="button" class="books-add-line" data-di-add="monthAdjustments">+ Add adjustment</button>`}
                </div>
            </fieldset>`;
    }

    function renderMonthlyBooks() {
        const agg = monthAggregate();
        const health = M().booksHealthSummary(state.monthId, state.daysById, state.month, {
            hasGasStation: hasGasStation(),
        });
        const openPay = (state.payables || []).filter((p) => !p.isPaid).length;
        const closed = isViewingClosedMonth();
        const fieldsetAttr = closed ? " disabled" : "";
        const linkedRec = (state.receivables || []).filter((r) => r.isReceived).length;
        const openRec = (state.receivables || []).filter((r) => !r.isReceived).length;

        const pnlRows = [
            { label: "Sales (merch / register)", amount: agg.sales, kind: "plus" },
            ...(hasGasStation()
                ? [
                      { label: "Fuel ($)", amount: agg.fuelDollars, kind: "info" },
                      { label: "Credit card (register)", amount: agg.creditCard, kind: "info" },
                  ]
                : []),
            { label: "Month credits (Net)", amount: agg.receivablesTotal, kind: "plus" },
            ...(agg.monthAdjustmentsCredit > 0
                ? [{ label: "Month adjustment credits", amount: agg.monthAdjustmentsCredit, kind: "plus" }]
                : []),
            { label: "Cash expenses (daily)", amount: agg.cashExpense, kind: "minus" },
            { label: "Checks / ACH", amount: agg.checksAch, kind: "minus" },
            { label: "Other daily expenses", amount: agg.otherExpense, kind: "minus" },
            { label: "Utilities", amount: agg.utilitiesTotal, kind: "minus" },
            { label: "Payroll", amount: agg.payrollTotal, kind: "minus" },
            ...(agg.salesTax ? [{ label: "Sales tax", amount: agg.salesTax, kind: "minus" }] : []),
            ...(agg.accountant ? [{ label: "Accountant", amount: agg.accountant, kind: "minus" }] : []),
            ...(agg.monthAdjustmentsExpense > 0
                ? [{ label: "Month adjustment expenses", amount: agg.monthAdjustmentsExpense, kind: "minus" }]
                : []),
        ];

        return `
            <div class="books-panel books-monthly-panel data-input-form">
                ${renderMonthStatusBanner({ onMonthlyPanel: true })}
                <p class="books-hint">Use <strong>Daily books</strong> for daily entry, utilities, payables, and receivables. This screen rolls everything up and is where you <strong>close the month</strong>.</p>

                <div class="books-month-grid">
                    <section class="books-month-section">
                        <h3 class="books-subtitle">Pre-close checklist</h3>
                        ${renderMonthlyCloseChecklist(health, openPay)}
                        <p class="books-hint books-month-tab-hint">Utilities & payroll: <strong>Utilities & payroll</strong> tab · Payables: <strong>Payables</strong> · Receivables: <strong>Receivables</strong> (${linkedRec} received, ${openRec} open)</p>
                    </section>

                    <section class="books-month-section">
                        <h3 class="books-subtitle">Month totals</h3>
                        <div class="an-kpi-row books-month-kpis">
                            <div class="an-kpi"><span>Sales</span><strong>${money(agg.sales)}</strong></div>
                            <div class="an-kpi"><span>Expenses</span><strong>${money(agg.expenses)}</strong></div>
                            <div class="an-kpi"><span>Net</span><strong class="${agg.net >= 0 ? "pos" : "neg"}">${money(agg.net)}</strong></div>
                            <div class="an-kpi"><span>Over / short</span><strong>${money(agg.totalOverShort)}</strong></div>
                        </div>
                    </section>
                </div>

                <section class="books-month-section">
                    <h3 class="books-subtitle">Final math (P&amp;L)</h3>
                    <div class="home-card home-cc-table-wrap">
                        <table class="home-cc-table books-month-pnl">
                            <tbody>
                                ${pnlRows
                                    .map((row) => {
                                        if (row.kind === "info") {
                                            return `<tr class="books-month-pnl-info"><td>${escapeHtml(row.label)}</td><td class="home-cc-num">${money(row.amount)}</td></tr>`;
                                        }
                                        const prefix = row.kind === "minus" ? "−" : row.kind === "plus" ? "+" : "";
                                        return `<tr><td>${escapeHtml(row.label)}</td><td class="home-cc-num">${prefix}${money(row.amount)}</td></tr>`;
                                    })
                                    .join("")}
                                <tr class="an-total-row">
                                    <td><strong>Net</strong></td>
                                    <td class="home-cc-num"><strong class="${agg.net >= 0 ? "pos" : "neg"}">${money(agg.net)}</strong></td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </section>

                ${renderMonthAdjustments(closed)}

                <fieldset class="books-fieldset"${fieldsetAttr}>
                    <label class="books-label">Close notes (optional)
                        <textarea class="books-input books-textarea" id="di-close-notes" rows="2" placeholder="Accountant sign-off, items to review next month…">${escapeHtml(state.month.closeNotes || "")}</textarea>
                    </label>
                </fieldset>

                <div class="books-month-actions">
                    ${closed ? "" : `<button type="button" class="btn books-save" id="di-save-month">Save month adjustments</button>`}
                    ${
                        closed
                            ? `<button type="button" class="btn" id="di-reopen-month">Reopen month</button>`
                            : `<button type="button" class="btn btn-nav-outline" id="di-close-month">Close month</button>`
                    }
                </div>
            </div>`;
    }

    function renderLegacyMonthReceivables() {
        const manual = (state.month.receivables || []).filter((r) => !r.linkedReceivableId);
        if (!manual.length) return "";
        const closed = isViewingClosedMonth();
        const fieldsetAttr = closed ? " disabled" : "";
        return `
            <div class="books-panel books-legacy-receivables data-input-form">
                <h3 class="books-subtitle">Legacy month credits</h3>
                <p class="books-hint">Older lines entered only on the month doc. New items should use <strong>Add receivable</strong> above — marking received syncs to Books Net automatically.</p>
                <fieldset class="books-fieldset"${fieldsetAttr}>
                ${renderLineList(
                    "receivables",
                    [
                        { name: "description", label: "Description" },
                        { name: "amount", label: "Amount", type: "number" },
                    ],
                    null,
                    true
                )}
                </fieldset>
                ${closed ? "" : `<button type="button" class="btn books-save" id="di-save-month">Save legacy credits</button>`}
            </div>`;
    }

    function renderChecksAchList() {
        const list = state.day.checksAch || [];
        const openPayables = window.OplixBooksLinks
            ? OplixBooksLinks.openPayablesForPick(state.payables)
            : (state.payables || []).filter((p) => !p.isPaid);
        const payableOptions = (selectedId) => {
            const opts = ['<option value="">— Payable —</option>'];
            openPayables.forEach((p) => {
                const label = window.OplixBooksLinks
                    ? OplixBooksLinks.payablePickLabel(p)
                    : `${p.payTo} — ${money(p.amount)}`;
                opts.push(
                    `<option value="${escapeHtml(p.id)}"${p.id === selectedId ? " selected" : ""}>${escapeHtml(label)}</option>`
                );
            });
            (state.payables || [])
                .filter((p) => p.isPaid && p.id === selectedId)
                .forEach((p) => {
                    opts.push(
                        `<option value="${escapeHtml(p.id)}" selected>${escapeHtml(p.payTo || "Paid")} (paid)</option>`
                    );
                });
            return opts.join("");
        };
        return `
            <h3 class="books-subtitle">Checks / ACH</h3>
            <p class="books-hint">Link a line to an open payable to mark it paid when you save this day.</p>
            <div class="books-lines books-lines--checks" data-di-list="checksAch">
                <div class="books-lines-head books-lines-head--checks">
                    <span>Payable</span>
                    <span>Description</span>
                    <span>Check #</span>
                    <span>Amount</span>
                    <span></span>
                </div>
                ${list
                    .map((row) => {
                        const pid = row.payableId || "";
                        return `
                    <div class="books-lines-row books-lines-row--checks" data-di-row="${escapeHtml(row.id)}">
                        <select class="books-select" name="payableId" data-di-payable-pick="${escapeHtml(row.id)}">${payableOptions(pid)}</select>
                        <input type="text" class="books-input" name="description" list="${EXPENSE_DESC_DATALIST_ID}" autocomplete="off" value="${escapeHtml(row.description || "")}" placeholder="Description">
                        <input type="text" class="books-input" name="checkNo" value="${escapeHtml(row.checkNo || "")}">
                        <input ${amountInputAttrs("amount", row.amount)}>
                        <button type="button" class="books-rm" data-di-rm="${escapeHtml(row.id)}" data-di-list="checksAch">×</button>
                    </div>`;
                    })
                    .join("")}
                <button type="button" class="books-add-line" data-di-add="checksAch">+ Add check / ACH</button>
            </div>`;
    }

    async function recordCheckFromPayable(payable) {
        if (isViewingClosedDay()) {
            window.alert("This day is closed. Reopen it or choose another day to record the check.");
            return;
        }
        normalizeAllAmountFields();
        syncFromForm();
        state.day.checksAch = state.day.checksAch || [];
        state.day.checksAch.push({
            id: lineId(),
            date: state.dayId,
            description: payable.payTo || "",
            checkNo: "",
            amount: M().num(payable.amount),
            payableId: payable.id,
        });
        state.dirty = true;
        await saveDay({ silent: true, skipClosePrompt: true });
        await loadPayables();
        if (state.tab !== "daily") {
            state.tab = "daily";
            render();
        }
    }

    async function syncPayablesFromChecks() {
        if (!window.OplixPayablesStore) return;
        for (const row of state.day.checksAch || []) {
            if (!row.payableId) continue;
            const p = state.payables.find((x) => x.id === row.payableId);
            if (!p || p.isPaid) continue;
            if (M().num(row.amount) <= 0) continue;
            await OplixPayablesStore.markPaid(userId, state.locationId, {
                ...p,
                payTo: String(row.description || p.payTo).trim() || p.payTo,
                amount: M().num(row.amount) || p.amount,
            });
        }
        await loadPayables();
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

    function booksFieldConfig() {
        if (!FC()) return null;
        return FC().normalizeBooksFieldConfig(currentLocation()?.booksFieldConfig, hasGasStation());
    }

    function showField(fieldId) {
        if (!FC()) return true;
        return FC().fieldEnabled(booksFieldConfig(), fieldId, hasGasStation());
    }

    function enabledCustomFields(group) {
        if (!FC()) return [];
        return FC().enabledCustomFields(booksFieldConfig(), group);
    }

    function renderCustomBooksFields(group, amounts) {
        const fields = enabledCustomFields(group);
        if (!fields.length) return "";
        const vals = amounts || {};
        return `
            <h3 class="books-subtitle">Custom fields</h3>
            <div class="books-grid-2 books-custom-fields">
                ${fields
                    .map(
                        (cf) => `
                <label class="books-label">${escapeHtml(cf.label)} ($)
                    <input ${amountInputAttrs(`custom_${cf.id}`, vals[cf.id])}>
                </label>`
                    )
                    .join("")}
            </div>`;
    }

    function syncCustomAmountsFromDom(root, target, group) {
        if (!target.customAmounts) target.customAmounts = {};
        enabledCustomFields(group).forEach((cf) => {
            const el = root.querySelector(`[name="custom_${cf.id}"]`);
            if (el) target.customAmounts[cf.id] = M().num(el.value);
        });
    }

    function tabVisible(tabId) {
        if (!FC()) return true;
        return FC().tabEnabled(booksFieldConfig(), tabId, hasGasStation());
    }

    function amountValue(v) {
        if (v == null || v === "") return "";
        if (M().num(v) === 0) return "";
        return M().formatAmountForInput(v);
    }

    function normalizeAllAmountFields() {
        ["data-input-root", "monthly-books-root"].forEach((rootId) => {
            const root = document.getElementById(rootId);
            if (!root) return;
            root.querySelectorAll(".books-input-amount").forEach(normalizeAmountField);
        });
    }

    function amountInputAttrs(name, value) {
        return `type="text" inputmode="decimal" autocomplete="off" class="books-input books-input-amount" name="${name}" value="${escapeHtml(amountValue(value))}"`;
    }

    function normalizeAmountField(el) {
        if (!el || !el.classList.contains("books-input-amount")) return;
        const raw = String(el.value ?? "").trim();
        if (raw === "") {
            el.value = "";
            return;
        }
        const n = M().parseAmountExpression(raw);
        if (Number.isFinite(n)) {
            el.value = n === 0 ? "" : M().formatAmountForInput(n);
        }
    }

    function bindPanelShell(panel) {
        if (!panel || panel.dataset.diBound) return;
        panel.dataset.diBound = "1";

        panel.addEventListener("change", async (e) => {
            if (isLocationSelect(e.target.id)) {
                if (!confirmDiscardDirty()) {
                    e.target.value = state.locationId;
                    return;
                }
                state.locationId = e.target.value;
                await loadCurrent();
                return;
            }
            if (isMonthSelect(e.target.id)) {
                state.monthId = e.target.value;
                return;
            }
            if (e.target.id === "di-day") {
                if (!switchDay(e.target.value)) e.target.value = state.dayId;
                return;
            }
            if (e.target.matches("[name='payableId']")) {
                const rowId = e.target.dataset.diPayablePick;
                if (rowId && e.target.value) applyPayablePick(rowId, e.target.value);
                return;
            }
            if (
                state.tab === "cash-recon" &&
                e.target.name &&
                String(e.target.name).startsWith("cr_")
            ) {
                syncFromForm();
                state.dirty = true;
                render();
            }
        });

        panel.addEventListener("click", (e) => {
            const tab = e.target.closest("[data-di-tab]");
            if (tab) {
                if (!confirmDiscardDirty()) return;
                syncFromForm();
                state.tab = tab.dataset.diTab;
                render();
                return;
            }
            if (isReloadButton(e.target.id)) {
                if (!confirmDiscardDirty()) return;
                loadCurrent();
                return;
            }
            if (e.target.id === "di-close-day") {
                closeCurrentDay();
                return;
            }
            if (e.target.id === "di-close-month") {
                closeCurrentMonth();
                return;
            }
            if (e.target.id === "di-reopen-month") {
                reopenCurrentMonth();
                return;
            }
            if (e.target.id === "di-open-monthly-books") {
                openMonthlyBooksPanel();
                return;
            }
            if (e.target.id === "di-reopen-day") {
                reopenCurrentDay();
                return;
            }
            if (e.target.id === "di-return-entry") {
                switchDay(state.entryDayId);
                return;
            }
            const closedTile = e.target.closest("[data-di-closed-tile]");
            if (closedTile) {
                switchDay(closedTile.dataset.diClosedTile);
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
            if (e.target.id === "di-open-books-config" && state.locationId) {
                if (window.showDashboardPanel) showDashboardPanel("facilities");
                if (window.OplixFacilities?.openCustomize) {
                    OplixFacilities.openCustomize(state.locationId, { focusBooks: true });
                } else if (window.OplixFacilities?.openBooksConfig) {
                    OplixFacilities.openBooksConfig(state.locationId);
                }
                return;
            }
            const add = e.target.closest("[data-di-add]");
            if (add) {
                if (isViewingClosedDay() || isViewingClosedMonth()) return;
                addLine(add.dataset.diAdd);
                render();
                return;
            }
            const rm = e.target.closest("[data-di-rm]");
            if (rm) {
                if (isViewingClosedDay() || isViewingClosedMonth()) return;
                removeLine(rm.dataset.diList, rm.dataset.diRm);
                render();
                return;
            }
            if (e.target.closest("[data-di-util-add]")) {
                addUtility();
                return;
            }
            const utilRm = e.target.closest("[data-di-util-rm]");
            if (utilRm) {
                deleteUtility(utilRm.dataset.diUtilRm);
            }
            const payoutAdd = e.target.closest("[data-cr-payout-add]");
            if (payoutAdd) {
                syncFromForm();
                const entry = reconEntryFromPrefix(payoutAdd.dataset.crPayoutAdd);
                if (entry) {
                    if (!entry.payOuts) entry.payOuts = [];
                    entry.payOuts = M().pruneEmptyPayOuts(entry.payOuts);
                    entry.payOuts.push({ id: lineId(), description: "", amount: 0 });
                    render();
                }
                return;
            }
            const payoutRm = e.target.closest("[data-cr-payout-rm]");
            if (payoutRm) {
                syncFromForm();
                const entry = reconEntryFromPrefix(payoutRm.dataset.crPayoutRm);
                const payoutId = payoutRm.dataset.payoutId;
                if (entry && payoutId) {
                    entry.payOuts = (entry.payOuts || []).filter((line) => line.id !== payoutId);
                    render();
                }
                return;
            }
        });

        panel.addEventListener("focusout", (e) => {
            const input = e.target;
            if (input?.name !== "description") return;
            const listKey = input.closest("[data-di-list]")?.dataset?.diList;
            if (!listKey || !EXPENSE_DESC_LISTS.has(listKey)) return;
            addExpenseDescription(input.value);
        });

        panel.addEventListener("focusin", (e) => {
            const el = e.target;
            if (!el.classList?.contains("books-input-amount")) return;
            if (!el.closest(".data-input-form, [data-pay-section]")) return;
            if (String(el.value ?? "").trim() === "0") el.value = "";
        });

        panel.addEventListener("input", (e) => {
            if (!e.target.closest(".data-input-form")) return;
            if (isViewingClosedDay() || isViewingClosedMonth()) return;
            if (e.target.name === "fuel_gallons") {
                const root = $("data-input-root");
                ["fuel_regular", "fuel_mid_grade", "fuel_premium", "fuel_diesel"].forEach((name) => {
                    const el = root?.querySelector(`[name="${name}"]`);
                    if (el) el.value = "";
                });
                if (state.day.fuelSale) {
                    state.day.fuelSale.regular = 0;
                    state.day.fuelSale.midGrade = 0;
                    state.day.fuelSale.premium = 0;
                    state.day.fuelSale.diesel = 0;
                }
            }
            syncFromForm();
            state.dirty = true;
            if (e.target.closest("[data-reg-recon], [data-reg-recon-input]")) {
                updateInlineRegisterReconDisplays($("data-input-root"));
            }
            if (state.tab === "cash-recon" && e.target.name === "cr_day_deposit") {
                render();
            }
        });

        panel.addEventListener(
            "blur",
            (e) => {
                const name = e.target?.name || "";
                const inForm = e.target.closest(".data-input-form, [data-pay-section]");
                if (!inForm) return;

                if (e.target.classList.contains("books-input-amount")) {
                    normalizeAmountField(e.target);
                }

                if (e.target.closest(".data-input-form")) {
                    syncFromForm();
                    state.dirty = true;
                    if (state.tab === "cash-recon" && name.startsWith("cr_")) {
                        render();
                    }
                }
            },
            true
        );
    }

    function bindShell() {
        bindPanelShell($("panel-data-input"));
        bindPanelShell($("panel-monthly-books"));
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
                payableId: null,
            });
        } else if (list === "otherExpenses") {
            state.day.otherExpenses.push({ id: lineId(), description: "", amount: 0 });
        } else if (list === "pulltabs") {
            state.day.pulltabs.push({
                id: lineId(),
                ticketNumber: "",
                cash: 0,
                winner: 0,
                overShort: 0,
            });
        } else if (list === "windStations") {
            if ((state.day.windStations || []).length >= 3) {
                window.alert("You can add up to 3 wind stations per day.");
                return;
            }
            const next = (state.day.windStations || []).length + 1;
            state.day.windStations.push({
                id: lineId(),
                station: String(next),
                cash: 0,
            });
        } else if (list === "kenoStations") {
            if ((state.day.kenoStations || []).length >= 3) {
                window.alert("You can add up to 3 keno stations per day.");
                return;
            }
            const next = (state.day.kenoStations || []).length + 1;
            state.day.kenoStations.push({
                id: lineId(),
                station: String(next),
                cash: 0,
            });
        } else if (list === "receivables") {
            state.month.receivables.push({ id: lineId(), description: "", amount: 0 });
        } else if (list === "monthAdjustments") {
            if (!state.month.monthAdjustments) state.month.monthAdjustments = [];
            state.month.monthAdjustments.push({
                id: lineId(),
                description: "",
                amount: 0,
                kind: "expense",
            });
        }
    }

    function removeLine(list, id) {
        if (list === "receivables") {
            state.month.receivables = state.month.receivables.filter((r) => r.id !== id);
        } else if (list === "monthAdjustments") {
            state.month.monthAdjustments = (state.month.monthAdjustments || []).filter((r) => r.id !== id);
        } else {
            state.day[list] = (state.day[list] || []).filter((r) => r.id !== id);
        }
    }

    function reconEntryFromPrefix(prefix) {
        if (!state.day.cashReconciliation) {
            state.day.cashReconciliation = M().defaultCashReconciliation();
        }
        const cr = state.day.cashReconciliation;
        const regMatch = prefix.match(/^cr_(register[12])_(shift[12])$/);
        if (regMatch) return cr[regMatch[1]][regMatch[2]];
        const lotMatch = prefix.match(/^cr_lottery_(shift[12])$/);
        if (lotMatch) {
            if (!cr.lottery) cr.lottery = M().defaultCashReconciliation().lottery;
            return cr.lottery[lotMatch[1]];
        }
        if (prefix.startsWith("cr_pt_")) {
            const id = prefix.slice("cr_pt_".length);
            if (!cr.pulltabs) cr.pulltabs = {};
            if (!cr.pulltabs[id]) cr.pulltabs[id] = M().emptyCashReconShift();
            return cr.pulltabs[id];
        }
        if (prefix.startsWith("cr_ws_")) {
            const id = prefix.slice("cr_ws_".length);
            if (!cr.windStations) cr.windStations = {};
            if (!cr.windStations[id]) cr.windStations[id] = M().emptyCashReconShift();
            return cr.windStations[id];
        }
        if (prefix.startsWith("cr_ks_")) {
            const id = prefix.slice("cr_ks_".length);
            if (!cr.kenoStations) cr.kenoStations = {};
            if (!cr.kenoStations[id]) cr.kenoStations[id] = M().emptyCashReconShift();
            return cr.kenoStations[id];
        }
        return null;
    }

    function syncPayOutsForPrefix(prefix, entry) {
        const root = $("data-input-root");
        const container = root?.querySelector(`[data-cr-payouts="${prefix}"]`);
        if (!container || !entry) return;
        const updated = [];
        container.querySelectorAll("[data-payout-id]").forEach((row) => {
            const id = row.dataset.payoutId;
            if (!id) return;
            const desc = row.querySelector(`[name="${prefix}_payOut_desc_${id}"]`);
            const amt = row.querySelector(`[name="${prefix}_payOut_amt_${id}"]`);
            updated.push({
                id,
                description: desc ? desc.value : "",
                amount: amt ? M().num(amt.value) : 0,
            });
        });
        entry.payOuts = updated;
    }

    function pruneAllReconPayOuts() {
        const cr = state.day?.cashReconciliation;
        if (!cr) return;
        const prune = (entry) => {
            if (entry?.payOuts) entry.payOuts = M().pruneEmptyPayOuts(entry.payOuts);
        };
        ["register1", "register2"].forEach((regKey) => {
            ["shift1", "shift2"].forEach((sh) => prune(cr[regKey]?.[sh]));
        });
        ["shift1", "shift2"].forEach((sh) => prune(cr.lottery?.[sh]));
        Object.values(cr.pulltabs || {}).forEach(prune);
        Object.values(cr.windStations || {}).forEach(prune);
        Object.values(cr.kenoStations || {}).forEach(prune);
    }

    function syncReconShiftFromDom(prefix, entry) {
        const root = $("data-input-root");
        if (!root || !entry) return;
        const counted = root.querySelector(`[name="${prefix}_counted"]`);
        const verified = root.querySelector(`[name="${prefix}_verified"]`);
        const note = root.querySelector(`[name="${prefix}_note"]`);
        if (counted) entry.countedCash = M().num(counted.value);
        syncPayOutsForPrefix(prefix, entry);
        if (verified) entry.verified = verified.checked;
        if (note) entry.note = note.value;
    }

    function syncFuelGradesToGallons(root) {
        if (!root || !state.day.fuelSale) return false;
        const fuelRegular = root.querySelector('[name="fuel_regular"]');
        const fuelMidGrade = root.querySelector('[name="fuel_mid_grade"]');
        const fuelPremium = root.querySelector('[name="fuel_premium"]');
        const fuelDiesel = root.querySelector('[name="fuel_diesel"]');
        const fuelG = root.querySelector('[name="fuel_gallons"]');
        let regular = 0;
        let midGrade = 0;
        let premium = 0;
        let diesel = 0;
        if (fuelRegular) regular = M().num(fuelRegular.value);
        if (fuelMidGrade) midGrade = M().num(fuelMidGrade.value);
        if (fuelPremium) premium = M().num(fuelPremium.value);
        if (fuelDiesel) diesel = M().num(fuelDiesel.value);
        const gradeSum = regular + midGrade + premium + diesel;
        const gradesActive = gradeSum > 0;

        state.day.fuelSale.regular = regular;
        state.day.fuelSale.midGrade = midGrade;
        state.day.fuelSale.premium = premium;
        state.day.fuelSale.diesel = diesel;

        if (gradesActive) {
            state.day.fuelSale.gallons = gradeSum;
            if (fuelG && document.activeElement !== fuelG) {
                fuelG.value = M().formatAmountForInput(gradeSum);
            }
        } else if (fuelG) {
            fuelG.readOnly = false;
            fuelG.removeAttribute("readonly");
            fuelG.removeAttribute("aria-readonly");
        }
        return gradesActive;
    }

    function syncFromForm() {
        const roots = [$("data-input-root"), $("monthly-books-root")].filter(Boolean);
        roots.forEach((root) => syncFromFormRoot(root));
    }

    function syncFromFormRoot(root) {
        if (!root) return;

        mergedUtilityKeys().forEach((u) => {
            const el = root.querySelector(`[name="util_${u.key}"]`);
            if (el) state.month.utilities[u.key] = M().num(el.value);
        });

        ["week1", "week2", "week3", "week4"].forEach((w) => {
            const el = root.querySelector(`[name="payroll_${w}"]`);
            if (el && !(state.month.payrollLines || []).length) {
                state.month.payroll[w] = M().num(el.value);
            }
        });

        const tax = root.querySelector('[name="salesTax"]');
        const acct = root.querySelector('[name="accountant"]');
        if (tax) state.month.salesTax = M().num(tax.value);
        if (acct) state.month.accountant = M().num(acct.value);

        const registerFields = ["cardSale", "cashSale", "cashPayOut"];
        ["register1", "register2"].forEach((regKey) => {
            if (!state.day[regKey]) state.day[regKey] = M().defaultRegisterUnit();
            ["shift1", "shift2"].forEach((sh) => {
                registerFields.forEach((f) => {
                    const el = root.querySelector(`[name="reg_${regKey}_${sh}_${f}"]`);
                    if (el) state.day[regKey][sh][f] = M().num(el.value);
                });
                const expenseEl = root.querySelector(`[name="reg_${regKey}_${sh}_cashPayOutExpense"]`);
                if (expenseEl) {
                    state.day[regKey][sh].cashPayOutExpense = expenseEl.value === "expense";
                }
            });
        });

        syncLinesFromDom("pulltabs", ["ticketNumber", "cash", "winner", "overShort"]);
        syncLinesFromDom("windStations", ["station", "cash"]);
        syncLinesFromDom("kenoStations", ["station", "cash"]);
        ["shift1", "shift2"].forEach((sh) => {
            const cash = root.querySelector(`[name="lot_shift${sh === "shift1" ? "1" : "2"}_cash"]`);
            const os = root.querySelector(`[name="lot_shift${sh === "shift1" ? "1" : "2"}_overShort"]`);
            if (!state.day.lottery) state.day.lottery = { shift1: M().emptyGamingShift(), shift2: M().emptyGamingShift() };
            if (cash) state.day.lottery[sh].cash = M().num(cash.value);
            if (os) state.day.lottery[sh].overShort = M().num(os.value);
        });
        if (hasGasStation()) {
            const merch = root.querySelector('[name="merch_sale"]');
            if (merch) state.day.merchSale = M().num(merch.value);
            const fuelG = root.querySelector('[name="fuel_gallons"]');
            const fuelD = root.querySelector('[name="fuel_dollars"]');
            const fuelRegular = root.querySelector('[name="fuel_regular"]');
            const fuelMidGrade = root.querySelector('[name="fuel_mid_grade"]');
            const fuelPremium = root.querySelector('[name="fuel_premium"]');
            const fuelDiesel = root.querySelector('[name="fuel_diesel"]');
            const credit = root.querySelector('[name="credit_card"]');
            const inHouse = root.querySelector('[name="in_house_account"]');
            const waynePass = root.querySelector('[name="wayne_pass"]');
            const lotteryPayOut = root.querySelector('[name="lottery_pay_out"]');
            const pullTabPay = root.querySelector('[name="pull_tab_payout"]');
            const otherCashPayOut = root.querySelector('[name="other_cash_pay_out"]');
            if (!state.day.fuelSale) state.day.fuelSale = M().defaultFuelSale();
            const gradesActive = syncFuelGradesToGallons(root);
            if (!gradesActive && fuelG) {
                state.day.fuelSale.gallons = M().num(fuelG.value);
            }
            if (fuelD) state.day.fuelSale.dollars = M().num(fuelD.value);
            if (credit) state.day.creditCard = M().num(credit.value);
            if (inHouse) state.day.inHouseAccount = M().num(inHouse.value);
            if (waynePass) state.day.waynePass = M().num(waynePass.value);
            if (lotteryPayOut) state.day.lotteryPayOut = M().num(lotteryPayOut.value);
            if (pullTabPay) state.day.pullTabPayout = M().num(pullTabPay.value);
            if (otherCashPayOut) state.day.otherCashPayOut = M().num(otherCashPayOut.value);
        } else {
            state.day.merchSale = 0;
            state.day.fuelSale = M().defaultFuelSale();
            state.day.creditCard = 0;
            state.day.inHouseAccount = 0;
            state.day.waynePass = 0;
            state.day.lotteryPayOut = 0;
            state.day.pullTabPayout = 0;
            state.day.otherCashPayOut = 0;
        }

        syncLinesFromDom("cashExpenses", ["description", "amount", "overShort"]);
        syncChecksAchFromDom();
        syncLinesFromDom("otherExpenses", ["description", "amount"]);
        syncLinesFromDom("receivables", ["description", "amount"], true);
        syncCustomAmountsFromDom(root, state.day, "daily");
        syncCustomAmountsFromDom(root, state.month, "month");

        if (!state.day.cashReconciliation) {
            state.day.cashReconciliation = M().defaultCashReconciliation();
        }
        ["register1", "register2"].forEach((regKey) => {
            ["shift1", "shift2"].forEach((sh) => {
                syncReconShiftFromDom(`cr_${regKey}_${sh}`, state.day.cashReconciliation[regKey][sh]);
            });
        });
        const deposit = root.querySelector('[name="cr_day_deposit"]');
        const dayNote = root.querySelector('[name="cr_day_note"]');
        if (deposit) {
            const v = String(deposit.value ?? "").trim();
            state.day.cashReconciliation.dayDeposit = v === "" ? null : M().num(v);
        }
        if (dayNote) state.day.cashReconciliation.note = dayNote.value;

        ["shift1", "shift2"].forEach((sh) => {
            if (!state.day.cashReconciliation.lottery) {
                state.day.cashReconciliation.lottery = M().defaultCashReconciliation().lottery;
            }
            syncReconShiftFromDom(`cr_lottery_${sh}`, state.day.cashReconciliation.lottery[sh]);
        });

        (state.day.pulltabs || []).forEach((pt) => {
            if (!state.day.cashReconciliation.pulltabs) state.day.cashReconciliation.pulltabs = {};
            syncReconShiftFromDom(`cr_pt_${pt.id}`, reconEntryFromPrefix(`cr_pt_${pt.id}`));
        });

        (state.day.windStations || []).forEach((ws) => {
            if (!state.day.cashReconciliation.windStations) state.day.cashReconciliation.windStations = {};
            syncReconShiftFromDom(`cr_ws_${ws.id}`, reconEntryFromPrefix(`cr_ws_${ws.id}`));
        });

        (state.day.kenoStations || []).forEach((ks) => {
            if (!state.day.cashReconciliation.kenoStations) state.day.cashReconciliation.kenoStations = {};
            syncReconShiftFromDom(`cr_ks_${ks.id}`, reconEntryFromPrefix(`cr_ks_${ks.id}`));
        });

        const lotteryDeposit = root.querySelector('[name="cr_lottery_deposit"]');
        const pulltabDeposit = root.querySelector('[name="cr_pulltab_deposit"]');
        const windDeposit = root.querySelector('[name="cr_wind_deposit"]');
        const kenoDeposit = root.querySelector('[name="cr_keno_deposit"]');
        if (lotteryDeposit) {
            const v = String(lotteryDeposit.value ?? "").trim();
            state.day.cashReconciliation.lotteryDeposit = v === "" ? null : M().num(v);
        }
        if (pulltabDeposit) {
            const v = String(pulltabDeposit.value ?? "").trim();
            state.day.cashReconciliation.pulltabDeposit = v === "" ? null : M().num(v);
        }
        if (windDeposit) {
            const v = String(windDeposit.value ?? "").trim();
            state.day.cashReconciliation.windDeposit = v === "" ? null : M().num(v);
        }
        if (kenoDeposit) {
            const v = String(kenoDeposit.value ?? "").trim();
            state.day.cashReconciliation.kenoDeposit = v === "" ? null : M().num(v);
        }

        syncMonthAdjustmentsFromDom(root);
        const closeNotes = root.querySelector("#di-close-notes");
        if (closeNotes) state.month.closeNotes = closeNotes.value;
    }

    function syncMonthAdjustmentsFromDom(root) {
        root = root || $("monthly-books-root") || $("data-input-root");
        if (!root?.querySelector('[data-di-list="monthAdjustments"]')) return;
        const rows = root.querySelectorAll('[data-di-list="monthAdjustments"] [data-di-row]');
        const updated = [];
        rows.forEach((row) => {
            const id = row.dataset.diRow;
            const existing =
                (state.month.monthAdjustments || []).find((r) => r.id === id) || { id };
            const desc = row.querySelector('[name="description"]');
            const kind = row.querySelector('[name="kind"]');
            const amount = row.querySelector('[name="amount"]');
            updated.push({
                ...existing,
                id,
                description: desc?.value || "",
                kind: kind?.value === "credit" ? "credit" : "expense",
                amount: M().num(amount?.value),
            });
        });
        state.month.monthAdjustments = updated;
    }

    function syncLinesFromDom(listKey, fields, isMonth) {
        const root = $("data-input-root");
        if (!root?.querySelector(`[data-di-list="${listKey}"]`)) return;
        const target = isMonth ? state.month[listKey] : state.day[listKey];
        const rows = root.querySelectorAll(`[data-di-list="${listKey}"] [data-di-row]`);
        const updated = [];
        rows.forEach((row) => {
            const id = row.dataset.diRow;
            const existing = target.find((r) => r.id === id) || { id };
            const obj = { ...existing, id };
            fields.forEach((f) => {
                const inp = row.querySelector(`[name="${f}"]`);
                if (inp) {
                    const isNum =
                        f === "amount" ||
                        f === "overShort" ||
                        f === "cash" ||
                        f === "winner";
                    obj[f] = isNum ? M().num(inp.value) : inp.value;
                }
            });
            updated.push(obj);
        });
        if (isMonth) state.month[listKey] = updated;
        else state.day[listKey] = updated;
    }

    function syncChecksAchFromDom() {
        const root = $("data-input-root");
        if (!root?.querySelector('[data-di-list="checksAch"]')) return;
        const rows = root.querySelectorAll('[data-di-list="checksAch"] [data-di-row]');
        const updated = [];
        rows.forEach((row) => {
            const id = row.dataset.diRow;
            const existing = (state.day.checksAch || []).find((r) => r.id === id) || { id };
            const payableEl = row.querySelector('[name="payableId"]');
            const desc = row.querySelector('[name="description"]');
            const checkNo = row.querySelector('[name="checkNo"]');
            const amt = row.querySelector('[name="amount"]');
            updated.push({
                ...existing,
                id,
                date: state.dayId,
                payableId: payableEl?.value || null,
                description: desc ? desc.value : "",
                checkNo: checkNo ? checkNo.value : "",
                amount: amt ? M().num(amt.value) : 0,
            });
        });
        state.day.checksAch = updated;
    }

    function applyPayablePick(rowId, payableId) {
        if (!payableId) return;
        const p = (state.payables || []).find((x) => x.id === payableId);
        if (!p) return;
        const row = state.day.checksAch?.find((r) => r.id === rowId);
        if (row) {
            row.payableId = payableId;
            row.description = p.payTo || row.description;
            row.amount = M().num(p.amount) || row.amount;
        }
        state.dirty = true;
        render();
    }

    async function loadCurrent() {
        if (!state.locationId) return;
        setBooksStatus("Loading…");
        try {
            const { month, daysById } = await Store().loadMonth(
                userId,
                state.locationId,
                state.monthId
            );
            await Promise.all([loadUtilityProviders(), loadPayables(), loadReceivables()]);
            state.month = M().normalizeMonthDoc(month);
            state.month.utilities = M().normalizeMonthUtilities(
                state.month.utilities,
                M().mergeUtilityKeys(state.utilityProviders, state.month.utilities)
            );
            state.daysById = daysById;
            refreshEntryDayId();
            if (!String(state.dayId).startsWith(`${state.monthId}-`)) {
                state.dayId = state.entryDayId;
            }
            state.day = M().normalizeDayDoc(daysById[state.dayId]);
            refreshExpenseDescriptions();
            state.dirty = false;
            setBooksStatus("");
            render();
        } catch (err) {
            console.error("[Oplix] Daily books load failed:", err);
            setBooksStatus("");
            const root = booksRoot();
            if (root) {
                root.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Failed to load Daily books.")}</p>`;
            }
        }
    }

    async function saveMonth(options = {}) {
        if (isViewingClosedMonth()) {
            setBooksStatus("Month is closed — reopen to save.");
            return;
        }
        normalizeAllAmountFields();
        syncFromForm();
        if (!options.silent) setBooksStatus("Saving…");
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        window.OplixAnalytics?.invalidateCache?.();
        state.dirty = false;
        if (!options.silent) {
            setBooksStatus("Month saved.");
            setTimeout(() => {
                if (getBooksStatus() === "Month saved.") setBooksStatus("");
            }, 2000);
        }
    }

    async function saveDay(options = {}) {
        if (isViewingClosedMonth()) {
            setBooksStatus("Month is closed — reopen to save.");
            return;
        }
        if (isViewingClosedDay()) {
            setBooksStatus("Day is closed — reopen to save.");
            return;
        }
        normalizeAllAmountFields();
        syncFromForm();
        pruneAllReconPayOuts();
        await syncPayablesFromChecks();
        if (!options.silent) setBooksStatus("Saving…");
        await Promise.all([
            Store().saveDay(userId, state.locationId, state.monthId, state.dayId, state.day),
            Store().saveMonth(userId, state.locationId, state.monthId, state.month),
        ]);
        window.OplixAnalytics?.invalidateCache?.();
        state.daysById[state.dayId] = { ...state.day, _dayId: state.dayId };
        rememberExpenseDescriptionsFromDay(state.day);
        state.dirty = false;
        if (!options.silent) {
            setBooksStatus("Day saved.");
            if (state.tab === "cash-recon") render();
            setTimeout(() => {
                if (getBooksStatus() === "Day saved.") setBooksStatus("");
            }, 2000);
        }
        if (
            !options.silent &&
            !options.skipClosePrompt &&
            !M().isDayClosed(state.day) &&
            M().dayHasEntryData({ ...state.day, _dayId: state.dayId }, { hasGasStation: hasGasStation() })
        ) {
            setTimeout(() => {
                if (
                    window.confirm(
                        "Entry saved. Close this day now to lock it from accidental changes?"
                    )
                ) {
                    closeCurrentDay({ skipConfirm: true });
                }
            }, 50);
        }
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
            const raw = state.daysById[id];
            const has = !!raw;
            const closed = M().isDayClosed(raw);
            const label = date.toLocaleDateString("en-US", {
                weekday: "short",
                month: "short",
                day: "numeric",
            });
            const prefix = closed ? "🔒 " : has ? "● " : "";
            opts.push(
                `<option value="${id}"${id === state.dayId ? " selected" : ""}>${prefix}${label}</option>`
            );
        }
        return opts.join("");
    }

    const REGISTER_SHIFT_FIELDS = [
        { name: "cardSale", label: "Card sale" },
        { name: "cashSale", label: "Cash sale" },
    ];

    function renderRegisterUnit(title, regKey, unit) {
        const total = M().registerBlockTotal(unit);
        return `
            <section class="books-register-unit">
                <div class="books-register-unit-head">
                    <h3 class="books-subtitle books-register-unit-title">${escapeHtml(title)}</h3>
                    <p class="books-total-line books-register-unit-total">${escapeHtml(title)} total: ${money(total.card + total.cash)} card+cash</p>
                </div>
                <div class="books-register-shifts">
                    ${renderRegisterShiftBlock("Shift 1", `reg_${regKey}_shift1`, unit.shift1, regKey, "shift1")}
                    ${renderRegisterShiftBlock("Shift 2", `reg_${regKey}_shift2`, unit.shift2, regKey, "shift2")}
                </div>
            </section>`;
    }

    /** All register shifts in one parallel row: R1 S1 | R1 S2 | R2 S1 | R2 S2 */
    function renderAllRegisters() {
        const r1 = state.day.register1 || M().defaultRegisterUnit();
        const r2 = state.day.register2 || M().defaultRegisterUnit();
        const t1 = M().registerBlockTotal(r1);
        const t2 = M().registerBlockTotal(r2);
        const all = M().registerDayTotal(state.day);
        return `
            <section class="books-register-unit books-register-unit--all">
                <div class="books-register-unit-head">
                    <h3 class="books-subtitle books-register-unit-title">Registers</h3>
                    <p class="books-total-line books-register-unit-total">
                        R1 ${money(t1.card + t1.cash)} · R2 ${money(t2.card + t2.cash)} · All ${money(all.card + all.cash)} card+cash
                    </p>
                </div>
                <div class="books-register-shifts books-register-shifts--all">
                    ${renderRegisterShiftBlock("Register 1 · Shift 1", "reg_register1_shift1", r1.shift1, "register1", "shift1")}
                    ${renderRegisterShiftBlock("Register 1 · Shift 2", "reg_register1_shift2", r1.shift2, "register1", "shift2")}
                    ${renderRegisterShiftBlock("Register 2 · Shift 1", "reg_register2_shift1", r2.shift1, "register2", "shift1")}
                    ${renderRegisterShiftBlock("Register 2 · Shift 2", "reg_register2_shift2", r2.shift2, "register2", "shift2")}
                </div>
            </section>`;
    }

    function registerShiftReconEntry(regKey, shiftKey) {
        if (!state.day.cashReconciliation) {
            state.day.cashReconciliation = M().defaultCashReconciliation();
        }
        if (!state.day.cashReconciliation[regKey]) {
            state.day.cashReconciliation[regKey] = {
                shift1: M().emptyCashReconShift(),
                shift2: M().emptyCashReconShift(),
            };
        }
        if (!state.day.cashReconciliation[regKey][shiftKey]) {
            state.day.cashReconciliation[regKey][shiftKey] = M().emptyCashReconShift();
        }
        return state.day.cashReconciliation[regKey][shiftKey];
    }

    function renderRegisterShiftBlock(title, prefix, data, regKey, shiftKey) {
        const shift = data || M().emptyShiftRegister();
        const countAsExpense = !!shift.cashPayOutExpense;
        const cashSale = M().num(shift.cashSale);
        const payOut = M().num(shift.cashPayOut);
        const expected = Math.max(0, cashSale - payOut);
        const showRecon = showField("cashReconciliation") && showField("registers");
        const recon = showRecon ? registerShiftReconEntry(regKey, shiftKey) : null;
        const counted = recon ? M().num(recon.countedCash) : 0;
        const variance = counted - expected;
        const varCls = varianceColorClass(variance);
        const crPrefix = `cr_${regKey}_${shiftKey}`;

        return `
            <fieldset class="books-fieldset books-register-shift">
                <legend>${escapeHtml(title)}</legend>
                <div class="books-register-shift-sales">
                    ${REGISTER_SHIFT_FIELDS.map(
                        (f) => `
                    <label class="books-label">${escapeHtml(f.label)}
                        <input ${amountInputAttrs(`${prefix}_${f.name}`, shift[f.name])} data-reg-recon-input="${escapeHtml(regKey)}:${escapeHtml(shiftKey)}">
                    </label>`
                    ).join("")}
                </div>
                <div class="books-register-payout-row">
                    <label class="books-label">Cash pay out ($)
                        <input ${amountInputAttrs(`${prefix}_cashPayOut`, shift.cashPayOut)} data-reg-recon-input="${escapeHtml(regKey)}:${escapeHtml(shiftKey)}">
                    </label>
                    <label class="books-label">Count in store expense?
                        <select class="books-select" name="${prefix}_cashPayOutExpense">
                            <option value="expense"${countAsExpense ? " selected" : ""}>Yes — expense</option>
                            <option value="track_only"${!countAsExpense ? " selected" : ""}>No — track only</option>
                        </select>
                    </label>
                </div>
                <p class="books-hint books-register-payout-hint">Pay out lowers expected cash. <strong>Yes</strong> also counts as store expense.</p>
                ${
                    showRecon
                        ? `<div class="books-register-recon" data-reg-recon="${escapeHtml(regKey)}:${escapeHtml(shiftKey)}">
                    <div class="books-register-recon-head">
                        <span class="books-register-recon-title">Cash reconciliation</span>
                        <span class="books-register-recon-status${Math.abs(variance) < 0.005 && counted !== 0 ? " books-register-recon-status--ok" : ""}" data-reg-recon-status>
                            ${Math.abs(variance) < 0.005 && (counted !== 0 || expected === 0) ? "Balanced" : "Count cash in drawer"}
                        </span>
                    </div>
                    <div class="books-register-recon-grid">
                        <div class="books-register-recon-stat">
                            <span>Expected</span>
                            <strong data-reg-recon-expected>${money(expected)}</strong>
                        </div>
                        <div class="books-register-recon-stat">
                            <span>Variance</span>
                            <strong class="${varCls}" data-reg-recon-variance>${money(variance)}</strong>
                        </div>
                        <label class="books-label books-register-recon-received">Received
                            <input ${amountInputAttrs(`${crPrefix}_counted`, recon.countedCash)} data-reg-recon-input="${escapeHtml(regKey)}:${escapeHtml(shiftKey)}" aria-label="Received cash">
                        </label>
                        <label class="books-check-label books-register-recon-verified">
                            <input type="checkbox" name="${crPrefix}_verified"${recon.verified ? " checked" : ""}>
                            Verified
                        </label>
                    </div>
                    <label class="books-label books-register-recon-note">Note
                        <input type="text" class="books-input" name="${crPrefix}_note" value="${escapeHtml(recon.note || "")}" placeholder="Optional">
                    </label>
                </div>`
                        : ""
                }
            </fieldset>`;
    }

    function updateInlineRegisterReconDisplays(root) {
        if (!root) return;
        root.querySelectorAll("[data-reg-recon]").forEach((block) => {
            const key = block.dataset.regRecon || "";
            const [regKey, shiftKey] = key.split(":");
            if (!regKey || !shiftKey) return;
            const prefix = `reg_${regKey}_${shiftKey}`;
            const cashSaleEl = root.querySelector(`[name="${prefix}_cashSale"]`);
            const payOutEl = root.querySelector(`[name="${prefix}_cashPayOut"]`);
            const countedEl = root.querySelector(`[name="cr_${regKey}_${shiftKey}_counted"]`);
            const cashSale = M().num(cashSaleEl?.value);
            const payOut = M().num(payOutEl?.value);
            const expected = Math.max(0, cashSale - payOut);
            const counted = M().num(countedEl?.value);
            const variance = counted - expected;
            const expectedEl = block.querySelector("[data-reg-recon-expected]");
            const varianceEl = block.querySelector("[data-reg-recon-variance]");
            const statusEl = block.querySelector("[data-reg-recon-status]");
            if (expectedEl) expectedEl.textContent = money(expected);
            if (varianceEl) {
                varianceEl.textContent = money(variance);
                varianceEl.classList.remove("books-cash-recon-var--ok", "books-cash-recon-var--bad");
                const cls = varianceColorClass(variance);
                if (cls) varianceEl.classList.add(cls);
            }
            if (statusEl) {
                const balanced = Math.abs(variance) < 0.005 && (counted !== 0 || expected === 0);
                statusEl.textContent = balanced ? "Balanced" : "Count cash in drawer";
                statusEl.classList.toggle("books-register-recon-status--ok", balanced);
            }
        });
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
                        <input ${amountInputAttrs(`${prefix}_${f.name}`, data[f.name])}>
                    </label>`
                        )
                        .join("")}
                </div>
            </fieldset>`;
    }

    function renderLineList(listKey, columns, rows, isMonth, addLabel) {
        const list = isMonth ? state.month[listKey] : state.day[listKey];
        const suggestDescriptions = EXPENSE_DESC_LISTS.has(listKey);
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
                                if (type === "number") {
                                    return `<input ${amountInputAttrs(c.name, val)}>`;
                                }
                                if (c.name === "description" && suggestDescriptions) {
                                    return `<input type="text" class="books-input" name="${c.name}" list="${EXPENSE_DESC_DATALIST_ID}" autocomplete="off" value="${escapeHtml(val)}" placeholder="Start typing…">`;
                                }
                                return `<input type="${type}" class="books-input" name="${c.name}" value="${escapeHtml(val)}">`;
                            })
                            .join("");
                        return `
                    <div class="books-lines-row" data-di-row="${escapeHtml(row.id)}">
                        ${cells}
                        <button type="button" class="books-rm" data-di-rm="${escapeHtml(row.id)}" data-di-list="${listKey}">×</button>
                    </div>`;
                    })
                    .join("")}
                ${
                    addLabel !== false
                        ? `<button type="button" class="books-add-line" data-di-add="${listKey}">${escapeHtml(addLabel || "+ Add line")}</button>`
                        : ""
                }
            </div>`;
    }

    function renderStationCards(listKey, columns, addLabel, itemLabel) {
        const list = state.day[listKey] || [];
        const cards = list
            .map((row, index) => {
                const fields = columns
                    .map((c) => {
                        const type = c.type || "text";
                        const val = row[c.name] ?? "";
                        if (type === "number") {
                            return `<label class="books-label">${escapeHtml(c.label)}
                                <input ${amountInputAttrs(c.name, val)}>
                            </label>`;
                        }
                        return `<label class="books-label">${escapeHtml(c.label)}
                            <input type="${type}" class="books-input" name="${c.name}" value="${escapeHtml(val)}">
                        </label>`;
                    })
                    .join("");
                return `
                <div class="books-station-card" data-di-row="${escapeHtml(row.id)}">
                    <div class="books-station-card-head">
                        <strong>${escapeHtml(itemLabel || "Item")} ${index + 1}</strong>
                        <button type="button" class="books-rm" data-di-rm="${escapeHtml(row.id)}" data-di-list="${listKey}" title="Remove">×</button>
                    </div>
                    <div class="books-station-card-fields">${fields}</div>
                </div>`;
            })
            .join("");
        return `
            <div class="books-station-cards" data-di-list="${listKey}">
                ${cards}
                ${
                    addLabel !== false
                        ? `<button type="button" class="books-add-line" data-di-add="${listKey}">${escapeHtml(addLabel || "+ Add")}</button>`
                        : ""
                }
            </div>`;
    }

    function renderLotteryDaily() {
        const lot = state.day.lottery || { shift1: M().emptyGamingShift(), shift2: M().emptyGamingShift() };
        const total = M().lotteryDayTotal(state.day);
        const shiftCard = (label, prefix, data) => `
            <div class="books-station-card books-station-card--shift">
                <div class="books-station-card-head"><strong>${escapeHtml(label)}</strong></div>
                <div class="books-station-card-fields books-station-card-fields--2">
                    <label class="books-label">Cash
                        <input ${amountInputAttrs(`${prefix}_cash`, data.cash)}>
                    </label>
                    <label class="books-label">O/S
                        <input ${amountInputAttrs(`${prefix}_overShort`, data.overShort)}>
                    </label>
                </div>
            </div>`;
        return `
            <section class="books-gaming-panel">
                <div class="books-gaming-panel-head">
                    <h3 class="books-subtitle">Lottery</h3>
                    <p class="books-total-line">Total: <strong>${money(total.cash)}</strong></p>
                </div>
                <p class="books-hint">Cash per shift. Count received on Cash reconciliation.</p>
                <div class="books-station-cards books-station-cards--shifts">
                    ${shiftCard("Shift 1", "lot_shift1", lot.shift1 || M().emptyGamingShift())}
                    ${shiftCard("Shift 2", "lot_shift2", lot.shift2 || M().emptyGamingShift())}
                </div>
            </section>`;
    }

    function renderPulltabs() {
        const total = M().pulltabDayTotal(state.day);
        return `
            <section class="books-gaming-panel">
                <div class="books-gaming-panel-head">
                    <h3 class="books-subtitle">Pulltab</h3>
                    <p class="books-total-line">Total: <strong>${money(total.cash)}</strong></p>
                </div>
                <p class="books-hint">One card per machine.</p>
                ${renderStationCards(
                    "pulltabs",
                    [
                        { name: "ticketNumber", label: "Ticket #" },
                        { name: "cash", label: "Cash", type: "number" },
                        { name: "winner", label: "Winners", type: "number" },
                        { name: "overShort", label: "O/S", type: "number" },
                    ],
                    "+ Add machine",
                    "Machine"
                )}
            </section>`;
    }

    function renderWindStations() {
        const total = M().windStationDayTotal(state.day);
        const count = (state.day.windStations || []).length;
        const canAdd = count < 3;
        return `
            <section class="books-gaming-panel">
                <div class="books-gaming-panel-head">
                    <h3 class="books-subtitle">Wind station</h3>
                    <p class="books-total-line">Total: <strong>${money(total)}</strong></p>
                </div>
                <p class="books-hint">Up to 3 stations.</p>
                ${renderStationCards(
                    "windStations",
                    [
                        { name: "station", label: "Station" },
                        { name: "cash", label: "Cash", type: "number" },
                    ],
                    canAdd ? "+ Add station" : false,
                    "Station"
                )}
            </section>`;
    }

    function renderKenoStations() {
        const total = M().kenoStationDayTotal(state.day);
        const count = (state.day.kenoStations || []).length;
        const canAdd = count < 3;
        return `
            <section class="books-gaming-panel">
                <div class="books-gaming-panel-head">
                    <h3 class="books-subtitle">Keno station</h3>
                    <p class="books-total-line">Total: <strong>${money(total)}</strong></p>
                </div>
                <p class="books-hint">Up to 3 stations.</p>
                ${renderStationCards(
                    "kenoStations",
                    [
                        { name: "station", label: "Station" },
                        { name: "cash", label: "Cash", type: "number" },
                    ],
                    canAdd ? "+ Add station" : false,
                    "Station"
                )}
            </section>`;
    }

    function renderGamingStationsGrid() {
        const panels = [];
        if (showField("pulltabs")) panels.push(renderPulltabs());
        if (showField("windStations")) panels.push(renderWindStations());
        if (showField("kenoStations")) panels.push(renderKenoStations());
        if (showField("lottery")) panels.push(renderLotteryDaily());
        if (!panels.length) return "";
        return `<div class="books-gaming-grid">${panels.join("\n")}</div>`;
    }

    function renderUtilitiesPayroll() {
        const utilityKeys = mergedUtilityKeys();
        const utilCards = utilityKeys
            .map((u) => {
                const deletable = canDeleteUtility(u.key);
                return `
            <div class="books-util-card" data-di-util-key="${escapeHtml(u.key)}">
                <div class="books-util-card-head">
                    <span class="books-util-label" title="${escapeHtml(u.label)}">${escapeHtml(u.label)}</span>
                    ${
                        deletable
                            ? `<button type="button" class="books-rm" data-di-util-rm="${escapeHtml(u.key)}" title="Remove utility">×</button>`
                            : ""
                    }
                </div>
                <label class="books-label">Amount
                    <input ${amountInputAttrs(`util_${u.key}`, state.month.utilities[u.key])}>
                </label>
            </div>`;
            })
            .join("");

        const payrollLines = (state.month.payrollLines || []).map((l) =>
            M().normalizePayrollLine(l)
        );
        const payrollSynced = payrollLines.length > 0;

        const payrollWeekCards = payrollSynced
            ? ""
            : ["week1", "week2", "week3", "week4"]
                  .map(
                      (w, i) => `
            <div class="books-payroll-card">
                <label class="books-label">Week ${i + 1}
                    <input ${amountInputAttrs(`payroll_${w}`, state.month.payroll[w])}>
                </label>
            </div>`
                  )
                  .join("");

        const utilTotal = utilityKeys.reduce(
            (s, u) => s + M().num(state.month.utilities[u.key]),
            0
        );
        const payTotal = payrollSynced
            ? payrollLines.reduce((s, l) => s + M().num(l.pay), 0)
            : M().num(state.month.payroll.week1) +
              M().num(state.month.payroll.week2) +
              M().num(state.month.payroll.week3) +
              M().num(state.month.payroll.week4);

        const payrollEmployeeCards = payrollSynced
            ? payrollLines
                  .map(
                      (l) => `
                <div class="books-payroll-card books-payroll-card--employee">
                    <strong class="books-payroll-card-name">${escapeHtml(l.employeeName || "Employee")}</strong>
                    <div class="books-payroll-card-stats">
                        <div><span>Hours</span><strong>${M().formatAmountForInput(l.hours)}</strong></div>
                        <div><span>Rate</span><strong>${money(l.hourlyRate)}</strong></div>
                        <div><span>Pay</span><strong>${money(l.pay)}</strong></div>
                    </div>
                </div>`
                  )
                  .join("")
            : "";

        const utilitiesPanel = showField("utilities")
            ? `<section class="books-util-payroll-panel">
                <div class="books-util-payroll-panel-head">
                    <h3 class="books-subtitle">Utilities</h3>
                    <p class="books-total-line">Total: <strong>${money(utilTotal)}</strong></p>
                </div>
                <p class="books-hint">Monthly amounts per utility. Add custom ones below.</p>
                <div class="books-util-cards" data-di-util-list>
                    ${utilCards}
                </div>
                <button type="button" class="books-add-line" data-di-util-add>+ Add utility</button>
            </section>`
            : "";

        const payrollPanel = showField("payroll")
            ? `<section class="books-util-payroll-panel">
                <div class="books-util-payroll-panel-head">
                    <h3 class="books-subtitle">Payroll</h3>
                    <p class="books-total-line">Total: <strong>${money(payTotal)}</strong></p>
                </div>
                ${
                    payrollSynced
                        ? `<p class="books-hint">Synced from the <strong>Payroll</strong> tab. Edit hours there to update Books.</p>
                    <div class="books-payroll-cards">${payrollEmployeeCards}</div>`
                        : `<p class="books-hint">Enter weekly totals, or use the <strong>Payroll</strong> tab for hours by employee.</p>
                    <div class="books-payroll-cards">${payrollWeekCards}</div>`
                }
            </section>`
            : "";

        const otherPanel =
            showField("salesTax") || showField("accountant")
                ? `<section class="books-util-payroll-panel books-util-payroll-panel--other">
                <h3 class="books-subtitle">Other monthly</h3>
                <div class="books-payroll-cards books-payroll-cards--other">
                    ${
                        showField("salesTax")
                            ? `<div class="books-payroll-card"><label class="books-label">Sales tax
                        <input ${amountInputAttrs("salesTax", state.month.salesTax)}>
                    </label></div>`
                            : ""
                    }
                    ${
                        showField("accountant")
                            ? `<div class="books-payroll-card"><label class="books-label">Accountant
                        <input ${amountInputAttrs("accountant", state.month.accountant)}>
                    </label></div>`
                            : ""
                    }
                </div>
            </section>`
                : "";

        const customMonth = renderCustomBooksFields("month", state.month.customAmounts);
        const parts = [
            '<div class="books-panel data-input-form">',
            `<div class="books-util-payroll-grid">${utilitiesPanel}${payrollPanel}</div>`,
            otherPanel,
        ];
        if (customMonth) parts.push(customMonth);
        parts.push(
            isViewingClosedMonth()
                ? ""
                : '<button type="button" class="btn books-save" id="di-save-month">Save month (utilities & payroll)</button>',
            "</div>"
        );
        const inner = parts.join("\n");
        if (isViewingClosedMonth()) {
            return `<fieldset class="books-fieldset" disabled>${inner}</fieldset>`;
        }
        return inner;
    }

    function renderDailyMerchEntry() {
        return `
            <label class="books-label">Merch sale ($)
                <input ${amountInputAttrs("merch_sale", state.day.merchSale)}>
                <span class="books-field-hint">In-store merch total for the day</span>
            </label>`;
    }

    function fuelGradesActive(fuel) {
        return M().sumFuelGradeGallons(fuel) > 0;
    }

    function renderDailyGasSales(fuelSale) {
        const fuel = fuelSale || M().defaultFuelSale();
        const gradesActive = fuelGradesActive(fuel);
        const showMerch = showField("merchSale");
        const showCredit = showField("creditCard");
        const showFuel = showField("fuel");
        if (!showMerch && !showCredit && !showFuel) return "";

        const parts = [
            `<h3 class="books-subtitle">Daily sales</h3>`,
            `<p class="books-hint">Merch, credit card, and fuel are separate — none are combined into each other.</p>`,
        ];
        if (showMerch) parts.push(renderDailyMerchEntry());
        if (showCredit) {
            parts.push(`<label class="books-label">Credit card ($)
                <input ${amountInputAttrs("credit_card", state.day.creditCard)}>
                <span class="books-field-hint">Credit card sales — separate from merch sale and fuel ($)</span>
            </label>`);
        }
        if (showFuel) {
            parts.push(`<div class="books-grid-2">
                <label class="books-label">Gallons sold
                    <input ${amountInputAttrs("fuel_gallons", fuel.gallons)}>
                    ${gradesActive ? '<span class="books-field-hint">Filled from grade breakdown below — clear all grades to enter a single total here</span>' : ""}
                </label>
                <label class="books-label">Fuel amount ($)
                    <input ${amountInputAttrs("fuel_dollars", fuel.dollars)}>
                    <span class="books-field-hint">Fuel revenue — separate from merch and credit card</span>
                </label>
            </div>
            <p class="books-hint books-fuel-grade-hint">Optional — gallons by grade (total updates Gallons sold automatically)</p>
            <div class="books-grid-4 books-fuel-grades">
                <label class="books-label">Regular (gal)
                    <input ${amountInputAttrs("fuel_regular", fuel.regular)}>
                </label>
                <label class="books-label">Mid grade (gal)
                    <input ${amountInputAttrs("fuel_mid_grade", fuel.midGrade)}>
                </label>
                <label class="books-label">Premium (gal)
                    <input ${amountInputAttrs("fuel_premium", fuel.premium)}>
                </label>
                <label class="books-label">Diesel (gal)
                    <input ${amountInputAttrs("fuel_diesel", fuel.diesel)}>
                </label>
            </div>`);
        }
        return parts.join("\n");
    }

    function renderRegisterWaynePass() {
        if (!showField("waynePass")) return "";
        return `
            <label class="books-label">Wayne Pass ($)
                <input ${amountInputAttrs("wayne_pass", state.day.waynePass)}>
                <span class="books-field-hint">Wayne Pass sales — recorded with register, not a payout</span>
            </label>`;
    }

    function renderRegisterPayoutFields() {
        if (!showField("registerPayouts")) return "";
        return `
            <h3 class="books-subtitle">Register payouts</h3>
            <p class="books-hint">Track payouts from the register. In house account, lottery pay out, and pull tab payout are <strong>track only</strong> — they do not change cash reconciliation. Other cash pay out lowers expected deposit.</p>
            <div class="books-grid-2">
                <label class="books-label">In house account ($)
                    <input ${amountInputAttrs("in_house_account", state.day.inHouseAccount)}>
                    <span class="books-field-hint">Track only — not subtracted on Cash reconciliation</span>
                </label>
                <label class="books-label">Lottery pay out ($)
                    <input ${amountInputAttrs("lottery_pay_out", state.day.lotteryPayOut)}>
                    <span class="books-field-hint">Track only — not subtracted on Cash reconciliation</span>
                </label>
                <label class="books-label">Pull tab payout ($)
                    <input ${amountInputAttrs("pull_tab_payout", state.day.pullTabPayout)}>
                    <span class="books-field-hint">Track only — not subtracted on Cash reconciliation</span>
                </label>
                <label class="books-label">Other cash pay out ($)
                    <input ${amountInputAttrs("other_cash_pay_out", state.day.otherCashPayOut)}>
                    <span class="books-field-hint">Reduces expected deposit on Cash reconciliation</span>
                </label>
            </div>`;
    }

    function renderDailyExpensesBlock() {
        const parts = [];
        if (showField("cashExpenses")) {
            parts.push(`<h3 class="books-subtitle">Cash expense (office)</h3>
                    <p class="books-hint">Paid from <strong>office cash</strong> (separate from the register drawer). Counts as store expense only — does <strong>not</strong> change register expected cash or day deposit. Paid from the drawer? Use <strong>Cash pay out</strong> on that shift instead.</p>
                    ${renderLineList("cashExpenses", [
                        { name: "description", label: "Description" },
                        { name: "amount", label: "Amount", type: "number" },
                        { name: "overShort", label: "O/S", type: "number" },
                    ])}`);
        }
        if (showField("checksAch")) {
            parts.push(renderChecksAchList());
        }
        if (showField("otherExpenses")) {
            parts.push(`<h3 class="books-subtitle">Other expense</h3>
                    ${renderLineList("otherExpenses", [
                        { name: "description", label: "Description" },
                        { name: "amount", label: "Amount", type: "number" },
                    ])}`);
        }
        return parts.join("\n");
    }

    function renderDailyDetailSheet(reg) {
        const bodyParts = [];
        if (showField("registers")) {
            bodyParts.push(
                renderAllRegisters(),
                `<p class="books-hint">Register card/cash on the detail sheet is for shift reconciliation only — not added to merch, credit card, or fuel.</p>`
            );
        }
        const wayne = renderRegisterWaynePass();
        if (wayne) bodyParts.push(wayne);
        const payouts = renderRegisterPayoutFields();
        if (payouts) bodyParts.push(payouts);
        const gaming = renderGamingStationsGrid();
        if (gaming) bodyParts.push(gaming);
        const expenses = renderDailyExpensesBlock();
        if (expenses) bodyParts.push(expenses);

        if (!bodyParts.length) return "";

        return `
            <details class="books-detail-sheet" open>
                <summary class="books-detail-summary">Detail sheet</summary>
                <div class="books-detail-body">
                    ${bodyParts.join("\n")}
                </div>
            </details>`;
    }

    function renderDailyCStore() {
        const reg = M().registerDayTotal(state.day);
        const parts = [];
        if (showField("registers")) {
            parts.push(
                `<p class="books-hint"><strong>Total sales</strong> in Books summary uses register card + cash (both registers, both shifts). Lottery and pulltab are tracked separately.</p>
            ${renderAllRegisters()}`
            );
        }
        const gaming = renderGamingStationsGrid();
        if (gaming) parts.push(gaming);
        const expenses = renderDailyExpensesBlock();
        if (expenses) parts.push(expenses);
        return parts.join("\n");
    }

    function renderDaily() {
        const reg = M().registerDayTotal(state.day);
        const gas = hasGasStation();
        const fuelSale = M().normalizeFuelSale(state.day.fuelSale);
        const closed = isBooksLocked();
        const fieldsetAttr = closed ? " disabled" : "";

        if (gas) {
            const gasSales = renderDailyGasSales(fuelSale);
            const detail = renderDailyDetailSheet(reg);
            return `
            <div class="books-panel data-input-form">
                ${renderDayStatusBanner()}
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>
                <fieldset class="books-day-fields"${fieldsetAttr}>
                    ${gasSales}
                    ${detail}
                    ${renderCustomBooksFields("daily", state.day.customAmounts)}
                </fieldset>
                ${closed ? "" : `<button type="button" class="btn books-save" id="di-save-day">Save this day</button>`}
            </div>`;
        }

        return `
            <div class="books-panel data-input-form">
                ${renderDayStatusBanner()}
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>
                <fieldset class="books-day-fields"${fieldsetAttr}>
                    ${renderDailyCStore()}
                    ${renderCustomBooksFields("daily", state.day.customAmounts)}
                </fieldset>
                ${closed ? "" : `<button type="button" class="btn books-save" id="di-save-day">Save this day</button>`}
            </div>`;
    }

    function renderPayOutsCell(prefix, payOuts) {
        const lines = Array.isArray(payOuts) ? payOuts : [];
        const rows = lines
            .map(
                (line) => `
            <div class="books-cash-recon-payout-row" data-payout-id="${escapeHtml(line.id)}">
                <input type="text" class="books-input books-cash-recon-payout-desc"
                    name="${prefix}_payOut_desc_${escapeHtml(line.id)}"
                    value="${escapeHtml(line.description)}"
                    placeholder="Description"
                    aria-label="Pay out description">
                <input ${amountInputAttrs(`${prefix}_payOut_amt_${line.id}`, line.amount)} aria-label="Pay out amount">
                <button type="button" class="books-rm" data-cr-payout-rm="${escapeHtml(prefix)}" data-payout-id="${escapeHtml(line.id)}" title="Remove payout">×</button>
            </div>`
            )
            .join("");
        const total = M().sumPayOuts(lines);
        return `
            <div class="books-cash-recon-payouts" data-cr-payouts="${escapeHtml(prefix)}">
                ${rows}
                <button type="button" class="books-add-line books-cash-recon-payout-add" data-cr-payout-add="${escapeHtml(prefix)}">+ Add payout</button>
                ${lines.length ? `<p class="books-cash-recon-payout-total">Total: ${money(total)}</p>` : ""}
            </div>`;
    }

    function renderReconTableRows(rows, col1, col2) {
        return rows
            .map((row) => {
                const prefix = row.namePrefix;
                const isRegister = row.kind === "register";
                const rowVariance = isRegister
                    ? num(row.counted) - num(row.expected)
                    : num(row.counted) + num(row.payOut) - num(row.expected);
                const varCls = varianceColorClass(rowVariance);
                const payOutCell = isRegister
                    ? `<span class="books-cash-recon-payout-readonly" title="${row.cashPayOutExpense ? "Counted as store expense" : "Track only"}">${money(row.payOut)}</span>`
                    : renderPayOutsCell(prefix, row.payOuts);
                return `
                    <tr>
                        <td>${escapeHtml(row[col1] || row.rowLabel)}</td>
                        <td>${escapeHtml(row[col2] || row.shiftLabel)}</td>
                        <td class="home-cc-num books-cash-recon-expected">${money(row.expected)}</td>
                        <td class="home-cc-num">
                            <input ${amountInputAttrs(`${prefix}_counted`, row.counted)} aria-label="Received">
                        </td>
                        <td class="books-cash-recon-payout-col">
                            ${payOutCell}
                        </td>
                        <td class="home-cc-num ${varCls}">${money(rowVariance)}</td>
                        <td class="books-cash-recon-verified">
                            <label class="books-check-label">
                                <input type="checkbox" name="${prefix}_verified"${row.verified ? " checked" : ""}>
                                Verified
                            </label>
                        </td>
                        <td>
                            <input type="text" class="books-input" name="${prefix}_note" value="${escapeHtml(row.note)}" placeholder="Note">
                        </td>
                    </tr>`;
            })
            .join("");
    }

    function num(v) {
        return M().num(v);
    }

    /** Zero = green; negative = red; positive = default text (no warning color). */
    function varianceColorClass(value) {
        const v = num(value);
        if (Math.abs(v) < 0.005) return "books-cash-recon-var--ok";
        if (v < 0) return "books-cash-recon-var--bad";
        return "";
    }

    function reconSummaryClass(section) {
        if (section.matched) return "books-cash-recon-summary books-cash-recon-summary--matched";
        const v =
            section.deposit != null ? num(section.depositVariance) : num(section.variance);
        const pending =
            Math.abs(v) < 0.005 &&
            section.countedTotal > 0 &&
            !section.allVerified &&
            (section.deposit == null || section.depositMatch);
        if (pending) return "books-cash-recon-summary books-cash-recon-summary--pending";
        if (v < -0.005) return "books-cash-recon-summary books-cash-recon-summary--variance";
        return "books-cash-recon-summary";
    }

    function renderReconSection(title, hint, section, depositField, depositLabel, extraHtml) {
        if (!section.applicable) return "";
        const rows = section.rows || [];
        const summaryCls = reconSummaryClass(section);
        const depositVal = section.deposit == null ? "" : amountValue(section.deposit);
        const depositVarCls =
            section.deposit == null ? "" : varianceColorClass(section.depositVariance);

        return `
            <section class="books-cash-recon-block">
                <h3 class="books-subtitle">${escapeHtml(title)}</h3>
                ${hint ? `<p class="books-hint">${hint}</p>` : ""}
                <div class="${summaryCls}">
                    <div class="books-cash-recon-totals">
                        <span><em>Received</em> <strong>${money(section.receivedTotal)}</strong></span>
                        ${
                            section.expectedNetCash != null
                                ? `<span><em>Cash sales</em> <strong>${money(section.expectedGross)}</strong></span>`
                                : section.expectedGross != null &&
                                    Math.abs(section.expectedGross - section.expectedDeposit) > 0.005
                                  ? `<span><em>Register cash</em> <strong>${money(section.expectedGross)}</strong></span>`
                                  : ""
                        }
                        ${
                            section.expectedNetCash != null
                                ? `<span><em>Expected cash (net)</em> <strong>${money(section.expectedNetCash)}</strong></span>`
                                : ""
                        }
                        ${
                            section.officeCashExpensesTotal > 0
                                ? `<span><em>Office cash expenses</em> <strong>${money(section.officeCashExpensesTotal)}</strong> <span class="books-cash-recon-var-hint">(P&amp;L only)</span></span>`
                                : ""
                        }
                        ${
                            section.dailyRegisterPayoutsAll > 0 &&
                            section.dailyRegisterPayoutsTrackOnly > 0 &&
                            section.dailyRegisterPayouts !== section.dailyRegisterPayoutsAll
                                ? `<span><em>Other cash pay out</em> <strong>− ${money(section.dailyRegisterPayouts)}</strong></span>
                                   <span><em>Track only (payouts)</em> <strong>− ${money(section.dailyRegisterPayoutsTrackOnly)}</strong></span>`
                                : section.dailyRegisterPayoutsAll > 0
                                  ? `<span><em>Register payouts (Daily sheet)</em> <strong>− ${money(section.dailyRegisterPayoutsAll)}</strong></span>`
                                  : section.dailyRegisterPayouts > 0
                                    ? `<span><em>Other cash pay out</em> <strong>− ${money(section.dailyRegisterPayouts)}</strong></span>`
                                    : section.dailyRegisterPayoutsTrackOnly > 0
                                      ? `<span><em>Track only (payouts)</em> <strong>− ${money(section.dailyRegisterPayoutsTrackOnly)}</strong></span>`
                                      : ""
                        }
                        ${
                            section.payOutTotal > 0
                                ? `<span><em>Pay out (reconciliation)</em> <strong>${money(section.payOutTotal)}</strong></span>`
                                : ""
                        }
                        ${
                            section.payOutTotal > 0 && section.expectedNetCash == null
                                ? `<span><em>Total received</em> <strong>${money(section.countedTotal)}</strong></span>`
                                : ""
                        }
                        <span><em>Expected deposit</em> <strong>${money(section.expectedDeposit)}</strong></span>
                        ${
                            section.deposit != null
                                ? `<span><em>Received / deposited</em> <strong>${money(section.deposit)}</strong></span>
                                   <span><em>Cash variance</em> <strong class="${varianceColorClass(section.depositVariance)}">${money(section.depositVariance)}</strong></span>`
                                : `<span><em>Cash variance</em> <strong class="${varianceColorClass(section.variance)}" title="Received minus expected cash (net)">${money(section.variance)}</strong> <span class="books-cash-recon-var-hint">(Received − expected cash net)</span></span>`
                        }
                        <span><em>Verified</em> <strong>${section.verifiedCount} / ${section.shiftCount}</strong></span>
                    </div>
                </div>
                ${
                    rows.length
                        ? renderReconCardsGrid(rows)
                        : `<p class="books-hint">Enter ${escapeHtml(title.toLowerCase())} amounts on the <strong>Daily sheet</strong> first.</p>`
                }
                ${extraHtml || ""}
                <label class="books-label books-cash-recon-deposit-field">${escapeHtml(depositLabel)}
                    <input ${amountInputAttrs(depositField, depositVal)}>
                </label>
                ${
                    section.deposit != null
                        ? `<p class="books-total-line books-cash-recon-deposit-check ${depositVarCls}">Cash variance: ${money(section.depositVariance)}${section.depositMatch ? " — matches expected" : ""}</p>`
                        : ""
                }
            </section>`;
    }

    function renderReconShiftCard(row, options = {}) {
        const readonly = options.readonly === true;
        const prefix = row.namePrefix;
        const varCls = varianceColorClass(row.variance);
        const balanced = Math.abs(num(row.variance)) < 0.005;
        const title = row.shiftLabel || row.rowLabel;
        const subtitle = row.shiftLabel && row.rowLabel !== row.shiftLabel ? row.rowLabel : "";

        if (readonly) {
            return `
                <div class="books-recon-card books-recon-card--readonly">
                    <div class="books-recon-card-head">
                        <strong>${escapeHtml(title)}</strong>
                        ${subtitle ? `<span>${escapeHtml(subtitle)}</span>` : ""}
                        <span class="books-register-recon-status${balanced && row.verified ? " books-register-recon-status--ok" : ""}">
                            ${row.verified ? (balanced ? "Verified" : "Verified · variance") : balanced ? "Balanced" : "Open"}
                        </span>
                    </div>
                    <div class="books-recon-card-stats">
                        <div><span>Expected</span><strong>${money(row.expected)}</strong></div>
                        <div><span>Received</span><strong>${money(row.counted)}</strong></div>
                        <div><span>Pay out</span><strong>${money(row.payOut)}</strong></div>
                        <div><span>Variance</span><strong class="${varCls}">${money(row.variance)}</strong></div>
                    </div>
                </div>`;
        }

        return `
            <div class="books-recon-card">
                <div class="books-recon-card-head">
                    <strong>${escapeHtml(row.rowLabel)}</strong>
                    <span>${escapeHtml(row.shiftLabel || "")}</span>
                </div>
                <div class="books-recon-card-stats">
                    <div><span>Expected</span><strong>${money(row.expected)}</strong></div>
                    <div><span>Variance</span><strong class="${varCls}">${money(row.variance)}</strong></div>
                </div>
                <label class="books-label">Received
                    <input ${amountInputAttrs(`${prefix}_counted`, row.counted)} aria-label="Received">
                </label>
                ${
                    row.kind === "register"
                        ? `<div class="books-recon-card-payout"><span>Pay out</span><strong>${money(row.payOut)}</strong></div>`
                        : renderPayOutsCell(prefix, row.payOuts)
                }
                <label class="books-check-label books-register-recon-verified">
                    <input type="checkbox" name="${prefix}_verified"${row.verified ? " checked" : ""}>
                    Verified
                </label>
                <label class="books-label">Note
                    <input type="text" class="books-input" name="${prefix}_note" value="${escapeHtml(row.note || "")}" placeholder="Optional">
                </label>
            </div>`;
    }

    function groupReconRowsByLabel(rows) {
        const groups = [];
        const map = new Map();
        (rows || []).forEach((row) => {
            const key = row.regKey || row.rowLabel || "row";
            if (!map.has(key)) {
                const group = { key, label: row.rowLabel || key, rows: [] };
                map.set(key, group);
                groups.push(group);
            }
            map.get(key).rows.push(row);
        });
        return groups;
    }

    function renderReconCardsGrid(rows, options = {}) {
        if (!rows?.length) return "";
        const flatAll = options.flatAll === true;
        const cardClass = flatAll ? "books-recon-cards books-recon-cards--all" : "books-recon-cards";

        if (flatAll) {
            return `<div class="${cardClass}">${rows
                .map((r) =>
                    renderReconShiftCard(
                        {
                            ...r,
                            shiftLabel: `${r.rowLabel} · ${r.shiftLabel}`,
                            rowLabel: `${r.rowLabel} · ${r.shiftLabel}`,
                        },
                        options
                    )
                )
                .join("")}</div>`;
        }

        const groups = groupReconRowsByLabel(rows);
        const multiShiftGroups = groups.some((g) => g.rows.length > 1);

        if (!multiShiftGroups) {
            return `<div class="${cardClass}">${rows.map((r) => renderReconShiftCard(r, options)).join("")}</div>`;
        }

        return groups
            .map(
                (group) => `
            <div class="books-recon-unit">
                <h4 class="books-recon-unit-title">${escapeHtml(group.label)}</h4>
                <div class="books-recon-cards">
                    ${group.rows.map((r) => renderReconShiftCard(r, options)).join("")}
                </div>
            </div>`
            )
            .join("");
    }

    /** Register section on Cash reconciliation tab — day deposit only; per-shift entry is on Daily sheet. */
    function renderRegisterDepositSection(section, extraHtml) {
        if (!section.applicable) return "";
        const depositVal = section.deposit == null ? "" : amountValue(section.deposit);
        const depositVarCls =
            section.deposit == null ? "" : varianceColorClass(section.depositVariance);
        const summaryCls = reconSummaryClass(section);
        const cardsHtml = renderReconCardsGrid(section.rows || [], { readonly: true, flatAll: true });

        return `
            <section class="books-cash-recon-block">
                <h3 class="books-subtitle">Register day deposit</h3>
                <p class="books-hint">Count and verify each shift on the <strong>Daily sheet</strong>. Enter the bank deposit for the day here.</p>
                <div class="${summaryCls}">
                    <div class="books-cash-recon-totals">
                        <span><em>Received (shifts)</em> <strong>${money(section.receivedTotal)}</strong></span>
                        <span><em>Cash sales</em> <strong>${money(section.expectedGross)}</strong></span>
                        <span><em>Expected deposit</em> <strong>${money(section.expectedDeposit)}</strong></span>
                        <span><em>Verified</em> <strong>${section.verifiedCount} / ${section.shiftCount}</strong></span>
                        ${
                            section.deposit != null
                                ? `<span><em>Deposited</em> <strong>${money(section.deposit)}</strong></span>
                                   <span><em>Cash variance</em> <strong class="${depositVarCls}">${money(section.depositVariance)}</strong></span>`
                                : ""
                        }
                    </div>
                </div>
                ${
                    cardsHtml ||
                    `<p class="books-hint">Enter register sales and received cash on the <strong>Daily sheet</strong> first.</p>`
                }
                ${extraHtml || ""}
                <label class="books-label books-cash-recon-deposit-field">Register received / deposited ($)
                    <input ${amountInputAttrs("cr_day_deposit", depositVal)}>
                </label>
                ${
                    section.deposit != null
                        ? `<p class="books-total-line books-cash-recon-deposit-check ${depositVarCls}">Cash variance: ${money(section.depositVariance)}${section.depositMatch ? " — matches expected" : ""}</p>`
                        : ""
                }
            </section>`;
    }

    function dailyRegisterShiftPayoutLines(day) {
        const d = M().normalizeDayDoc(day);
        const lines = [];
        ["register1", "register2"].forEach((regKey, regIdx) => {
            ["shift1", "shift2"].forEach((sh, shiftIdx) => {
                const shift = d[regKey]?.[sh];
                const amount = M().num(shift?.cashPayOut);
                if (amount === 0) return;
                lines.push({
                    label: `Register ${regIdx + 1} · Shift ${shiftIdx + 1}`,
                    amount,
                    expense: !!shift?.cashPayOutExpense,
                });
            });
        });
        return lines;
    }

    function dailyRegisterPayoutLines(day) {
        const d = M().normalizeDayDoc(day);
        const trackOnly = [];
        const recon = [];
        if (M().num(d.inHouseAccount) !== 0) {
            trackOnly.push({ label: "In house account", amount: d.inHouseAccount });
        }
        if (M().num(d.lotteryPayOut) !== 0) {
            trackOnly.push({ label: "Lottery pay out", amount: d.lotteryPayOut });
        }
        if (M().num(d.pullTabPayout) !== 0) {
            trackOnly.push({ label: "Pull tab payout", amount: d.pullTabPayout });
        }
        if (M().num(d.otherCashPayOut) !== 0) {
            recon.push({ label: "Other cash pay out", amount: d.otherCashPayOut });
        }
        return { trackOnly, recon };
    }

    function renderPayoutLinesList(lines) {
        if (!lines.length) return "";
        return `<ul class="books-cash-recon-expense-list">
            ${lines
                .map(
                    (row) =>
                        `<li><span>${escapeHtml(row.label)}</span> <strong>${money(M().num(row.amount))}</strong></li>`
                )
                .join("")}
        </ul>`;
    }

    function renderCashReconciliation() {
        if (!showField("cashReconciliation")) {
            return `<p class="data-list-empty">Cash reconciliation is turned off for this facility. Enable it under Facilities → Customize.</p>`;
        }
        const summary = M().cashReconciliationSummary(state.day);
        const reg = summary.register;
        const sectionEntries = [
            { section: summary.register, fieldId: "registers" },
            { section: summary.lottery, fieldId: "lottery" },
            { section: summary.pulltab, fieldId: "pulltabs" },
            { section: summary.wind, fieldId: "windStations" },
            { section: summary.keno, fieldId: "kenoStations" },
        ];
        const sections = sectionEntries
            .filter((e) => e.section.applicable && showField(e.fieldId))
            .map((e) => e.section);
        const matchLabel =
            sections.length === 0
                ? "No cash to reconcile — enter shift or machine data on the Daily sheet first"
                : summary.matched
                  ? "All cash reconciled for this day"
                  : "Finish shift counts on Daily sheet, then enter day deposit below";

        const cashExpenseLines = (state.day.cashExpenses || []).filter(
            (row) => M().num(row.amount) !== 0 || (row.description && String(row.description).trim())
        );
        const cashExpenseList =
            cashExpenseLines.length === 0
                ? ""
                : `<ul class="books-cash-recon-expense-list">
                    ${cashExpenseLines
                        .map(
                            (row) =>
                                `<li><span>${escapeHtml(row.description || "(no description)")}</span> <strong>${money(M().num(row.amount))}</strong></li>`
                        )
                        .join("")}
                   </ul>`;
        const payoutLines = dailyRegisterPayoutLines(state.day);
        const registerExtraParts = [];
        if ((reg.officeCashExpensesTotal || reg.cashExpensesTotal) > 0) {
            registerExtraParts.push(`<div class="books-cash-recon-expenses">
                    <h4 class="books-subtitle books-subtitle--sm">Office cash expenses (P&amp;L only — not in register deposit)</h4>
                    ${cashExpenseList}
                   </div>`);
        }
        if (payoutLines.recon.length > 0) {
            registerExtraParts.push(`<div class="books-cash-recon-expenses">
                    <h4 class="books-subtitle books-subtitle--sm">Other cash pay out (Daily sheet — lowers expected cash)</h4>
                    ${renderPayoutLinesList(payoutLines.recon)}
                   </div>`);
        }
        if (payoutLines.trackOnly.length > 0) {
            registerExtraParts.push(`<div class="books-cash-recon-expenses books-cash-recon-track-only">
                    <h4 class="books-subtitle books-subtitle--sm">Track only — in house, lottery pay out, pull tab payout</h4>
                    <p class="books-hint">Track-only payouts (in house, lottery pay out, pull tab) are recorded separately from cash expenses but still reduce <strong>expected cash (net)</strong>. Other cash pay out also reduces expected cash.</p>
                    ${renderPayoutLinesList(payoutLines.trackOnly)}
                   </div>`);
        }
        const shiftPayoutLines = dailyRegisterShiftPayoutLines(state.day);
        if (shiftPayoutLines.length > 0) {
            registerExtraParts.push(`<div class="books-cash-recon-expenses">
                    <h4 class="books-subtitle books-subtitle--sm">Shift pay outs (Daily sheet — under each register shift)</h4>
                    <ul class="books-cash-recon-expense-list">
                        ${shiftPayoutLines
                            .map(
                                (row) =>
                                    `<li><span>${escapeHtml(row.label)}</span> <strong>${money(row.amount)}</strong> <em class="books-hint">${row.expense ? "· counts as expense" : "· track only"}</em></li>`
                            )
                            .join("")}
                    </ul>
                   </div>`);
        }
        const registerExtra = registerExtraParts.join("");
        const closed = isBooksLocked();
        const fieldsetAttr = closed ? " disabled" : "";

        return `
            <div class="books-panel data-input-form">
                ${renderDayStatusBanner()}
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>

                <div class="books-cash-recon-summary${summary.matched ? " books-cash-recon-summary--matched" : ""}">
                    <p class="books-cash-recon-summary-title">${escapeHtml(matchLabel)}</p>
                </div>

                <p class="books-hint">Reconcile each <strong>register shift</strong> on the Daily sheet. Use this tab for the <strong>day deposit</strong> and for lottery, pulltab, and station cash.</p>

                <fieldset class="books-day-fields"${fieldsetAttr}>
                ${
                    sections.length === 0
                        ? `<p class="data-list-empty">Nothing to reconcile for this day yet.</p>`
                        : ""
                }

                ${showField("registers") ? renderRegisterDepositSection(reg, registerExtra) : ""}

                ${showField("lottery")
                    ? renderReconSection(
                          "Lottery cash",
                          "Expected from lottery cash per shift on the Daily sheet.",
                          summary.lottery,
                          "cr_lottery_deposit",
                          "Lottery received / deposited ($)"
                      )
                    : ""}

                ${showField("pulltabs")
                    ? renderReconSection(
                          "Pulltab cash",
                          "Expected from pulltab machine cash on the Daily sheet (one row per machine).",
                          summary.pulltab,
                          "cr_pulltab_deposit",
                          "Pulltab received / deposited ($)"
                      )
                    : ""}

                ${showField("windStations")
                    ? renderReconSection(
                          "Wind station cash",
                          "Expected from wind station cash on the Daily sheet.",
                          summary.wind,
                          "cr_wind_deposit",
                          "Wind station received / deposited ($)"
                      )
                    : ""}

                ${showField("kenoStations")
                    ? renderReconSection(
                          "Keno station cash",
                          "Expected from keno station cash on the Daily sheet.",
                          summary.keno,
                          "cr_keno_deposit",
                          "Keno station received / deposited ($)"
                      )
                    : ""}

                <label class="books-label">Day notes
                    <input type="text" class="books-input" name="cr_day_note" value="${escapeHtml(state.day.cashReconciliation?.note || "")}" placeholder="Optional">
                </label>
                </fieldset>

                ${closed ? "" : `<button type="button" class="btn books-save" id="di-save-day">Save cash reconciliation</button>`}
            </div>`;
    }

    function renderBooksReceivablesTab() {
        const main = window.OplixReceivablesUI
            ? OplixReceivablesUI.renderTab({
                  userId,
                  locationId: state.locationId,
                  monthId: state.monthId,
                  month: state.month,
                  receivables: state.receivables,
              })
            : '<p class="data-list-empty">Receivables unavailable.</p>';
        return `${main}${renderLegacyMonthReceivables()}`;
    }

    function renderMonthlyPanel() {
        const root = $("monthly-books-root");
        if (!root) return;
        try {
            if (!locations.length) {
                root.innerHTML = '<p class="data-list-empty">Add a facility first (Facilities tab).</p>';
                return;
            }
            root.innerHTML = `
                ${renderBooksToolbar("mb")}
                ${renderBooksHealthStrip()}
                ${renderMonthlyBooks()}`;
        } catch (err) {
            console.error("[Oplix] Monthly books render failed:", err);
            root.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Could not load Monthly books.")}</p>`;
        }
    }

    function renderDailyPanel() {
        const root = $("data-input-root");
        if (!root) return;
        try {
            renderInner(root);
        } catch (err) {
            console.error("[Oplix] Daily books render failed:", err);
            root.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Could not load Daily books.")}</p>`;
        }
    }

    function render() {
        renderDailyPanel();
        renderMonthlyPanel();
    }

    function renderInner(root) {
        if (!locations.length) {
            root.innerHTML = '<p class="data-list-empty">Add a facility first (Facilities tab).</p>';
            return;
        }

        const allTabs = [
            { id: "daily", label: "Daily sheet" },
            { id: "utilities", label: "Utilities & payroll" },
            { id: "payables", label: "Payables" },
            { id: "receivables", label: "Receivables" },
            { id: "cash-recon", label: "Cash reconciliation" },
        ];
        const tabs = allTabs.filter((t) => tabVisible(t.id));
        if (!tabs.some((t) => t.id === state.tab)) {
            state.tab = tabs[0]?.id || "daily";
        }

        let body = "";
        if (state.tab === "daily") body = renderDaily();
        else if (state.tab === "utilities") body = renderUtilitiesPayroll();
        else if (state.tab === "payables") {
            body =
                (isViewingClosedMonth()
                    ? `<p class="books-hint books-month-locked-hint">This month is closed — payables are read-only until you reopen from <button type="button" class="books-link-btn" id="di-open-monthly-books">Monthly books</button> in the sidebar.</p>`
                    : "") +
                (tabVisible("payables")
                    ? window.OplixPayablesUI
                        ? OplixPayablesUI.renderTab({
                              userId,
                              locationId: state.locationId,
                              monthId: state.monthId,
                              payables: state.payables,
                          })
                        : '<p class="data-list-empty">Payables unavailable.</p>'
                    : '<p class="data-list-empty">Payables is turned off for this facility.</p>');
        } else if (state.tab === "cash-recon") body = renderCashReconciliation();
        else {
            body =
                (isViewingClosedMonth()
                    ? `<p class="books-hint books-month-locked-hint">This month is closed — receivables are read-only until you reopen from <button type="button" class="books-link-btn" id="di-open-monthly-books">Monthly books</button> in the sidebar.</p>`
                    : "") +
                (tabVisible("receivables")
                    ? renderBooksReceivablesTab()
                    : '<p class="data-list-empty">Receivables is turned off for this facility.</p>');
        }

        const loc = currentLocation();
        const customizeHint = loc
            ? `<p class="books-hint books-customize-hint">Daily books layout for this facility can be customized in <button type="button" class="books-link-btn" id="di-open-books-config">Facilities → Customize</button>.</p>`
            : "";
        const monthClosedBanner = isViewingClosedMonth()
            ? renderMonthStatusBanner({ onDailyPanel: true })
            : "";

        root.innerHTML = `
            ${renderBooksToolbar("di")}
            ${renderBooksHealthStrip()}
            ${monthClosedBanner}
            ${customizeHint}
            <p class="books-hint books-amount-tip">Amount fields: use <strong>+</strong> or <strong>−</strong> to add/subtract (e.g. <code>100+50-25</code>). Tab out of the field to total.</p>
            <nav class="books-tabs">
                ${tabs.map((t) => `<button type="button" class="books-tab${state.tab === t.id ? " active" : ""}" data-di-tab="${t.id}">${t.label}</button>`).join("")}
            </nav>
            ${renderExpenseDescDatalist()}
            ${body}
            ${state.tab === "daily" || state.tab === "cash-recon" ? renderClosedDayTiles() : ""}`;

        if (state.tab === "payables" && window.OplixPayablesUI) {
            const payRoot = root.querySelector("[data-pay-section]");
            if (payRoot) {
                payRoot.dataset.payBound = "";
                OplixPayablesUI.bind(payRoot, {
                    userId,
                    locationId: state.locationId,
                    monthId: state.monthId,
                    payables: state.payables,
                    onRecordCheckPayment: recordCheckFromPayable,
                    onRefresh: async () => {
                        await loadPayables();
                        render();
                    },
                });
            }
        }
        if (state.tab === "receivables" && window.OplixReceivablesUI) {
            const recRoot = root.querySelector("[data-rec-section]");
            if (recRoot) {
                recRoot.dataset.recBound = "";
                OplixReceivablesUI.bind(recRoot, {
                    userId,
                    locationId: state.locationId,
                    monthId: state.monthId,
                    month: state.month,
                    receivables: state.receivables,
                    onSyncBooks: syncMonthFromReceivable,
                    onRefresh: async () => {
                        await loadReceivables();
                        render();
                    },
                });
            }
        }
    }

    function ensureBooksInitialized(uid, locs) {
        userId = uid;
        locations = locs || [];
        if (locations.length && !state.locationId) state.locationId = locations[0].id;
        bindShell();
    }

    window.OplixDataInput = {
        init(uid, locs) {
            ensureBooksInitialized(uid, locs);
            viewMode = "daily";
            render();
            if (state.locationId) loadCurrent();
        },
        onShow() {
            viewMode = "daily";
            if (userId && state.locationId) loadCurrent();
            else render();
        },
        resetToRoot() {
            state.tab = "daily";
            viewMode = "daily";
            render();
            if (userId && state.locationId) loadCurrent();
        },
        refreshIfOpen(locationId, monthId) {
            if (
                userId &&
                state.locationId === locationId &&
                state.monthId === monthId
            ) {
                loadCurrent();
            }
        },
        async openCashReconciliation(opts = {}) {
            const { dayId, monthId, locationId } = opts;
            bindShell();
            viewMode = "daily";
            if (window.showDashboardPanel) {
                await window.showDashboardPanel("data-input");
            }
            if (locationId) state.locationId = locationId;
            if (monthId) state.monthId = monthId;
            else if (dayId) state.monthId = String(dayId).slice(0, 7);
            if (dayId) state.dayId = dayId;
            state.tab = "cash-recon";
            if (state.locationId) {
                await loadCurrent();
            } else {
                render();
            }
        },
    };

    window.OplixMonthlyBooks = {
        init(uid, locs) {
            ensureBooksInitialized(uid, locs);
            viewMode = "monthly";
            render();
            if (state.locationId) loadCurrent();
        },
        onShow() {
            viewMode = "monthly";
            if (userId && state.locationId) loadCurrent();
            else render();
        },
        resetToRoot() {
            viewMode = "monthly";
            render();
            if (userId && state.locationId) loadCurrent();
        },
    };
})();
