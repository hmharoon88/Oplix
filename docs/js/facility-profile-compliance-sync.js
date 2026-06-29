/**
 * Sync facility profile rows marked as compliance items into complianceItems collection.
 */
(function () {
    const PM = () => window.OplixFacilityProfileModel;
    const CM = () => window.OplixComplianceModel;
    const CS = () => window.OplixComplianceStore;

    const SLOT_COMPLIANCE_MAP = {
        lease: { category: "business", recordType: "registration" },
        food_license: { category: "food_safety", recordType: "license" },
        liquor_license: { category: "alcohol", recordType: "license" },
        cigarette_license: { category: "tobacco", recordType: "license" },
        tobacco_license: { category: "tobacco", recordType: "license" },
        workers_comp: { category: "employment", recordType: "certification" },
        insurance: { category: "insurance", recordType: "insurance" },
    };

    function complianceIdForSlot(slotId) {
        return `pfcomp_${slotId}`;
    }

    function slotComplianceMeta(slotId) {
        return SLOT_COMPLIANCE_MAP[slotId] || { category: "other", recordType: "license" };
    }

    function complianceStatusFromExpiry(expiryDate) {
        if (!expiryDate) return "active";
        const days = CM().daysUntilExpiry({ expiryDate, status: "active" });
        if (days != null && days < 0) return "expired";
        return "active";
    }

    function buildCompliancePayload(slot, entry, doc) {
        const meta = slotComplianceMeta(slot.id);
        const normalized = PM().normalizeProfileEntry(entry);
        const fileType = doc?.fileType
            ? String(doc.fileType).toLowerCase()
            : doc?.fileURL
              ? "pdf"
              : "";
        return CM().normalizeItem({
            active: true,
            profileLinked: true,
            profileSlotId: slot.id,
            title: slot.label,
            recordType: meta.recordType,
            category: meta.category,
            identifier: normalized.identifier,
            issuingAuthority: normalized.issuingAuthority,
            issueDate: normalized.issueDate,
            expiryDate: normalized.expiryDate,
            notes: normalized.notes,
            status: complianceStatusFromExpiry(normalized.expiryDate),
            attachmentUrl: doc?.fileURL || "",
            attachmentFileName: doc?.name || "",
            attachmentFileType: fileType,
        });
    }

    async function sync(userId, locationId, { profileSlotConfig, facilityProfile, documents, complianceItems }) {
        if (!CS()?.save || !PM() || !CM()) return;

        const slotConfig = PM().normalizeProfileSlotConfig(profileSlotConfig);
        const entries = PM().normalizeProfileEntries(facilityProfile, slotConfig);
        const enabledSlots = PM().enabledProfileSlots(slotConfig);
        const enabledIds = new Set(enabledSlots.map((s) => s.id));
        const docs = Array.isArray(documents) ? documents : [];
        const comps = Array.isArray(complianceItems) ? complianceItems : [];

        const existing = await CS().list(userId, locationId);
        const linkedBySlot = new Map();
        existing.forEach((item) => {
            if (item.profileLinked && item.profileSlotId) {
                linkedBySlot.set(item.profileSlotId, item);
            }
        });

        for (const slot of enabledSlots) {
            const entry = entries[slot.id];
            const compId = complianceIdForSlot(slot.id);
            const linked = linkedBySlot.get(slot.id);

            if (entry?.isComplianceItem) {
                const doc = PM().profileDocumentForSlot(docs, entry, slot.id, {
                    slotLabel: slot.label,
                    complianceItems: comps,
                });
                const payload = buildCompliancePayload(slot, entry, doc);
                await CS().save(userId, locationId, linked?.id || compId, payload);
                continue;
            }

            if (linked && linked.active !== false) {
                await CS().save(userId, locationId, linked.id, {
                    active: false,
                    profileLinked: true,
                    profileSlotId: slot.id,
                });
            }
        }

        for (const item of existing) {
            if (!item.profileLinked || !item.profileSlotId) continue;
            if (!enabledIds.has(item.profileSlotId) && item.active !== false) {
                await CS().save(userId, locationId, item.id, { active: false });
            }
        }
    }

    window.OplixProfileComplianceSync = {
        complianceIdForSlot,
        sync,
    };
})();
