(function () {
    const loadingEl = document.getElementById("app-loading");
    const contentEl = document.getElementById("app-content");
    const signOutBtn = document.getElementById("sign-out");
    const sidebarNav = document.getElementById("sidebar-nav");

    let currentUserId = null;
    let locationsCache = [];
    let employeesCache = [];
    let tasksCache = [];
    let profileCache = null;
    let activePanelId = null;
    const initializedPanels = new Set();

    const PLACEHOLDER_SECTIONS = [];
    const PANEL_KEY = "oplix.dashboard.panel";
    const VALID_PANELS = new Set([
        "home",
        "facilities",
        "employees",
        "vendors",
        "compliance",
        "payroll",
        "tasks",
        "data-input",
        "analytics",
        "reports",
        "settings",
    ]);

    function panelFromHash() {
        const id = (location.hash || "").replace(/^#/, "").trim();
        return VALID_PANELS.has(id) ? id : null;
    }

    function savePanel(panelId) {
        if (!VALID_PANELS.has(panelId)) return;
        try {
            sessionStorage.setItem(PANEL_KEY, panelId);
        } catch {
            /* ignore */
        }
        const hash = `#${panelId}`;
        if (location.hash !== hash) {
            history.replaceState(null, "", hash);
        }
    }

    function restorePanel() {
        const fromHash = panelFromHash();
        if (fromHash) return fromHash;
        try {
            const saved = sessionStorage.getItem(PANEL_KEY);
            if (saved && VALID_PANELS.has(saved)) return saved;
        } catch {
            /* ignore */
        }
        return "home";
    }

    function showContent() {
        loadingEl.hidden = true;
        contentEl.hidden = false;
    }

    function showError(message) {
        loadingEl.innerHTML = `<p class="app-error">${escapeHtml(message)}</p><p><a href="../login.html">Back to log in</a></p>`;
    }

    function escapeHtml(text) {
        const div = document.createElement("div");
        div.textContent = text == null ? "" : String(text);
        return div.innerHTML;
    }

    function resetPanelToRoot(panelId) {
        switch (panelId) {
            case "home":
                window.OplixHomeOverview?.resetToRoot?.();
                break;
            case "facilities":
                window.OplixFacilities?.resetToRoot?.();
                break;
            case "employees":
                window.OplixEmployeesUI?.resetToRoot?.();
                break;
            case "vendors":
                window.OplixVendorsUI?.resetToRoot?.();
                break;
            case "compliance":
                window.OplixComplianceHubUI?.resetToRoot?.();
                break;
            case "payroll":
                window.OplixPayrollUI?.resetToRoot?.();
                break;
            case "tasks":
                window.OplixTaskCheckUI?.resetToRoot?.();
                break;
            case "data-input":
                window.OplixDataInput?.resetToRoot?.();
                break;
            case "analytics":
                window.OplixAnalytics?.resetToRoot?.();
                break;
            case "reports":
                window.OplixReports?.resetToRoot?.();
                break;
            case "settings":
                window.OplixSettingsUI?.resetToRoot?.();
                break;
            default:
                break;
        }
        const panel = document.getElementById(`panel-${panelId}`);
        if (panel) panel.scrollTop = 0;
    }

    async function ensurePanelInitialized(panelId) {
        if (!currentUserId || initializedPanels.has(panelId)) return;
        const uid = currentUserId;
        const locs = locationsCache;

        switch (panelId) {
            case "data-input":
                if (window.OplixDataInput) OplixDataInput.init(uid, locs);
                break;
            case "analytics":
                if (window.OplixAnalytics) OplixAnalytics.init(uid, locs);
                break;
            case "reports":
                if (window.OplixReports) OplixReports.init(uid, locs);
                break;
            case "payroll":
                await runModuleInit("Payroll", () => OplixPayrollUI.init(uid, locs));
                break;
            case "tasks":
                await runModuleInit("Tasks", () => OplixTaskCheckUI.init(uid, locs));
                break;
            case "settings":
                await runModuleInit("Settings", () => OplixSettingsUI.init(uid));
                break;
            case "vendors":
                await runModuleInit("Vendors", () => OplixVendorsUI.init(uid, locs));
                break;
            case "compliance":
                await runModuleInit("Compliance", () => OplixComplianceHubUI.init(uid, locs));
                break;
            case "employees":
                await runModuleInit("Employees", () => OplixEmployeesUI.init(uid, locs));
                break;
            default:
                break;
        }
        initializedPanels.add(panelId);
    }

    async function panelOnShow(panelId) {
        if (panelId === "facilities" && window.OplixFacilities?.onShow) {
            await OplixFacilities.onShow();
        } else if (panelId === "facilities" && window.OplixFacilities) {
            OplixFacilities.ensureLoaded();
        }
        if (panelId === "data-input" && window.OplixDataInput) {
            OplixDataInput.onShow();
        }
        if (panelId === "analytics" && window.OplixAnalytics) {
            OplixAnalytics.onShow();
        }
        if (panelId === "reports" && window.OplixReports) {
            OplixReports.onShow();
        }
        if (panelId === "payroll" && window.OplixPayrollUI) {
            OplixPayrollUI.onShow();
        }
        if (panelId === "tasks" && window.OplixTaskCheckUI) {
            OplixTaskCheckUI.onShow();
        }
        if (panelId === "settings" && window.OplixSettingsUI) {
            OplixSettingsUI.onShow();
        }
        if (panelId === "vendors" && window.OplixVendorsUI) {
            OplixVendorsUI.onShow();
        }
        if (panelId === "compliance" && window.OplixComplianceHubUI) {
            OplixComplianceHubUI.onShow();
        }
        if (panelId === "employees" && window.OplixEmployeesUI) {
            OplixEmployeesUI.onShow();
        }
    }

    async function showPanel(panelId) {
        const reselect = activePanelId === panelId;
        if (reselect) {
            resetPanelToRoot(panelId);
        }

        document.querySelectorAll(".dashboard-panel").forEach((panel) => {
            const active = panel.dataset.panel === panelId;
            panel.hidden = !active;
            panel.classList.toggle("active", active);
        });
        document.querySelectorAll(".sidebar-btn").forEach((btn) => {
            btn.classList.toggle("active", btn.dataset.panel === panelId);
        });

        await ensurePanelInitialized(panelId);
        await panelOnShow(panelId);

        activePanelId = panelId;
        savePanel(panelId);
    }

    window.showDashboardPanel = showPanel;

    function refreshInitializedModules() {
        if (!currentUserId) return;
        const uid = currentUserId;
        const locs = locationsCache;
        if (initializedPanels.has("data-input") && window.OplixDataInput) {
            OplixDataInput.init(uid, locs);
        }
        if (initializedPanels.has("analytics") && window.OplixAnalytics) {
            OplixAnalytics.init(uid, locs);
        }
        if (initializedPanels.has("reports") && window.OplixReports) {
            OplixReports.init(uid, locs);
        }
        if (initializedPanels.has("payroll") && window.OplixPayrollUI) {
            OplixPayrollUI.init(uid, locs);
        }
        if (initializedPanels.has("tasks") && window.OplixTaskCheckUI) {
            OplixTaskCheckUI.setLocations(locs);
        }
        if (initializedPanels.has("tasks") && window.OplixTasksUI?.setLocations) {
            OplixTasksUI.setLocations(locs);
        }
        if (initializedPanels.has("settings") && window.OplixSettingsUI) {
            OplixSettingsUI.init(uid);
        }
        if (initializedPanels.has("vendors") && window.OplixVendorsUI) {
            OplixVendorsUI.setLocations(locs);
        }
        if (initializedPanels.has("compliance") && window.OplixComplianceHubUI) {
            OplixComplianceHubUI.setLocations(locs);
        }
        if (initializedPanels.has("employees") && window.OplixEmployeesUI) {
            OplixEmployeesUI.setLocations(locs);
        }
    }

    async function reloadLocations() {
        if (!currentUserId) return locationsCache;
        await Promise.all([
            loadLocations(currentUserId),
            loadTasks(currentUserId),
        ]);
        if (window.OplixFacilities) {
            await OplixFacilities.refresh(currentUserId, locationsCache, tasksCache);
        }
        refreshInitializedModules();
        if (window.OplixHomeOverview && profileCache) {
            await OplixHomeOverview.loadAndRender(
                currentUserId,
                locationsCache,
                employeesCache,
                tasksCache,
                profileCache
            );
        }
        if (window.OplixGlobalSearch?.rebuildIndex) {
            OplixGlobalSearch.rebuildIndex();
        }
        return locationsCache;
    }

    window.OplixDashboard = {
        reloadLocations,
        getSearchContext() {
            return {
                userId: currentUserId,
                locations: locationsCache,
                employees: employeesCache,
                tasks: tasksCache,
            };
        },
    };

    function bindSidebar() {
        sidebarNav.addEventListener("click", (e) => {
            const btn = e.target.closest(".sidebar-btn");
            if (!btn) return;
            showPanel(btn.dataset.panel);
        });
    }

    async function loadLocations(userId) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .get();

        locationsCache = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    }

    async function loadEmployees(userId) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("employees")
            .get();

        employeesCache = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    }

    async function loadTasks(userId) {
        const snap = await window.oplixDb.collection("users").doc(userId).collection("tasks").get();
        tasksCache = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    }

    function initPlaceholders() {
        PLACEHOLDER_SECTIONS.forEach((id) => {
            const el = document.getElementById(`${id}-content`);
            if (el) {
                el.innerHTML = '<p class="data-list-empty">This section is coming soon on the web.</p>';
            }
        });
    }

    signOutBtn.addEventListener("click", async () => {
        await OplixAuth.signOut();
        OplixAuth.redirectToLogin();
    });

    bindSidebar();
    initPlaceholders();

    window.addEventListener("hashchange", () => {
        const panel = panelFromHash();
        if (panel && contentEl && !contentEl.hidden) {
            showPanel(panel);
        }
    });

    async function runModuleInit(label, fn) {
        if (!fn) return;
        try {
            await fn();
        } catch (err) {
            console.error(`[Oplix] ${label} failed to load:`, err);
        }
    }

    OplixAuth.onAuthStateChanged(async (user) => {
        if (!user) {
            OplixAuth.redirectToLogin();
            return;
        }

        try {
            const profile = await OplixAuth.requireManagerUser(user);
            currentUserId = user.uid;
            profileCache = profile;

            await Promise.all([
                loadLocations(user.uid),
                loadEmployees(user.uid),
                loadTasks(user.uid),
            ]);

            const initialPanel = restorePanel();
            showContent();
            await showPanel(initialPanel);

            const homeLoad = window.OplixHomeOverview
                ? OplixHomeOverview.loadAndRender(
                      user.uid,
                      locationsCache,
                      employeesCache,
                      tasksCache,
                      profile,
                      { deferHeavy: true }
                  )
                : Promise.resolve();
            const facilitiesLoad = window.OplixFacilities
                ? OplixFacilities.refresh(user.uid, locationsCache, tasksCache)
                : Promise.resolve();

            Promise.all([homeLoad, facilitiesLoad]).catch((err) => {
                console.error("[Oplix] Background dashboard load failed:", err);
            });

            if (window.OplixGlobalSearch) {
                OplixGlobalSearch.init(user.uid, () => window.OplixDashboard?.getSearchContext?.() || {});
            }
        } catch (err) {
            showError(err.message || "Unable to load your account.");
        }
    });
})();
