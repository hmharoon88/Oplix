(function () {
    const form = document.getElementById("login-form");
    const errorEl = document.getElementById("login-error");
    const submitBtn = document.getElementById("login-submit");
    const forgotBtn = document.getElementById("forgot-password");

    function showError(message) {
        errorEl.textContent = message;
        errorEl.hidden = false;
    }

    function clearError() {
        errorEl.hidden = true;
        errorEl.textContent = "";
        errorEl.classList.remove("login-message-info");
    }

    function setLoading(loading) {
        submitBtn.disabled = loading;
        submitBtn.textContent = loading ? "Signing in…" : "Sign in";
    }

    OplixAuth.onAuthStateChanged(async (user) => {
        if (!user) return;
        try {
            await OplixAuth.requireManagerUser(user);
            OplixAuth.redirectToApp();
        } catch {
            /* not a valid manager session */
        }
    });

    form.addEventListener("submit", async (e) => {
        e.preventDefault();
        clearError();
        setLoading(true);

        const email = form.email.value;
        const password = form.password.value;

        try {
            await OplixAuth.signInManager(email, password);
            OplixAuth.redirectToApp();
        } catch (err) {
            const code = err.code || "";
            let message = err.message || "Sign in failed. Please try again.";

            if (code === "auth/user-not-found" || code === "auth/wrong-password") {
                message = "Invalid email or password.";
            } else if (code === "auth/too-many-requests") {
                message = "Too many attempts. Please wait a few minutes and try again.";
            } else if (code === "auth/invalid-email") {
                message = "Please enter a valid email address.";
            }

            showError(message);
        } finally {
            setLoading(false);
        }
    });

    forgotBtn.addEventListener("click", async (e) => {
        e.preventDefault();
        clearError();
        const email = form.email.value.trim();
        if (!email) {
            showError("Enter your email above, then tap Forgot password.");
            return;
        }
        try {
            await OplixAuth.sendPasswordReset(email);
            showError("Password reset email sent. Check your inbox.");
            errorEl.classList.add("login-message-info");
        } catch (err) {
            showError(err.message || "Could not send reset email.");
        }
    });
})();
