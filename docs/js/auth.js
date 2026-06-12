/**
 * Web auth — Firebase project and users collection.
 * Only accounts with users/{uid}.role === "manager" and verified email.
 */
const OplixAuth = {
    async fetchUserProfile(uid) {
        const snap = await window.oplixDb.collection("users").doc(uid).get();
        if (!snap.exists) {
            throw new Error("User account not found. Please contact support.");
        }
        return snap.data();
    },

    async requireManagerUser(authUser) {
        await authUser.reload();
        const profile = await this.fetchUserProfile(authUser.uid);

        if (profile.role !== "manager") {
            await window.oplixAuth.signOut();
            throw new Error("This account is not authorized for web access.");
        }

        if (!authUser.emailVerified) {
            await window.oplixAuth.signOut();
            throw new Error(
                "Please verify your email before signing in. Check your inbox for the verification link."
            );
        }

        return profile;
    },

    async signInManager(email, password) {
        const trimmedEmail = email.trim();
        const credential = await window.oplixAuth.signInWithEmailAndPassword(
            trimmedEmail,
            password
        );
        try {
            const profile = await this.requireManagerUser(credential.user);
            return { authUser: credential.user, profile };
        } catch (err) {
            await window.oplixAuth.signOut();
            throw err;
        }
    },

    async signUpManager(email, password, username) {
        const trimmedEmail = email.trim();
        const trimmedUsername = String(username || "").trim();
        const credential = await window.oplixAuth.createUserWithEmailAndPassword(
            trimmedEmail,
            password
        );
        const uid = credential.user.uid;

        try {
            await credential.user.sendEmailVerification();
        } catch (err) {
            console.warn("[Oplix] Verification email failed:", err);
        }

        try {
            await window.oplixDb
                .collection("users")
                .doc(uid)
                .set({
                    id: uid,
                    username: trimmedUsername || trimmedEmail.split("@")[0] || "manager",
                    role: "manager",
                    locationId: null,
                    createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                });
        } catch (err) {
            try {
                await credential.user.delete();
            } catch {
                /* ignore */
            }
            throw err;
        }

        await window.oplixAuth.signOut();
        return { email: trimmedEmail };
    },

    async resendVerificationEmail(email, password) {
        const trimmedEmail = email.trim();
        const credential = await window.oplixAuth.signInWithEmailAndPassword(
            trimmedEmail,
            password
        );
        try {
            await credential.user.reload();
            if (credential.user.emailVerified) {
                throw new Error("Email is already verified. You can sign in now.");
            }
            await credential.user.sendEmailVerification();
        } finally {
            await window.oplixAuth.signOut();
        }
    },

    async getCurrentManagerSession() {
        const authUser = window.oplixAuth.currentUser;
        if (!authUser) return null;
        try {
            const profile = await this.requireManagerUser(authUser);
            return { authUser, profile };
        } catch {
            await window.oplixAuth.signOut();
            return null;
        }
    },

    async signOut() {
        await window.oplixAuth.signOut();
    },

    async sendPasswordReset(email) {
        await window.oplixAuth.sendPasswordResetEmail(email.trim());
    },

    onAuthStateChanged(callback) {
        return window.oplixAuth.onAuthStateChanged(callback);
    },

    redirectToLogin() {
        const inApp = window.location.pathname.includes("/app/");
        window.location.href = inApp ? "../login.html" : "login.html";
    },

    redirectToApp() {
        const inApp = window.location.pathname.includes("/app/");
        window.location.href = inApp ? "index.html" : "app/index.html";
    }
};

window.OplixAuth = OplixAuth;
