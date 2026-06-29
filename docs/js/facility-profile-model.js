/**
 * Facility profile — built-in + custom slots (lease, licenses, etc.).
 * `profileSlotConfig` on the location defines visible items; `facilityProfile` holds entry data by slot id.
 */
(function () {
    const BUILTIN_PROFILE_SLOTS = [
        { id: "lease", label: "Lease" },
        { id: "food_license", label: "Food license" },
        { id: "liquor_license", label: "Liquor license" },
        { id: "cigarette_license", label: "Retail cigarette license" },
        { id: "tobacco_license", label: "Tobacco license" },
        { id: "workers_comp", label: "Bureau of Workers Compensation" },
        { id: "insurance", label: "Insurance" },
    ];

    const BUILTIN_BY_ID = Object.fromEntries(BUILTIN_PROFILE_SLOTS.map((s) => [s.id, s]));

    function newCustomSlotId() {
        return `pf_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
    }

    function defaultProfileEntry() {
        return {
            expiryDate: "",
            notifyOnExpiry: true,
            isComplianceItem: false,
            documentId: "",
            identifier: "",
            issuingAuthority: "",
            issueDate: "",
            notes: "",
        };
    }

    function defaultProfileSlotConfig() {
        return {
            version: 1,
            slots: BUILTIN_PROFILE_SLOTS.map((s) => ({
                id: s.id,
                label: s.label,
                builtin: true,
                enabled: true,
            })),
        };
    }

    function normalizeProfileSlotConfig(raw) {
        if (!raw || !Array.isArray(raw.slots) || !raw.slots.length) {
            return defaultProfileSlotConfig();
        }

        const result = [];
        const seen = new Set();

        raw.slots.forEach((s) => {
            if (!s?.id || seen.has(s.id)) return;
            seen.add(s.id);

            if (s.custom) {
                if (s.enabled === false) return;
                const label = String(s.label || "").trim() || "Custom item";
                result.push({ id: s.id, label, custom: true, enabled: true });
                return;
            }

            const builtin = BUILTIN_BY_ID[s.id];
            if (!builtin) return;
            result.push({
                id: s.id,
                label: builtin.label,
                builtin: true,
                enabled: s.enabled !== false,
            });
        });

        BUILTIN_PROFILE_SLOTS.forEach((b) => {
            if (!seen.has(b.id)) {
                result.push({ id: b.id, label: b.label, builtin: true, enabled: false });
            }
        });

        return { version: 1, slots: result };
    }

    function enabledProfileSlots(slotConfig) {
        return normalizeProfileSlotConfig(slotConfig).slots.filter((s) => s.enabled !== false);
    }

    function hiddenBuiltinSlots(slotConfig) {
        return normalizeProfileSlotConfig(slotConfig).slots.filter(
            (s) => s.builtin && s.enabled === false
        );
    }

    function normalizeProfileEntry(raw) {
        const row = raw || {};
        return {
            expiryDate: String(row.expiryDate ?? "").trim(),
            notifyOnExpiry: row.notifyOnExpiry !== false,
            isComplianceItem: row.isComplianceItem === true,
            documentId: String(row.documentId ?? "").trim(),
            identifier: String(row.identifier ?? "").trim(),
            issuingAuthority: String(row.issuingAuthority ?? "").trim(),
            issueDate: String(row.issueDate ?? "").trim(),
            notes: String(row.notes ?? "").trim(),
        };
    }

    function normalizeProfileEntries(raw, slotConfig) {
        const saved = raw && typeof raw === "object" ? raw : {};
        const config = normalizeProfileSlotConfig(slotConfig);
        const entries = {};

        config.slots.forEach((slot) => {
            entries[slot.id] = normalizeProfileEntry(saved[slot.id]);
        });

        Object.keys(saved).forEach((key) => {
            if (key.startsWith("pf_") && !entries[key]) {
                entries[key] = normalizeProfileEntry(saved[key]);
            }
        });

        return entries;
    }

    /** @deprecated use normalizeProfileEntries — kept for callers passing entries only */
    function normalizeFacilityProfile(raw, slotConfig) {
        return normalizeProfileEntries(raw, slotConfig);
    }

    function defaultFacilityProfile() {
        const profile = {};
        BUILTIN_PROFILE_SLOTS.forEach((slot) => {
            profile[slot.id] = defaultProfileEntry();
        });
        return profile;
    }

    function profileEntryHasData(entry) {
        const e = normalizeProfileEntry(entry);
        return !!(
            e.documentId ||
            e.identifier ||
            e.issuingAuthority ||
            e.issueDate ||
            e.expiryDate ||
            e.notes
        );
    }

    function profileDocumentForSlot(documents, entry, slotId, options) {
        if (window.OplixProfileDocumentSync?.resolveDocument) {
            return OplixProfileDocumentSync.resolveDocument(
                documents,
                options?.complianceItems,
                entry,
                slotId,
                options?.slotLabel
            );
        }
        const e = normalizeProfileEntry(entry);
        const list = Array.isArray(documents) ? documents : [];
        if (e.documentId) {
            const byId = list.find((d) => d.id === e.documentId);
            if (byId) return byId;
        }
        return list.find((d) => d.profileSlot === slotId) || null;
    }

    function parseISODate(iso) {
        if (!iso) return null;
        const d = new Date(`${iso}T12:00:00`);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function profileExpiryStatus(entry, leadDaysOverride) {
        const e = normalizeProfileEntry(entry);
        if (!e.expiryDate) return null;
        const exp = parseISODate(e.expiryDate);
        if (!exp) return null;
        const leadDays =
            Number.isFinite(leadDaysOverride) && leadDaysOverride >= 0 ? leadDaysOverride : 60;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const diff = Math.ceil((exp - today) / (1000 * 60 * 60 * 24));
        if (diff < 0) return { tone: "expired", label: "Expired" };
        if (diff <= leadDays) {
            return {
                tone: "expiring",
                label: diff === 0 ? "Expires today" : `Expires in ${diff}d`,
            };
        }
        return { tone: "ok", label: "Active" };
    }

    function profileSummary(profileEntries, options) {
        const leadDays =
            Number.isFinite(options?.leadDays) && options.leadDays >= 0 ? options.leadDays : 60;
        const slots = options?.slotConfig
            ? enabledProfileSlots(options.slotConfig)
            : enabledProfileSlots(null);
        let filled = 0;
        let expiring = 0;
        let expired = 0;
        slots.forEach((slot) => {
            const entry = normalizeProfileEntry(profileEntries?.[slot.id]);
            if (!profileEntryHasData(entry)) return;
            filled += 1;
            if (!entry.notifyOnExpiry) return;
            const st = profileExpiryStatus(entry, leadDays);
            if (st?.tone === "expiring") expiring += 1;
            if (st?.tone === "expired") expired += 1;
        });
        return { filled, expiring, expired, total: slots.length };
    }

    window.OplixFacilityProfileModel = {
        BUILTIN_PROFILE_SLOTS,
        PROFILE_SLOTS: BUILTIN_PROFILE_SLOTS,
        newCustomSlotId,
        defaultProfileEntry,
        defaultProfileSlotConfig,
        normalizeProfileSlotConfig,
        enabledProfileSlots,
        hiddenBuiltinSlots,
        normalizeProfileEntry,
        normalizeProfileEntries,
        normalizeFacilityProfile,
        defaultFacilityProfile,
        profileEntryHasData,
        profileDocumentForSlot,
        profileExpiryStatus,
        profileSummary,
    };
})();
