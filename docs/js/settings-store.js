/**
 * Firestore user settings — organization name, notification prefs, account delete.
 */
(function () {
    const SM = () => window.OplixSettingsModel;

    function userRef(userId) {
        return window.oplixDb.collection("users").doc(userId);
    }

    async function fetchProfile(userId) {
        const snap = await userRef(userId).get();
        if (!snap.exists) throw new Error("User profile not found.");
        return { id: userId, ...snap.data() };
    }

    async function updateOrganizationName(userId, organizationName) {
        const value = String(organizationName || "").trim();
        await userRef(userId).set(
            { organizationName: value || firebase.firestore.FieldValue.delete() },
            { merge: true }
        );
    }

    async function updateNotificationPrefs(userId, prefs) {
        await userRef(userId).update({ notificationPrefs: prefs });
    }

    async function deleteAllManagerTasks(userId) {
        const snap = await userRef(userId).collection("tasks").get();
        if (snap.empty) return;
        const batch = window.oplixDb.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
    }

    async function deleteManagerEmployees(userId) {
        const snap = await userRef(userId).collection("employees").get();
        for (const doc of snap.docs) {
            try {
                await window.oplixDb.collection("users").doc(doc.id).delete();
            } catch {
                /* ignore */
            }
            await doc.ref.delete();
        }
    }

    async function deleteAccount(userId, password) {
        const authUser = window.oplixAuth.currentUser;
        if (!authUser || authUser.uid !== userId) {
            throw new Error("Not signed in.");
        }
        const email = authUser.email;
        if (!email) throw new Error("Account has no email address.");

        const cred = firebase.auth.EmailAuthProvider.credential(email, password);
        await authUser.reauthenticateWithCredential(cred);

        const locSnap = await userRef(userId).collection("locations").get();
        const LocStore = window.OplixLocationStore;
        if (LocStore?.deleteLocation) {
            for (const loc of locSnap.docs) {
                await LocStore.deleteLocation(userId, loc.id);
            }
        } else {
            for (const loc of locSnap.docs) {
                await loc.ref.delete();
            }
        }

        await deleteAllManagerTasks(userId);
        await deleteManagerEmployees(userId);
        await userRef(userId).delete();
        await authUser.delete();
    }

    window.OplixSettingsStore = {
        fetchProfile,
        updateOrganizationName,
        updateNotificationPrefs,
        deleteAccount,
        buildNotificationPrefs: (form) => SM().buildNotificationPrefs(form),
    };
})();
