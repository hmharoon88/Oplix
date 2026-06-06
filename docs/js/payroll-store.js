/**
 * Firestore CRUD for manual payrollEntries subcollection.
 */
(function () {
    const M = () => window.OplixPayrollModel;

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(M().COLLECTION);
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) => M().normalizeEntry({ id: d.id, ...d.data() }, locationId));
    }

    async function save(userId, locationId, entry) {
        const e = M().normalizeEntry(entry, locationId);
        const id = e.id || newId();
        const payload = {
            ...e,
            pay: M().calcPay(e.hours, e.hourlyRate),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!entry.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        } else {
            payload.createdAt = entry.createdAt;
        }
        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
        return id;
    }

    async function remove(userId, locationId, entryId) {
        await colRef(userId, locationId).doc(entryId).delete();
    }

    async function listEmployees(userId, locationId) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("employees")
            .get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    async function syncToBooksMonth(userId, locationId, monthId) {
        const Books = () => window.OplixBooksStore;
        const B = () => window.OplixBooksModel;
        const allEntries = await list(userId, locationId);
        const { payrollLines, payroll } = M().buildBooksPayrollFromEntries(
            allEntries,
            monthId,
            B()
        );
        const { month, daysById } = await Books().loadMonth(userId, locationId, monthId);
        const updated = {
            ...month,
            payrollLines,
            payroll,
        };
        await Books().saveMonth(userId, locationId, monthId, updated);
        return { month: updated, daysById, payrollLines, payrollTotal: B().payrollTotalFrom(updated) };
    }

    async function syncAllBooksMonths(userId, locationId, extraMonthIds) {
        const allEntries = await list(userId, locationId);
        const months = M().affectedMonthIds(allEntries, extraMonthIds);
        const results = [];
        for (const monthId of months) {
            results.push(await syncToBooksMonth(userId, locationId, monthId));
        }
        return results;
    }

    window.OplixPayrollStore = {
        list,
        save,
        remove,
        listEmployees,
        newId,
        syncToBooksMonth,
        syncAllBooksMonths,
    };
})();
