/**
 * Web Settings — organization, notifications, home layout, about, and account.
 */
(function () {
    const Store = () => window.OplixSettingsStore;
    const SM = () => window.OplixSettingsModel;
    const Layout = () => window.OplixHomeLayoutStore;

    let userId = null;
    let profile = null;
    let state = {
        view: "main",
        status: "",
        statusKind: "",
        orgName: "",
        savingOrg: false,
        notifForm: null,
        savingNotif: false,
        layoutPrefs: null,
        deletePassword: "",
        deleting: false,
    };

    let notifSaveTimer = null;
    let orgSaveReady = null;

    function $(id) {
        return document.getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function setStatus(msg, kind) {
        state.status = msg || "";
        state.statusKind = kind || "";
    }

    function renderStatus() {
        if (!state.status) return "";
        return `<div class="settings-status settings-status--${escapeHtml(state.statusKind || "info")}" role="status">${escapeHtml(state.status)}</div>`;
    }

    function toggleRow(label, sub, checked, name) {
        return `
            <label class="settings-toggle-row">
                <span class="settings-toggle-text">
                    <strong>${escapeHtml(label)}</strong>
                    ${sub ? `<span class="settings-toggle-sub">${escapeHtml(sub)}</span>` : ""}
                </span>
                <input type="checkbox" name="${escapeHtml(name)}"${checked ? " checked" : ""}>
            </label>`;
    }

    function renderMain() {
        return `
            ${renderStatus()}
            <div class="settings-section">
                <h2 class="settings-section-title">Organization</h2>
                <div class="books-panel settings-card">
                    <label class="books-label">Organization name
                        <input class="books-input" id="settings-org-name" value="${escapeHtml(state.orgName)}" placeholder="Your company name">
                    </label>
                    <button type="button" class="btn books-save" id="settings-save-org"${state.savingOrg ? " disabled" : ""}>Save</button>
                </div>
            </div>
            <div class="settings-section">
                <h2 class="settings-section-title">Account</h2>
                <div class="books-panel settings-card settings-kv">
                    <div><span>Username</span><strong>${escapeHtml(profile?.username || "—")}</strong></div>
                    <div><span>Role</span><strong>${escapeHtml((profile?.role || "manager").replace(/^./, (c) => c.toUpperCase()))}</strong></div>
                </div>
            </div>
            <div class="settings-section">
                <h2 class="settings-section-title">Preferences</h2>
                <div class="settings-link-list">
                    <button type="button" class="settings-link-row" data-settings-view="notifications">
                        <span>Notifications</span><span class="settings-chevron">›</span>
                    </button>
                    <button type="button" class="settings-link-row" data-settings-view="homeLayout">
                        <span>Home layout</span><span class="settings-chevron">›</span>
                    </button>
                    <button type="button" class="settings-link-row" id="settings-open-reports">
                        <span>Reports</span><span class="settings-chevron">›</span>
                    </button>
                </div>
            </div>
            <div class="settings-section">
                <h2 class="settings-section-title">Information</h2>
                <div class="settings-link-list">
                    <button type="button" class="settings-link-row" data-settings-view="about">
                        <span>About Oplix</span><span class="settings-chevron">›</span>
                    </button>
                </div>
            </div>
            <div class="settings-section">
                <h2 class="settings-section-title">Actions</h2>
                <div class="settings-link-list">
                    <button type="button" class="settings-link-row settings-link-row--danger" id="settings-sign-out">Sign out</button>
                    <button type="button" class="settings-link-row settings-link-row--danger" data-settings-view="deleteAccount">Delete account</button>
                </div>
            </div>`;
    }

    function renderNotifications() {
        const f = state.notifForm || SM().notificationFormFromProfile(profile);
        return `
            <button type="button" class="settings-back" data-settings-view="main">← Settings</button>
            ${renderStatus()}
            <h2 class="settings-page-title">Notifications</h2>
            <p class="books-hint">Saved to your account and used by email/push services.</p>
            <div class="settings-section">
                <h3 class="settings-section-title">How</h3>
                <div class="books-panel settings-card settings-toggles">
                    ${toggleRow("Push notifications", "Master switch for push alerts", f.push, "notif_push")}
                    ${toggleRow("Email notifications", "Master switch for email alerts", f.email, "notif_email")}
                </div>
            </div>
            <div class="settings-section">
                <h3 class="settings-section-title">What</h3>
                <div class="books-panel settings-card settings-toggles">
                    ${toggleRow("Task updates", null, f.tasks, "notif_tasks")}
                    ${toggleRow("Schedule changes", null, f.schedule, "notif_schedule")}
                    ${toggleRow("Location & role changes", null, f.assignment, "notif_assignment")}
                    ${toggleRow("Shift end summary (email)", null, f.shiftSummary, "notif_shiftSummary")}
                    ${toggleRow("Cash variance alert", null, f.cashAlert, "notif_cashAlert")}
                    ${toggleRow("Daily digest (email)", "Off by default — opt in", f.dailyDigest, "notif_dailyDigest")}
                </div>
            </div>
            <div class="settings-section">
                <h3 class="settings-section-title">Quiet hours</h3>
                <div class="books-panel settings-card settings-toggles">
                    ${toggleRow("Pause push during quiet hours", "Email is unaffected", f.quietHoursEnabled, "notif_quietEnabled")}
                    <label class="books-label">Start
                        <input type="time" class="books-input" name="notif_quietStart" value="${escapeHtml(f.quietStart)}">
                    </label>
                    <label class="books-label">End
                        <input type="time" class="books-input" name="notif_quietEnd" value="${escapeHtml(f.quietEnd)}">
                    </label>
                </div>
            </div>
            ${state.savingNotif ? `<p class="books-hint">Saving…</p>` : ""}`;
    }

    function renderHomeLayout() {
        const prefs = state.layoutPrefs || Layout().load(userId);
        const sections = prefs.order.filter((id) => Layout().SECTIONS[id]);
        return `
            <button type="button" class="settings-back" data-settings-view="main">← Settings</button>
            ${renderStatus()}
            <h2 class="settings-page-title">Home layout</h2>
            <p class="books-hint">Show, hide, and reorder Home sections. Saved per browser.</p>
            <div class="settings-section">
                <div class="settings-link-list" style="margin-bottom:12px">
                    <button type="button" class="settings-link-row" data-settings-view="homeLayoutAlerts">
                        <span>Needs Attention categories</span><span class="settings-chevron">›</span>
                    </button>
                </div>
                <div class="books-panel settings-card">
                    ${sections
                        .map((id) => {
                            const sec = Layout().SECTIONS[id];
                            const visible = !(prefs.hidden || []).includes(id);
                            return `
                        <div class="settings-layout-row" data-layout-section="${id}">
                            <label class="settings-layout-toggle">
                                <input type="checkbox" data-layout-visible="${id}"${visible ? " checked" : ""}>
                                <span>
                                    <strong>${escapeHtml(sec.title)}</strong>
                                    <span class="settings-toggle-sub">${escapeHtml(sec.subtitle)}</span>
                                </span>
                            </label>
                            <div class="settings-layout-move">
                                <button type="button" class="btn btn-nav-outline settings-move-btn" data-layout-up="${id}" title="Move up">↑</button>
                                <button type="button" class="btn btn-nav-outline settings-move-btn" data-layout-down="${id}" title="Move down">↓</button>
                            </div>
                        </div>`;
                        })
                        .join("")}
                </div>
                <button type="button" class="btn btn-nav-outline" id="settings-layout-reset">Reset to default</button>
            </div>`;
    }

    function renderHomeLayoutAlerts() {
        const prefs = state.layoutPrefs || Layout().load(userId);
        const hidden = new Set(prefs.hiddenAlertCategories || []);
        const cats = Object.values(Layout().ALERT_CATEGORIES);
        return `
            <button type="button" class="settings-back" data-settings-view="homeLayout">← Home layout</button>
            ${renderStatus()}
            <h2 class="settings-page-title">Needs Attention</h2>
            <p class="books-hint">Choose which alert types appear on Home.</p>
            <div class="books-panel settings-card settings-toggles">
                ${cats
                    .map((c) =>
                        toggleRow(
                            c.title,
                            c.subtitle,
                            !hidden.has(c.id),
                            `alert_cat_${c.id}`
                        )
                    )
                    .join("")}
            </div>
            <button type="button" class="btn btn-nav-outline" id="settings-alerts-reset">Show all categories</button>`;
    }

    function renderAbout() {
        return `
            <button type="button" class="settings-back" data-settings-view="main">← Settings</button>
            <h2 class="settings-page-title">About Oplix</h2>
            <div class="books-panel settings-card">
                <p class="settings-about-lead">Oplix is a cloud-based workforce management platform for managers and employees.</p>
                <p class="books-hint">Web dashboard version · Firebase project oplix-3183d</p>
                <h3 class="books-subtitle">Features</h3>
                <ul class="settings-about-list">
                    <li>Facility & employee management</li>
                    <li>Tasks with photo verification</li>
                    <li>Shift tracking & payroll</li>
                    <li>Daily books & reporting</li>
                    <li>Lottery forms & compliance</li>
                </ul>
            </div>`;
    }

    function renderDeleteAccount() {
        return `
            <button type="button" class="settings-back" data-settings-view="main">← Settings</button>
            ${renderStatus()}
            <h2 class="settings-page-title">Delete account</h2>
            <div class="books-panel settings-card settings-danger-box">
                <p><strong>Warning:</strong> This permanently removes your account, facilities, employees, tasks, and all associated data. This cannot be undone.</p>
                <label class="books-label">Confirm password
                    <input type="password" class="books-input" id="settings-delete-password" autocomplete="current-password" placeholder="Your password">
                </label>
                <button type="button" class="btn settings-delete-btn" id="settings-delete-confirm"${state.deleting ? " disabled" : ""}>Delete my account</button>
            </div>`;
    }

    function renderPanel() {
        const root = $("settings-root");
        if (!root) return;
        let body = "";
        if (state.view === "notifications") body = renderNotifications();
        else if (state.view === "homeLayout") body = renderHomeLayout();
        else if (state.view === "homeLayoutAlerts") body = renderHomeLayoutAlerts();
        else if (state.view === "about") body = renderAbout();
        else if (state.view === "deleteAccount") body = renderDeleteAccount();
        else body = renderMain();
        root.innerHTML = `<div class="settings-panel" data-settings-panel>${body}</div>`;
        attachOrgSaveReady();
    }

    function attachOrgSaveReady() {
        orgSaveReady?.detach();
        orgSaveReady = null;
        if (state.view !== "main" || !window.OplixFormSaveReady) return;
        const input = $("settings-org-name");
        const card = input?.closest(".books-panel");
        if (!card) return;
        orgSaveReady = OplixFormSaveReady.watch(card, {
            saveButton: "#settings-save-org",
            isReady: () => {
                const value = (input.value || "").trim();
                return value.length > 0 && value !== String(state.orgName || "").trim();
            },
        });
    }

    function readNotifForm(root) {
        const panel = root.querySelector("[data-settings-panel]");
        if (!panel) return state.notifForm;
        const q = (name) => panel.querySelector(`[name="${name}"]`);
        return {
            push: !!q("notif_push")?.checked,
            email: !!q("notif_email")?.checked,
            tasks: !!q("notif_tasks")?.checked,
            schedule: !!q("notif_schedule")?.checked,
            assignment: !!q("notif_assignment")?.checked,
            shiftSummary: !!q("notif_shiftSummary")?.checked,
            cashAlert: !!q("notif_cashAlert")?.checked,
            dailyDigest: !!q("notif_dailyDigest")?.checked,
            quietHoursEnabled: !!q("notif_quietEnabled")?.checked,
            quietStart: q("notif_quietStart")?.value || "22:00",
            quietEnd: q("notif_quietEnd")?.value || "07:00",
        };
    }

    function scheduleNotifSave(root) {
        clearTimeout(notifSaveTimer);
        notifSaveTimer = setTimeout(() => saveNotifications(root), 400);
    }

    async function saveNotifications(root) {
        if (!userId) return;
        const form = readNotifForm(root);
        state.notifForm = form;
        state.savingNotif = true;
        renderPanel();
        try {
            const prefs = Store().buildNotificationPrefs(form);
            await Store().updateNotificationPrefs(userId, prefs);
            profile = { ...profile, notificationPrefs: prefs };
            setStatus("Notification preferences saved.", "success");
        } catch (err) {
            setStatus(err.message || "Failed to save notifications.", "error");
        } finally {
            state.savingNotif = false;
            renderPanel();
        }
    }

    async function saveOrg() {
        const input = $("settings-org-name");
        const name = input?.value || "";
        state.savingOrg = true;
        setStatus("Saving…", "info");
        renderPanel();
        try {
            await Store().updateOrganizationName(userId, name);
            state.orgName = name.trim();
            profile = { ...profile, organizationName: state.orgName || null };
            setStatus("Organization name saved.", "success");
            if (window.OplixHomeOverview && window.OplixDashboard?.reloadLocations) {
                await OplixDashboard.reloadLocations();
            }
        } catch (err) {
            setStatus(err.message || "Failed to save.", "error");
        } finally {
            state.savingOrg = false;
            renderPanel();
        }
    }

    async function confirmDelete() {
        const password = $("settings-delete-password")?.value || "";
        if (!password) {
            setStatus("Enter your password to confirm.", "error");
            renderPanel();
            return;
        }
        if (!window.confirm("Delete your account permanently?")) return;
        state.deleting = true;
        setStatus("Deleting account…", "info");
        renderPanel();
        try {
            await Store().deleteAccount(userId, password);
            OplixAuth.redirectToLogin();
        } catch (err) {
            state.deleting = false;
            setStatus(err.message || "Failed to delete account.", "error");
            renderPanel();
        }
    }

    function bind() {
        const root = $("settings-root");
        if (!root || root.dataset.settingsBound) return;
        root.dataset.settingsBound = "1";

        root.addEventListener("click", async (e) => {
            const viewBtn = e.target.closest("[data-settings-view]");
            if (viewBtn) {
                state.view = viewBtn.dataset.settingsView;
                setStatus("", "");
                if (state.view === "homeLayout" || state.view === "homeLayoutAlerts") {
                    state.layoutPrefs = Layout().load(userId);
                }
                renderPanel();
                return;
            }
            if (e.target.id === "settings-save-org") {
                await saveOrg();
                return;
            }
            if (e.target.id === "settings-open-reports") {
                if (window.showDashboardPanel) showDashboardPanel("reports");
                return;
            }
            if (e.target.id === "settings-sign-out") {
                await OplixAuth.signOut();
                OplixAuth.redirectToLogin();
                return;
            }
            if (e.target.id === "settings-layout-reset") {
                state.layoutPrefs = Layout().reset(userId);
                setStatus("Home layout reset.", "success");
                renderPanel();
                return;
            }
            if (e.target.id === "settings-alerts-reset") {
                state.layoutPrefs = Layout().resetAlertCategories(userId);
                setStatus("All alert categories shown.", "success");
                renderPanel();
                return;
            }
            if (e.target.id === "settings-delete-confirm") {
                await confirmDelete();
                return;
            }
            const up = e.target.closest("[data-layout-up]");
            if (up) {
                state.layoutPrefs = Layout().moveSection(userId, up.dataset.layoutUp, "up");
                renderPanel();
                return;
            }
            const down = e.target.closest("[data-layout-down]");
            if (down) {
                state.layoutPrefs = Layout().moveSection(userId, down.dataset.layoutDown, "down");
                renderPanel();
                return;
            }
        });

        root.addEventListener("change", (e) => {
            const vis = e.target.closest("[data-layout-visible]");
            if (vis) {
                state.layoutPrefs = Layout().toggleSection(userId, vis.dataset.layoutVisible);
                renderPanel();
                return;
            }
            const alertCat = e.target.name?.match(/^alert_cat_(.+)$/);
            if (alertCat) {
                state.layoutPrefs = Layout().toggleAlertCategory(userId, alertCat[1]);
                renderPanel();
                return;
            }
            if (e.target.name?.startsWith("notif_")) {
                scheduleNotifSave(root);
            }
        });
    }

    async function loadProfile() {
        profile = await Store().fetchProfile(userId);
        state.orgName = profile.organizationName || "";
        state.notifForm = SM().notificationFormFromProfile(profile);
        state.layoutPrefs = Layout().load(userId);
    }

    async function init(uid) {
        userId = uid;
        const root = $("settings-root");
        if (root) {
            root.dataset.settingsBound = "";
            bind();
        }
        try {
            await loadProfile();
            setStatus("", "");
        } catch (err) {
            setStatus(err.message || "Failed to load settings.", "error");
        }
        renderPanel();
    }

    async function onShow() {
        if (!userId) return;
        try {
            await loadProfile();
        } catch {
            /* keep last profile */
        }
        renderPanel();
    }

    function resetToRoot() {
        orgSaveReady?.detach();
        orgSaveReady = null;
        if (notifSaveTimer) {
            clearTimeout(notifSaveTimer);
            notifSaveTimer = null;
        }
        state.view = "main";
        state.status = "";
        renderPanel();
    }

    window.OplixSettingsUI = { init, onShow, resetToRoot };
})();
