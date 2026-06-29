/**
 * Link facility documents & compliance attachments to profile rows.
 */
(function () {
    const PM = () => window.OplixFacilityProfileModel;
    const DocStore = () => window.OplixDocumentsStore;
    const LocStore = () => window.OplixLocationStore;

    function normalizeName(value) {
        return String(value || "")
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, " ");
    }

    function namesMatch(a, b) {
        const na = normalizeName(a);
        const nb = normalizeName(b);
        if (!na || !nb) return false;
        if (na === nb) return true;
        if (na.includes(nb) || nb.includes(na)) return true;
        return false;
    }

    function complianceAsDocument(item) {
        if (!item?.attachmentUrl) return null;
        return {
            id: `compattach_${item.id}`,
            name: item.attachmentFileName || item.title || "Compliance file",
            fileURL: item.attachmentUrl,
            fileType: item.attachmentFileType || "",
            source: "compliance",
            complianceId: item.id,
            profileSlot: item.profileSlotId || "",
        };
    }

    function resolveDocument(documents, complianceItems, entry, slotId, slotLabel) {
        const e = PM().normalizeProfileEntry(entry);
        const docs = Array.isArray(documents) ? documents : [];
        const comps = (complianceItems || []).filter((c) => c.active !== false);
        const label = slotLabel || slotId || "";

        if (e.documentId && !String(e.documentId).startsWith("compattach_")) {
            const byId = docs.find((d) => d.id === e.documentId);
            if (byId) return { ...byId, source: "documents" };
        }

        const bySlot = docs.find((d) => d.profileSlot === slotId);
        if (bySlot) return { ...bySlot, source: "documents" };

        const compBySlot = comps.find(
            (c) => c.profileSlotId === slotId && c.attachmentUrl
        );
        if (compBySlot) return complianceAsDocument(compBySlot);

        const pfCompId = window.OplixProfileComplianceSync?.complianceIdForSlot(slotId);
        if (pfCompId) {
            const linkedComp = comps.find(
                (c) => (c.id === pfCompId || c.profileSlotId === slotId) && c.attachmentUrl
            );
            if (linkedComp) return complianceAsDocument(linkedComp);
        }

        let docByName = null;
        for (const doc of docs) {
            if (doc.profileSlot && doc.profileSlot !== slotId) continue;
            if (namesMatch(doc.name, label)) {
                docByName = doc;
                break;
            }
        }
        if (docByName) return { ...docByName, source: "documents" };

        for (const comp of comps) {
            if (comp.profileSlotId && comp.profileSlotId !== slotId) continue;
            if (!comp.attachmentUrl) continue;
            if (namesMatch(comp.title, label)) {
                return complianceAsDocument(comp);
            }
        }

        return null;
    }

    function matchNameToSlot(name, profileSlotConfig) {
        if (!PM()) return null;
        const slots = PM().enabledProfileSlots(profileSlotConfig);
        for (const slot of slots) {
            if (namesMatch(name, slot.label)) return slot;
        }
        return null;
    }

    async function linkDocumentToSlot(userId, locationId, slotId, documentId) {
        if (!LocStore()?.setProfileDocumentId || !slotId || !documentId) return;
        await LocStore().setProfileDocumentId(userId, locationId, slotId, documentId);
        if (DocStore()?.update) {
            await DocStore().update(userId, locationId, documentId, {
                profileSlot: slotId,
            });
        }
    }

    async function afterFacilityDocumentUpload(userId, locationId, location, createdDoc) {
        if (!createdDoc?.id || !location) return;
        const slot = matchNameToSlot(createdDoc.name, location.profileSlotConfig);
        if (!slot) return;
        await linkDocumentToSlot(userId, locationId, slot.id, createdDoc.id);
    }

    async function afterComplianceSave(userId, locationId, location, item) {
        if (!item?.attachmentUrl || !location) return;
        let slotId = item.profileSlotId || null;
        if (!slotId && item.profileLinked && item.id?.startsWith("pfcomp_")) {
            slotId = item.id.slice("pfcomp_".length);
        }
        if (!slotId) {
            const slot = matchNameToSlot(item.title, location.profileSlotConfig);
            slotId = slot?.id || null;
        }
        if (!slotId) return;

        const docs = location._documentsCache || [];
        const existing = docs.find(
            (d) =>
                d.profileSlot === slotId ||
                d.id === location.facilityProfile?.[slotId]?.documentId
        );

        if (existing?.fileURL === item.attachmentUrl) {
            await linkDocumentToSlot(userId, locationId, slotId, existing.id);
            return;
        }

        if (DocStore()?.createFromUrl) {
            const mirrored = await DocStore().createFromUrl(userId, locationId, {
                name: item.title || "Compliance file",
                fileURL: item.attachmentUrl,
                fileType: item.attachmentFileType,
                profileSlot: slotId,
                uploadedBy: userId,
            });
            if (mirrored?.id) {
                await linkDocumentToSlot(userId, locationId, slotId, mirrored.id);
            }
        }
    }

    window.OplixProfileDocumentSync = {
        namesMatch,
        resolveDocument,
        matchNameToSlot,
        linkDocumentToSlot,
        afterFacilityDocumentUpload,
        afterComplianceSave,
    };
})();
