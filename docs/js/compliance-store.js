/**
 * Firestore CRUD + Firebase Storage for compliance item attachments.
 */
(function () {
    const M = () => window.OplixComplianceModel;
    const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

    function storage() {
        if (!window.oplixStorage && typeof firebase !== "undefined" && firebase.storage) {
            window.oplixStorage = firebase.storage();
        }
        return window.oplixStorage;
    }

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(M().COLLECTION);
    }

    function sanitizeFileName(name) {
        return String(name || "file")
            .replace(/\s+/g, "_")
            .replace(/[^a-zA-Z0-9._-]/g, "");
    }

    function contentTypeFromName(fileName, fallback) {
        const ext = String(fileName || "")
            .split(".")
            .pop()
            .toLowerCase();
        const map = {
            pdf: "application/pdf",
            jpg: "image/jpeg",
            jpeg: "image/jpeg",
            png: "image/png",
            gif: "image/gif",
            webp: "image/webp",
            heic: "image/heic",
        };
        return map[ext] || fallback || "application/octet-stream";
    }

    async function uploadAttachment(userId, locationId, itemId, file) {
        const st = storage();
        if (!st) throw new Error("File storage is not available. Reload the page and try again.");
        if (!file) throw new Error("No file selected.");
        if (file.size > MAX_ATTACHMENT_BYTES) {
            throw new Error("File must be 10 MB or smaller.");
        }
        const sanitized = sanitizeFileName(file.name) || "attachment";
        const path = `compliance_attachments/${userId}/${locationId}/${itemId}/${Date.now()}_${sanitized}`;
        const ref = st.ref().child(path);
        const metadata = {
            contentType: file.type || contentTypeFromName(file.name),
        };
        const snap = await ref.put(file, metadata);
        return snap.ref.getDownloadURL();
    }

    async function deleteAttachment(url) {
        if (!url) return;
        const st = storage();
        if (!st) return;
        try {
            await st.refFromURL(url).delete();
        } catch (err) {
            console.warn("Compliance attachment delete:", err);
        }
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) => M().normalizeItem({ id: d.id, ...d.data() }));
    }

    /** Load compliance items for every facility (parallel reads). */
    async function listAll(userId, locations) {
        const locs = locations || [];
        if (!locs.length) return [];
        const rows = await Promise.all(
            locs.map(async (loc) => {
                const items = await list(userId, loc.id);
                return items
                    .filter((i) => i.active !== false)
                    .map((item) => ({
                        ...item,
                        locationId: loc.id,
                        locationName: loc.name || "Facility",
                    }));
            })
        );
        return rows.flat();
    }

    async function save(userId, locationId, id, data) {
        const payload = {
            ...data,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!data.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
    }

    async function remove(userId, locationId, id, item) {
        const url = item?.attachmentUrl;
        if (url) await deleteAttachment(url);
        await colRef(userId, locationId).doc(id).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixComplianceStore = {
        list,
        listAll,
        save,
        remove,
        newId,
        uploadAttachment,
        deleteAttachment,
        MAX_ATTACHMENT_BYTES,
    };
})();
