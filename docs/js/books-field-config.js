/**
 * Per-facility Daily books field configuration — enable/disable built-in fields,
 * add custom fields, and assign sales vs expense categories.
 */
(function () {
    const CATEGORIES = [
        { id: "sales", label: "Sales" },
        { id: "expense", label: "Expense" },
        { id: "reconciliation", label: "Reconciliation" },
        { id: "none", label: "Track only" },
    ];

    const GROUP_LABELS = {
        daily: "Daily sheet",
        month: "Month (utilities & payroll)",
        tab: "Tabs",
        custom: "Custom fields",
    };

    /** @type {{ id: string, label: string, group: string, gasOnly?: boolean, defaultCategory: string }[]} */
    const BOOKS_FIELDS = [
        { id: "merchSale", label: "Merch sale", group: "daily", gasOnly: true, defaultCategory: "sales" },
        { id: "creditCard", label: "Network Card", group: "daily", gasOnly: true, defaultCategory: "sales" },
        { id: "fuel", label: "Fuel (gallons & $)", group: "daily", gasOnly: true, defaultCategory: "sales" },
        { id: "registers", label: "Registers", group: "daily", defaultCategory: "reconciliation" },
        { id: "waynePass", label: "Wayne Pass", group: "daily", gasOnly: true, defaultCategory: "none" },
        { id: "registerPayouts", label: "Register payouts", group: "daily", gasOnly: true, defaultCategory: "expense" },
        { id: "pulltabs", label: "Pulltab", group: "daily", defaultCategory: "none" },
        { id: "windStations", label: "Wind station", group: "daily", defaultCategory: "none" },
        { id: "kenoStations", label: "Keno station", group: "daily", defaultCategory: "none" },
        { id: "lottery", label: "Lottery", group: "daily", defaultCategory: "none" },
        { id: "cashExpenses", label: "Cash expense", group: "daily", defaultCategory: "expense" },
        { id: "checksAch", label: "Checks / ACH", group: "daily", defaultCategory: "expense" },
        { id: "otherExpenses", label: "Other expense", group: "daily", defaultCategory: "expense" },
        { id: "utilities", label: "Utilities", group: "month", defaultCategory: "expense" },
        { id: "payroll", label: "Payroll", group: "month", defaultCategory: "expense" },
        { id: "salesTax", label: "Sales tax", group: "month", defaultCategory: "expense" },
        { id: "accountant", label: "Accountant", group: "month", defaultCategory: "expense" },
        { id: "payables", label: "Payables", group: "tab", defaultCategory: "expense" },
        { id: "receivables", label: "Receivables", group: "tab", defaultCategory: "sales" },
        { id: "cashReconciliation", label: "Cash reconciliation", group: "tab", defaultCategory: "reconciliation" },
    ];

    const FIELD_BY_ID = Object.fromEntries(BOOKS_FIELDS.map((f) => [f.id, f]));

    const TAB_FIELD_BY_TAB = {
        daily: null,
        utilities: ["utilities", "payroll", "salesTax", "accountant"],
        payables: "payables",
        receivables: "receivables",
        "cash-recon": "cashReconciliation",
    };

    function newCustomFieldId() {
        return `cf_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
    }

    function normalizeCustomFieldDefs(raw) {
        if (!Array.isArray(raw)) return [];
        return raw
            .map((row, i) => {
                const r = row || {};
                const cat = String(r.category || "none").trim();
                return {
                    id: String(r.id || `cf_${i}`).trim() || newCustomFieldId(),
                    label: String(r.label || "").trim(),
                    group: r.group === "month" ? "month" : "daily",
                    category: CATEGORIES.some((c) => c.id === cat) ? cat : "none",
                    enabled: r.enabled !== false,
                    custom: true,
                };
            })
            .filter((cf) => cf.label);
    }

    function defaultEnabledForField(field, hasGasStation) {
        if (field.gasOnly && !hasGasStation) return false;
        return true;
    }

    function defaultBooksFieldConfig(hasGasStation) {
        const fields = {};
        BOOKS_FIELDS.forEach((f) => {
            fields[f.id] = {
                enabled: defaultEnabledForField(f, hasGasStation),
                category: f.defaultCategory,
            };
        });
        return { version: 2, fields, customFields: [] };
    }

    function normalizeBooksFieldConfig(raw, hasGasStation) {
        const base = defaultBooksFieldConfig(hasGasStation);
        const saved = raw?.fields && typeof raw.fields === "object" ? raw.fields : {};
        BOOKS_FIELDS.forEach((f) => {
            const row = saved[f.id];
            if (!row || typeof row !== "object") return;
            if (typeof row.enabled === "boolean") {
                base.fields[f.id].enabled = row.enabled;
            }
            const cat = String(row.category || "").trim();
            if (CATEGORIES.some((c) => c.id === cat)) {
                base.fields[f.id].category = cat;
            }
        });
        BOOKS_FIELDS.forEach((f) => {
            if (f.gasOnly && !hasGasStation) {
                base.fields[f.id].enabled = false;
            }
        });
        base.customFields = normalizeCustomFieldDefs(raw?.customFields);
        return base;
    }

    function customFieldById(config, customId) {
        return (config?.customFields || []).find((cf) => cf.id === customId) || null;
    }

    function customFieldEnabled(config, customId) {
        const cf = customFieldById(config, customId);
        return cf ? cf.enabled !== false : false;
    }

    function fieldEnabled(config, fieldId, hasGasStation) {
        const def = FIELD_BY_ID[fieldId];
        if (!def) return true;
        if (def.gasOnly && !hasGasStation) return false;
        const row = config?.fields?.[fieldId];
        if (!row) return defaultEnabledForField(def, hasGasStation);
        return row.enabled !== false;
    }

    function fieldCategory(config, fieldId, hasGasStation) {
        const def = FIELD_BY_ID[fieldId];
        if (!def) return "none";
        const row = config?.fields?.[fieldId];
        const cat = row?.category || def.defaultCategory;
        return CATEGORIES.some((c) => c.id === cat) ? cat : def.defaultCategory;
    }

    function enabledCustomFields(config, group) {
        return (config?.customFields || []).filter(
            (cf) => cf.enabled !== false && cf.group === group
        );
    }

    function tabEnabled(config, tabId, hasGasStation) {
        if (tabId === "daily") return true;
        const map = TAB_FIELD_BY_TAB[tabId];
        if (!map) return true;
        if (Array.isArray(map)) {
            const builtIn = map.some((id) => fieldEnabled(config, id, hasGasStation));
            const customMonth = enabledCustomFields(config, "month").length > 0;
            return builtIn || (tabId === "utilities" && customMonth);
        }
        return fieldEnabled(config, map, hasGasStation);
    }

    function fieldsForGroup(group, hasGasStation) {
        return BOOKS_FIELDS.filter((f) => f.group === group && (!f.gasOnly || hasGasStation));
    }

    function configFromLocation(location) {
        const hasGas = location?.facilityType === "c_store_gas";
        return normalizeBooksFieldConfig(location?.booksFieldConfig, hasGas);
    }

    function filterBreakdownLines(lines, config, hasGasStation) {
        if (!config) return lines;
        return (lines || []).filter((line) => {
            if (line.custom) {
                return customFieldEnabled(config, line.fieldId);
            }
            if (!line.fieldId) return true;
            return fieldEnabled(config, line.fieldId, hasGasStation);
        });
    }

    window.OplixBooksFieldConfig = {
        BOOKS_FIELDS,
        CATEGORIES,
        GROUP_LABELS,
        newCustomFieldId,
        defaultBooksFieldConfig,
        normalizeBooksFieldConfig,
        normalizeCustomFieldDefs,
        fieldEnabled,
        fieldCategory,
        customFieldEnabled,
        enabledCustomFields,
        tabEnabled,
        fieldsForGroup,
        configFromLocation,
        filterBreakdownLines,
    };
})();
