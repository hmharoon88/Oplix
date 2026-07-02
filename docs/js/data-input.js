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
        dirty: false,
        expenseDescriptions: [],
    };

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
        $("di-status").textContent = "Adding utility…";
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
        $("di-status").textContent = "Utility added.";
        render();
        setTimeout(() => {
            if ($("di-status")?.textContent === "Utility added.") $("di-status").textContent = "";
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
        $("di-status").textContent = "Removing…";
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
        $("di-status").textContent = "Utility removed.";
        render();
        setTimeout(() => {
            if ($("di-status")?.textContent === "Utility removed.") $("di-status").textContent = "";
        }, 2000);
    }

    async function loadPayables() {
        if (!state.locationId || !window.OplixPayablesStore) {
            state.payables = [];
            return;
        }
        state.payables = await OplixPayablesStore.list(userId, state.locationId);
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
        const root = $("data-input-root");
        if (!root) return;
        root.querySelectorAll(".books-input-amount").forEach(normalizeAmountField);
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
                syncFromForm();
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
                addLine(add.dataset.diAdd);
                render();
                return;
            }
            const rm = e.target.closest("[data-di-rm]");
            if (rm) {
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
        }
    }

    function removeLine(list, id) {
        if (list === "receivables") {
            state.month.receivables = state.month.receivables.filter((r) => r.id !== id);
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
        const root = $("data-input-root");
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

        const registerFields = ["cardSale", "cashSale"];
        ["register1", "register2"].forEach((regKey) => {
            if (!state.day[regKey]) state.day[regKey] = M().defaultRegisterUnit();
            ["shift1", "shift2"].forEach((sh) => {
                registerFields.forEach((f) => {
                    const el = root.querySelector(`[name="reg_${regKey}_${sh}_${f}"]`);
                    if (el) state.day[regKey][sh][f] = M().num(el.value);
                });
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
        syncLinesFromDom("checksAch", ["date", "description", "checkNo", "amount"]);
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

    async function loadCurrent() {
        if (!state.locationId) return;
        const statusEl = $("di-status");
        if (statusEl) statusEl.textContent = "Loading…";
        try {
            const { month, daysById } = await Store().loadMonth(
                userId,
                state.locationId,
                state.monthId
            );
            await Promise.all([loadUtilityProviders(), loadPayables()]);
            state.month = month;
            state.month.utilities = M().normalizeMonthUtilities(
                state.month.utilities,
                M().mergeUtilityKeys(state.utilityProviders, state.month.utilities)
            );
            state.daysById = daysById;
            state.day = M().normalizeDayDoc(daysById[state.dayId]);
            refreshExpenseDescriptions();
            state.dirty = false;
            if (statusEl) statusEl.textContent = "";
            render();
        } catch (err) {
            console.error("[Oplix] Daily books load failed:", err);
            if (statusEl) statusEl.textContent = "";
            const root = $("data-input-root");
            if (root) {
                root.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Failed to load Daily books.")}</p>`;
            }
        }
    }

    async function saveMonth() {
        normalizeAllAmountFields();
        syncFromForm();
        $("di-status").textContent = "Saving…";
        await Store().saveMonth(userId, state.locationId, state.monthId, state.month);
        window.OplixAnalytics?.invalidateCache?.();
        state.dirty = false;
        $("di-status").textContent = "Month saved.";
        setTimeout(() => {
            if ($("di-status").textContent === "Month saved.") $("di-status").textContent = "";
        }, 2000);
    }

    async function saveDay() {
        normalizeAllAmountFields();
        syncFromForm();
        pruneAllReconPayOuts();
        $("di-status").textContent = "Saving…";
        await Promise.all([
            Store().saveDay(userId, state.locationId, state.monthId, state.dayId, state.day),
            Store().saveMonth(userId, state.locationId, state.monthId, state.month),
        ]);
        window.OplixAnalytics?.invalidateCache?.();
        state.daysById[state.dayId] = { ...state.day, _dayId: state.dayId };
        rememberExpenseDescriptionsFromDay(state.day);
        state.dirty = false;
        $("di-status").textContent = "Day saved.";
        if (state.tab === "cash-recon") render();
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
    ];

    function renderRegisterUnit(title, regKey, unit) {
        const total = M().registerBlockTotal(unit);
        return `
            <h3 class="books-subtitle">${escapeHtml(title)}</h3>
            ${renderShiftBlock("Shift 1", `reg_${regKey}_shift1`, unit.shift1, REGISTER_SHIFT_FIELDS)}
            ${renderShiftBlock("Shift 2", `reg_${regKey}_shift2`, unit.shift2, REGISTER_SHIFT_FIELDS)}
            <p class="books-total-line">${escapeHtml(title)} total: ${money(total.card + total.cash)} card+cash</p>`;
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

    function renderLotteryDaily() {
        const lot = state.day.lottery || { shift1: M().emptyGamingShift(), shift2: M().emptyGamingShift() };
        const total = M().lotteryDayTotal(state.day);
        const shiftFields = (prefix, data) => `
            <fieldset class="books-fieldset">
                <legend>${escapeHtml(prefix.replace("lot_", "").replace("_", " "))}</legend>
                <div class="books-grid-2">
                    <label class="books-label">Cash
                        <input ${amountInputAttrs(`${prefix}_cash`, data.cash)}>
                    </label>
                    <label class="books-label">O/S
                        <input ${amountInputAttrs(`${prefix}_overShort`, data.overShort)}>
                    </label>
                </div>
            </fieldset>`;
        return `
            <h3 class="books-subtitle">Lottery</h3>
            <p class="books-hint">Lottery cash collected per shift. Reconcile received amounts on <strong>Cash reconciliation</strong>.</p>
            ${shiftFields("lot_shift1", lot.shift1 || M().emptyGamingShift())}
            ${shiftFields("lot_shift2", lot.shift2 || M().emptyGamingShift())}
            <p class="books-total-line">Lottery total: ${money(total.cash)} cash · O/S ${money(total.overShort)}</p>`;
    }

    function renderPulltabs() {
        const total = M().pulltabDayTotal(state.day);
        return `
            <h3 class="books-subtitle">Pulltab</h3>
            <p class="books-hint">One row per pulltab machine — enter the ticket number and amounts from each machine report.</p>
            ${renderLineList(
                "pulltabs",
                [
                    { name: "ticketNumber", label: "Ticket #" },
                    { name: "cash", label: "Cash", type: "number" },
                    { name: "winner", label: "Winners", type: "number" },
                    { name: "overShort", label: "O/S", type: "number" },
                ],
                null,
                false,
                "+ Add pulltab machine"
            )}
            <p class="books-total-line">Pulltab total: ${money(total.cash)} cash · Winners ${money(total.winner)} · O/S ${money(total.overShort)}</p>`;
    }

    function renderWindStations() {
        const total = M().windStationDayTotal(state.day);
        const count = (state.day.windStations || []).length;
        const canAdd = count < 3;
        return `
            <h3 class="books-subtitle">Wind station</h3>
            <p class="books-hint">Cash collected at each wind station (add up to 3 stations per day).</p>
            ${renderLineList(
                "windStations",
                [
                    { name: "station", label: "Station" },
                    { name: "cash", label: "Cash", type: "number" },
                ],
                null,
                false,
                canAdd ? "+ Add wind station" : false
            )}
            <p class="books-total-line">Wind station total: ${money(total)} cash</p>`;
    }

    function renderKenoStations() {
        const total = M().kenoStationDayTotal(state.day);
        const count = (state.day.kenoStations || []).length;
        const canAdd = count < 3;
        return `
            <h3 class="books-subtitle">Keno station</h3>
            <p class="books-hint">Cash collected at each keno station (add up to 3 stations per day).</p>
            ${renderLineList(
                "kenoStations",
                [
                    { name: "station", label: "Station" },
                    { name: "cash", label: "Cash", type: "number" },
                ],
                null,
                false,
                canAdd ? "+ Add keno station" : false
            )}
            <p class="books-total-line">Keno station total: ${money(total)} cash</p>`;
    }

    function renderUtilitiesPayroll() {
        const utilityKeys = mergedUtilityKeys();
        const utilRows = utilityKeys
            .map((u) => {
                const deletable = canDeleteUtility(u.key);
                return `
            <div class="books-util-row" data-di-util-key="${escapeHtml(u.key)}">
                <span class="books-util-label" title="${escapeHtml(u.label)}">${escapeHtml(u.label)}</span>
                <input ${amountInputAttrs(`util_${u.key}`, state.month.utilities[u.key])}>
                ${
                    deletable
                        ? `<button type="button" class="books-rm" data-di-util-rm="${escapeHtml(u.key)}" title="Remove utility">×</button>`
                        : `<span class="books-util-spacer" aria-hidden="true"></span>`
                }
            </div>`;
            })
            .join("");

        const payrollLines = (state.month.payrollLines || []).map((l) =>
            M().normalizePayrollLine(l)
        );
        const payrollSynced = payrollLines.length > 0;

        const payrollFields = payrollSynced
            ? ""
            : ["week1", "week2", "week3", "week4"]
                  .map(
                      (w, i) => `
            <label class="books-label">Week ${i + 1}
                <input ${amountInputAttrs(`payroll_${w}`, state.month.payroll[w])}>
            </label>`
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

        const payrollLinesTable = payrollSynced
            ? `
                <div class="home-card home-cc-table-wrap payroll-books-table">
                    <table class="home-cc-table">
                        <thead>
                            <tr>
                                <th>Employee</th>
                                <th class="home-cc-num">Hours</th>
                                <th class="home-cc-num">Rate</th>
                                <th class="home-cc-num">Pay</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${payrollLines
                                .map(
                                    (l) => `
                                <tr>
                                    <td>${escapeHtml(l.employeeName || "Employee")}</td>
                                    <td class="home-cc-num">${M().formatAmountForInput(l.hours)}</td>
                                    <td class="home-cc-num">${money(l.hourlyRate)}</td>
                                    <td class="home-cc-num">${money(l.pay)}</td>
                                </tr>`
                                )
                                .join("")}
                        </tbody>
                    </table>
                </div>
                <p class="books-hint">Synced from the <strong>Payroll</strong> tab — this total is included in Books summary automatically. Edit hours in Payroll, save, and it updates here. You do not need to enter weekly totals below.</p>`
            : `<p class="books-hint">Enter weekly totals below, or use the <strong>Payroll</strong> tab to enter hours by employee (syncs here and into Books summary when you save).</p>`;

        const payrollWeekBlock = payrollFields
            ? `<h4 class="books-week-heading">Weekly totals</h4>
                <div class="books-payroll-weeks">${payrollFields}</div>`
            : "";

        const parts = ['<div class="books-panel data-input-form">'];
        if (showField("utilities")) {
            parts.push(`<h3 class="books-subtitle">Utilities</h3>
                <p class="books-hint">Monthly amounts per utility. Standard types (Internet, Water, Electric, etc.) are always listed; add custom ones below.</p>
                <div class="books-util-list" data-di-util-list>
                    <div class="books-util-head">
                        <span>Utility</span>
                        <span>Amount</span>
                        <span></span>
                    </div>
                    ${utilRows}
                    <button type="button" class="books-add-line" data-di-util-add>+ Add utility</button>
                </div>
                <p class="books-total-line">Utilities total: <strong>${money(utilTotal)}</strong></p>`);
        }
        if (showField("payroll")) {
            parts.push(`<h3 class="books-subtitle">Payroll</h3>
                ${payrollLinesTable}
                ${payrollWeekBlock}
                <p class="books-total-line">Payroll total: <strong>${money(payTotal)}</strong></p>`);
        }
        if (showField("salesTax") || showField("accountant")) {
            parts.push(`<h3 class="books-subtitle">Other monthly</h3>
                <div class="books-grid-2">
                    ${
                        showField("salesTax")
                            ? `<label class="books-label">Sales tax
                        <input ${amountInputAttrs("salesTax", state.month.salesTax)}>
                    </label>`
                            : ""
                    }
                    ${
                        showField("accountant")
                            ? `<label class="books-label">Accountant
                        <input ${amountInputAttrs("accountant", state.month.accountant)}>
                    </label>`
                            : ""
                    }
                </div>`);
        }
        const customMonth = renderCustomBooksFields("month", state.month.customAmounts);
        if (customMonth) parts.push(customMonth);
        parts.push(
            '<button type="button" class="btn books-save" id="di-save-month">Save month (utilities & payroll)</button>',
            "</div>"
        );
        return parts.join("\n");
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
            <p class="books-hint">Cash paid out from the register — not added to merch, credit card, or fuel.</p>
            <div class="books-grid-2">
                <label class="books-label">In house account ($)
                    <input ${amountInputAttrs("in_house_account", state.day.inHouseAccount)}>
                </label>
                <label class="books-label">Lottery pay out ($)
                    <input ${amountInputAttrs("lottery_pay_out", state.day.lotteryPayOut)}>
                </label>
                <label class="books-label">Pull tab payout ($)
                    <input ${amountInputAttrs("pull_tab_payout", state.day.pullTabPayout)}>
                </label>
                <label class="books-label">Other cash pay out ($)
                    <input ${amountInputAttrs("other_cash_pay_out", state.day.otherCashPayOut)}>
                </label>
            </div>`;
    }

    function renderDailyExpensesBlock() {
        const parts = [];
        if (showField("cashExpenses")) {
            parts.push(`<h3 class="books-subtitle">Cash expense</h3>
                    ${renderLineList("cashExpenses", [
                        { name: "description", label: "Description" },
                        { name: "amount", label: "Amount", type: "number" },
                        { name: "overShort", label: "O/S", type: "number" },
                    ])}`);
        }
        if (showField("checksAch")) {
            parts.push(`<h3 class="books-subtitle">Checks / ACH</h3>
                    ${renderLineList("checksAch", [
                        { name: "date", label: "Date" },
                        { name: "description", label: "Description" },
                        { name: "checkNo", label: "Check #" },
                        { name: "amount", label: "Amount", type: "number" },
                    ])}`);
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
                renderRegisterUnit("Register 1", "register1", state.day.register1),
                renderRegisterUnit("Register 2", "register2", state.day.register2),
                `<p class="books-total-line">All registers (1 + 2): ${money(reg.card + reg.cash)} card+cash</p>
            <p class="books-hint">Register card/cash on the detail sheet is for shift reconciliation only — not added to merch, credit card, or fuel.</p>`
            );
        }
        const wayne = renderRegisterWaynePass();
        if (wayne) bodyParts.push(wayne);
        const payouts = renderRegisterPayoutFields();
        if (payouts) bodyParts.push(payouts);
        if (showField("pulltabs")) bodyParts.push(renderPulltabs());
        if (showField("windStations")) bodyParts.push(renderWindStations());
        if (showField("kenoStations")) bodyParts.push(renderKenoStations());
        if (showField("lottery")) bodyParts.push(renderLotteryDaily());
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
                `<h3 class="books-subtitle">Registers</h3>
            <p class="books-hint"><strong>Total sales</strong> in Books summary uses register card + cash (both registers, both shifts). Lottery and pulltab are tracked separately.</p>
            ${renderRegisterUnit("Register 1", "register1", state.day.register1)}
            ${renderRegisterUnit("Register 2", "register2", state.day.register2)}
            <p class="books-total-line">All registers (1 + 2): ${money(reg.card + reg.cash)} card+cash</p>`
            );
        }
        if (showField("pulltabs")) parts.push(renderPulltabs());
        if (showField("windStations")) parts.push(renderWindStations());
        if (showField("kenoStations")) parts.push(renderKenoStations());
        if (showField("lottery")) parts.push(renderLotteryDaily());
        const expenses = renderDailyExpensesBlock();
        if (expenses) parts.push(expenses);
        return parts.join("\n");
    }

    function renderDaily() {
        const reg = M().registerDayTotal(state.day);
        const gas = hasGasStation();
        const fuelSale = M().normalizeFuelSale(state.day.fuelSale);

        if (gas) {
            const gasSales = renderDailyGasSales(fuelSale);
            const detail = renderDailyDetailSheet(reg);
            return `
            <div class="books-panel data-input-form">
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>

                ${gasSales}
                ${detail}

                ${renderCustomBooksFields("daily", state.day.customAmounts)}

                <button type="button" class="btn books-save" id="di-save-day">Save this day</button>
            </div>`;
        }

        return `
            <div class="books-panel data-input-form">
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>

                ${renderDailyCStore()}

                ${renderCustomBooksFields("daily", state.day.customAmounts)}

                <button type="button" class="btn books-save" id="di-save-day">Save this day</button>
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
                const rowVariance = num(row.counted) + num(row.payOut) - num(row.expected);
                const varCls = varianceColorClass(rowVariance);
                return `
                    <tr>
                        <td>${escapeHtml(row[col1] || row.rowLabel)}</td>
                        <td>${escapeHtml(row[col2] || row.shiftLabel)}</td>
                        <td class="home-cc-num books-cash-recon-expected">${money(row.expected)}</td>
                        <td class="home-cc-num">
                            <input ${amountInputAttrs(`${prefix}_counted`, row.counted)} aria-label="Received">
                        </td>
                        <td class="books-cash-recon-payout-col">
                            ${renderPayOutsCell(prefix, row.payOuts)}
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
                            section.cashExpensesTotal > 0
                                ? `<span><em>Cash expenses</em> <strong>− ${money(section.cashExpensesTotal)}</strong></span>`
                                : ""
                        }
                        ${
                            section.dailyRegisterPayouts > 0
                                ? `<span><em>Register payouts (Daily sheet)</em> <strong>− ${money(section.dailyRegisterPayouts)}</strong></span>`
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
                                : `<span><em>Cash variance</em> <strong class="${varianceColorClass(section.variance)}">${money(section.variance)}</strong></span>`
                        }
                        <span><em>Verified</em> <strong>${section.verifiedCount} / ${section.shiftCount}</strong></span>
                    </div>
                </div>
                ${
                    rows.length
                        ? `<div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table books-cash-recon-table">
                        <thead>
                            <tr>
                                <th>${escapeHtml(title.includes("Register") ? "Register" : title.split(" ")[0])}</th>
                                <th>${rows[0]?.kind === "pulltab" ? "Ticket" : rows[0]?.kind === "wind" || rows[0]?.kind === "keno" ? "Type" : "Shift"}</th>
                                <th class="home-cc-num">Expected</th>
                                <th class="home-cc-num">Received</th>
                                <th class="home-cc-num">Pay out</th>
                                <th class="home-cc-num">Variance</th>
                                <th>Status</th>
                                <th>Note</th>
                            </tr>
                        </thead>
                        <tbody>${renderReconTableRows(rows)}</tbody>
                        <tfoot>
                            <tr class="books-cash-recon-total-row">
                                <td colspan="2"><strong>Day total</strong></td>
                                <td class="home-cc-num"><strong>${money(section.expectedTotal)}</strong></td>
                                <td class="home-cc-num"><strong>${money(section.receivedTotal)}</strong></td>
                                <td class="home-cc-num"><strong>${money(section.payOutTotal)}</strong></td>
                                <td class="home-cc-num"><strong class="${varianceColorClass(section.variance)}">${money(section.variance)}</strong></td>
                                <td colspan="2"></td>
                            </tr>
                        </tfoot>
                    </table>
                </div>`
                        : `<p class="books-hint">Enter ${escapeHtml(title.toLowerCase())} amounts on the <strong>Daily sheet</strong> first.</p>`
                }
                ${extraHtml || ""}
                <label class="books-label">${escapeHtml(depositLabel)}
                    <input ${amountInputAttrs(depositField, depositVal)}>
                </label>
                ${
                    section.deposit != null
                        ? `<p class="books-total-line books-cash-recon-deposit-check ${depositVarCls}">Cash variance: ${money(section.depositVariance)}${section.depositMatch ? " — matches expected" : ""}</p>`
                        : ""
                }
            </section>`;
    }

    function dailyRegisterPayoutLines(day) {
        const d = M().normalizeDayDoc(day);
        const lines = [];
        if (M().num(d.inHouseAccount) !== 0) {
            lines.push({ label: "In house account", amount: d.inHouseAccount });
        }
        if (M().num(d.lotteryPayOut) !== 0) {
            lines.push({ label: "Lottery pay out", amount: d.lotteryPayOut });
        }
        if (M().num(d.pullTabPayout) !== 0) {
            lines.push({ label: "Pull tab payout", amount: d.pullTabPayout });
        }
        if (M().num(d.otherCashPayOut) !== 0) {
            lines.push({ label: "Other cash pay out", amount: d.otherCashPayOut });
        }
        return lines;
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
                  : `Complete ${sections.length} section${sections.length === 1 ? "" : "s"} below`;

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
        const payoutList =
            payoutLines.length === 0
                ? ""
                : `<ul class="books-cash-recon-expense-list">
                    ${payoutLines
                        .map(
                            (row) =>
                                `<li><span>${escapeHtml(row.label)}</span> <strong>${money(M().num(row.amount))}</strong></li>`
                        )
                        .join("")}
                   </ul>`;
        const registerExtraParts = [];
        if (reg.cashExpensesTotal > 0) {
            registerExtraParts.push(`<div class="books-cash-recon-expenses">
                    <h4 class="books-subtitle books-subtitle--sm">Cash expenses (Daily sheet — lowers expected cash)</h4>
                    ${cashExpenseList}
                   </div>`);
        }
        if (payoutLines.length > 0) {
            registerExtraParts.push(`<div class="books-cash-recon-expenses">
                    <h4 class="books-subtitle books-subtitle--sm">Register payouts (Daily sheet — lowers expected cash)</h4>
                    ${payoutList}
                   </div>`);
        }
        const registerExtra = registerExtraParts.join("");

        return `
            <div class="books-panel data-input-form">
                <label class="books-label">Day
                    <select id="di-day" class="books-select">${dayOptions()}</select>
                </label>

                <div class="books-cash-recon-summary${summary.matched ? " books-cash-recon-summary--matched" : ""}">
                    <p class="books-cash-recon-summary-title">${escapeHtml(matchLabel)}</p>
                </div>

                <p class="books-hint">Per shift: <strong>Expected</strong> = cash sale from the Daily sheet. <strong>Received + pay out</strong> should equal Expected for that shift. <strong>Cash expenses</strong> and <strong>register payouts</strong> on the Daily sheet lower expected cash for the day — they are listed below and included in <strong>Expected cash (net)</strong>. Enter <strong>Received</strong> as cash counted; use <strong>Pay out</strong> on each row for cash removed from that shift. Check <strong>Verified</strong> on each row, then enter <strong>Received / deposited</strong>.</p>

                ${
                    sections.length === 0
                        ? `<p class="data-list-empty">Nothing to reconcile for this day yet.</p>`
                        : ""
                }

                ${showField("registers")
                    ? renderReconSection(
                          "Register cash",
                          "Expected deposit = cash sales − cash expenses − register payouts (Daily sheet). Per shift: received + pay out = cash sale. Reconciliation pay outs explain cash removed from each shift — not subtracted again from the deposit.",
                          reg,
                          "cr_day_deposit",
                          "Register received / deposited ($)",
                          registerExtra
                      )
                    : ""}

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

                <button type="button" class="btn books-save" id="di-save-day">Save cash reconciliation</button>
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

        try {
            renderInner(root);
        } catch (err) {
            console.error("[Oplix] Daily books render failed:", err);
            root.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Could not load Daily books.")}</p>`;
        }
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
            body = tabVisible("payables")
                ? window.OplixPayablesUI
                    ? OplixPayablesUI.renderTab({
                          userId,
                          locationId: state.locationId,
                          monthId: state.monthId,
                          payables: state.payables,
                      })
                    : '<p class="data-list-empty">Payables unavailable.</p>'
                : '<p class="data-list-empty">Payables is turned off for this facility.</p>';
        } else if (state.tab === "cash-recon") body = renderCashReconciliation();
        else {
            body = tabVisible("receivables")
                ? renderReceivables()
                : '<p class="data-list-empty">Receivables is turned off for this facility.</p>';
        }

        const loc = currentLocation();
        const customizeHint = loc
            ? `<p class="books-hint books-customize-hint">Daily books layout for this facility can be customized in <button type="button" class="books-link-btn" id="di-open-books-config">Facilities → Customize</button>.</p>`
            : "";

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
            ${customizeHint}
            <p class="books-hint books-amount-tip">Amount fields: use <strong>+</strong> or <strong>−</strong> to add/subtract (e.g. <code>100+50-25</code>). Tab out of the field to total.</p>
            <nav class="books-tabs">
                ${tabs.map((t) => `<button type="button" class="books-tab${state.tab === t.id ? " active" : ""}" data-di-tab="${t.id}">${t.label}</button>`).join("")}
            </nav>
            ${renderExpenseDescDatalist()}
            ${body}`;

        if (state.tab === "payables" && window.OplixPayablesUI) {
            const payRoot = root.querySelector("[data-pay-section]");
            if (payRoot) {
                payRoot.dataset.payBound = "";
                OplixPayablesUI.bind(payRoot, {
                    userId,
                    locationId: state.locationId,
                    monthId: state.monthId,
                    payables: state.payables,
                    onRefresh: async () => {
                        await loadPayables();
                        render();
                    },
                });
            }
        }
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
        resetToRoot() {
            state.tab = "daily";
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
})();
