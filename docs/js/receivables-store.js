/**
 * Firestore CRUD for location receivables subcollection.
 */
(function () {
    const M = () => window.OplixReceivablesModel;

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("receivables");
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) =>
            M().normalizeReceivable({ id: d.id, ...d.data() }, locationId)
        );
    }

    async function save(userId, locationId, receivable) {
        const r = M().normalizeReceivable(receivable, locationId);
        const isNew = !receivable.createdAt;
        const id = r.id || newId();
        const payload = {
            id,
            locationId,
            receiveFrom: r.receiveFrom,
            amount: r.amount,
            notes: r.notes || null,
            frequency: r.frequency,
            isReceived: r.isReceived,
            originalReceivableId: r.originalReceivableId,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        payload.dueDate = r.dueDate || null;

        if (r.isReceived) {
            payload.receivedAt = r.receivedAt || firebase.firestore.FieldValue.serverTimestamp();
        } else {
            payload.receivedAt = null;
        }

        if (r.createdAt) {
            payload.createdAt = r.createdAt;
        } else {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }

        if (r.createdSource) {
            payload.createdSource = r.createdSource;
        } else if (isNew) {
            payload.createdSource = "web";
        }

        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
        return id;
    }

    async function markReceived(userId, locationId, receivable) {
        return save(userId, locationId, {
            ...receivable,
            isReceived: true,
            receivedAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
    }

    /**
     * After marking received on web books: keep the payer as an open item for
     * next month with amount $0 so the new (often different) amount can be entered.
     * Skips weekly/monthly rows (iOS recurring owns those). No-op if already open.
     */
    async function ensureNextOpenForBooks(userId, locationId, receivedItem, existingList) {
        const Model = window.OplixReceivablesModel;
        if (!Model || !receivedItem) return null;
        const r = Model.normalizeReceivable(receivedItem, locationId);
        if (r.frequency === "weekly" || r.frequency === "monthly") return null;
        const current = existingList || (await list(userId, locationId));
        const asOf = Model.toDate(r.receivedAt) || new Date();
        if (Model.hasCarryForwardOpen(current, r.receiveFrom, asOf)) return null;
        const next = Model.buildNextOpenForBooks(r, locationId);
        if (!next) return null;
        const id = await save(userId, locationId, { ...next, id: newId() });
        return id;
    }

    async function remove(userId, locationId, receivableId) {
        await colRef(userId, locationId).doc(receivableId).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixReceivablesStore = {
        list,
        save,
        markReceived,
        ensureNextOpenForBooks,
        remove,
        newId,
    };
})();
