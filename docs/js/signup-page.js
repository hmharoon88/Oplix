(function () {
    const form = document.getElementById("signup-form");
    const formView = document.getElementById("signup-form-view");
    const successView = document.getElementById("signup-success-view");
    const errorEl = document.getElementById("signup-error");
    const submitBtn = document.getElementById("signup-submit");
    const resendBtn = document.getElementById("signup-resend");
    const successEmailEl = document.getElementById("signup-success-email");
    const successStatusEl = document.getElementById("signup-success-status");

    let pendingEmail = "";
    let pendingPassword = "";

    function showError(message) {
        errorEl.textContent = message;
        errorEl.hidden = false;
        errorEl.classList.remove("login-message-info");
    }

    function clearError() {
        errorEl.hidden = true;
        errorEl.textContent = "";
        errorEl.classList.remove("login-message-info");
    }

    function setLoading(loading) {
        submitBtn.disabled = loading;
        submitBtn.textContent = loading ? "Creating account…" : "Create account";
    }

    function showSuccess(email) {
        pendingEmail = email;
        formView.hidden = true;
        successView.hidden = false;
        successEmailEl.textContent = email;
        successStatusEl.hidden = true;
        successStatusEl.textContent = "";
    }

    OplixAuth.onAuthStateChanged(async (user) => {
        if (!user) return;
        try {
            await OplixAuth.requireManagerUser(user);
            OplixAuth.redirectToApp();
        } catch {
            /* not a valid manager session yet */
        }
    });

    form.addEventListener("submit", async (e) => {
        e.preventDefault();
        clearError();

        const email = form.email.value.trim();
        const password = form.password.value;
        const confirmPassword = form.confirmPassword.value;

        if (!email || !password || !confirmPassword) {
            showError("Please fill in all fields.");
            return;
        }
        if (password !== confirmPassword) {
            showError("Passwords do not match.");
            return;
        }
        if (password.length < 6) {
            showError("Password must be at least 6 characters.");
            return;
        }

        setLoading(true);
        pendingPassword = password;

        try {
            const username = email.split("@")[0] || "manager";
            await OplixAuth.signUpManager(email, password, username);
            showSuccess(email);
        } catch (err) {
            const code = err.code || "";
            let message = err.message || "Sign up failed. Please try again.";

            if (code === "auth/email-already-in-use") {
                message = "An account with this email already exists. Try logging in instead.";
            } else if (code === "auth/invalid-email") {
                message = "Please enter a valid email address.";
            } else if (code === "auth/weak-password") {
                message = "Password is too weak. Use at least 6 characters.";
            }

            showError(message);
        } finally {
            setLoading(false);
        }
    });

    resendBtn.addEventListener("click", async () => {
        if (!pendingEmail || !pendingPassword) {
            successStatusEl.hidden = false;
            successStatusEl.textContent = "Enter your details again on the form to resend.";
            successStatusEl.classList.add("login-message-info");
            return;
        }

        resendBtn.disabled = true;
        resendBtn.textContent = "Sending…";
        successStatusEl.hidden = true;

        try {
            await OplixAuth.resendVerificationEmail(pendingEmail, pendingPassword);
            successStatusEl.hidden = false;
            successStatusEl.textContent = "Verification email sent again. Check your inbox.";
            successStatusEl.classList.add("login-message-info");
        } catch (err) {
            successStatusEl.hidden = false;
            successStatusEl.textContent = err.message || "Could not resend email.";
            successStatusEl.classList.remove("login-message-info");
        } finally {
            resendBtn.disabled = false;
            resendBtn.textContent = "Resend verification email";
        }
    });
})();
