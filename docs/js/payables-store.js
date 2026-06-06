/**
 * Firestore CRUD for location payables subcollection.
 */
(function () {
    const M = () => window.OplixPayablesModel;

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("payables");
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) =>
            M().normalizePayable({ id: d.id, ...d.data() }, locationId)
        );
    }

    async function save(userId, locationId, payable) {
        const p = M().normalizePayable(payable, locationId);
        const id = p.id || newId();
        const payload = {
            id,
            locationId,
            payTo: p.payTo,
            amount: p.amount,
            notes: p.notes || null,
            frequency: p.frequency,
            isPaid: p.isPaid,
            originalPayableId: p.originalPayableId,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (p.dueDate) payload.dueDate = p.dueDate;
        else payload.dueDate = null;

        if (p.isPaid) {
            payload.paidAt = p.paidAt || firebase.firestore.FieldValue.serverTimestamp();
        } else {
            payload.paidAt = null;
        }

        if (p.createdAt) {
            payload.createdAt = p.createdAt;
        } else {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }

        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
        return id;
    }

    async function markPaid(userId, locationId, payable) {
        return save(userId, locationId, {
            ...payable,
            isPaid: true,
            paidAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
    }

    async function remove(userId, locationId, payableId) {
        await colRef(userId, locationId).doc(payableId).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixPayablesStore = {
        list,
        save,
        markPaid,
        remove,
        newId,
    };
})();
