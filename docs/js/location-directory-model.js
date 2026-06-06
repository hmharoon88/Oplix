/**
 * Per-facility directory records (web-first; same paths for future iOS).
 *
 * Firestore (new subcollections only — does not touch books, shifts, payables, etc.):
 *   users/{uid}/locations/{locationId}/vendors/{id}
 *   users/{uid}/locations/{locationId}/utilityProviders/{id}  — doc id = utilityType key
 *   users/{uid}/locations/{locationId}/servicers/{id}
 *
 * Standard utility types match Daily books (OplixBooksModel.UTILITY_KEYS).
 */
(function () {
    const COLLECTIONS = {
        vendors: "vendors",
        utilityProviders: "utilityProviders",
        servicers: "servicers",
    };

    const SERVICE_TYPES = [
        "HVAC",
        "Pest control",
        "Alarm / security",
        "Equipment repair",
        "Cleaning",
        "Landscaping",
        "Other",
    ];

    function books() {
        return window.OplixBooksModel;
    }

    function defaultVendor() {
        return {
            name: "",
            category: "",
            contactName: "",
            phone: "",
            email: "",
            accountNumber: "",
            notes: "",
            active: true,
        };
    }

    function defaultUtilityProvider(utilityType) {
        const key = utilityType || "electric";
        const B = books();
        const std = B?.UTILITY_KEYS?.find((u) => u.key === key);
        return {
            utilityType: key,
            customLabel: std ? "" : B?.labelForUtilityKey(key, []) || "",
            providerName: "",
            accountNumber: "",
            phone: "",
            email: "",
            billingContact: "",
            notes: "",
            isDefault: !!std,
            active: true,
        };
    }

    function defaultServicer() {
        return {
            name: "",
            serviceType: "Other",
            phone: "",
            email: "",
            contractEnd: "",
            notes: "",
            active: true,
        };
    }

    function normalizeVendor(raw) {
        return { ...defaultVendor(), ...(raw || {}) };
    }

    function normalizeUtilityProvider(raw) {
        const utilityType = raw?.utilityType || raw?.id || "electric";
        return { ...defaultUtilityProvider(utilityType), ...(raw || {}), utilityType };
    }

    function normalizeServicer(raw) {
        return { ...defaultServicer(), ...(raw || {}) };
    }

    function utilityDisplayLabel(provider) {
        const p = normalizeUtilityProvider(provider);
        const B = books();
        if (!B) return p.utilityType;
        if (p.customLabel) return p.customLabel;
        return B.labelForUtilityKey(p.utilityType, [p]);
    }

    function sortUtilityProviders(list) {
        const B = books();
        const keys = B?.UTILITY_KEYS || [];
        return [...list].sort((a, b) => {
            const ak = a.utilityType || a.id;
            const bk = b.utilityType || b.id;
            const ai = keys.findIndex((u) => u.key === ak);
            const bi = keys.findIndex((u) => u.key === bk);
            if (ai >= 0 && bi >= 0) return ai - bi;
            if (ai >= 0) return -1;
            if (bi >= 0) return 1;
            return utilityDisplayLabel(a).localeCompare(utilityDisplayLabel(b));
        });
    }

    window.OplixLocationDirectoryModel = {
        COLLECTIONS,
        SERVICE_TYPES,
        defaultVendor,
        defaultUtilityProvider,
        defaultServicer,
        normalizeVendor,
        normalizeUtilityProvider,
        normalizeServicer,
        utilityDisplayLabel,
        sortUtilityProviders,
    };
})();
