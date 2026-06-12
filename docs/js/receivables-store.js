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
        remove,
        newId,
    };
})();
