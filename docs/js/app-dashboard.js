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

    const PLACEHOLDER_SECTIONS = [];
    const PANEL_KEY = "oplix.dashboard.panel";
    const VALID_PANELS = new Set([
        "home",
        "facilities",
        "employees",
        "vendors",
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

    function showPanel(panelId) {
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
        if (panelId === "facilities" && window.OplixFacilities) {
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
        if (panelId === "employees" && window.OplixEmployeesUI) {
            OplixEmployeesUI.onShow();
        }
        activePanelId = panelId;
        savePanel(panelId);
    }

    window.showDashboardPanel = showPanel;

    async function reloadLocations() {
        if (!currentUserId) return locationsCache;
        await Promise.all([
            loadLocations(currentUserId),
            loadTasks(currentUserId),
        ]);
        if (window.OplixFacilities) {
            await OplixFacilities.refresh(currentUserId, locationsCache, tasksCache);
        }
        if (window.OplixDataInput) {
            OplixDataInput.init(currentUserId, locationsCache);
        }
        if (window.OplixAnalytics) {
            OplixAnalytics.init(currentUserId, locationsCache);
        }
        if (window.OplixReports) {
            OplixReports.init(currentUserId, locationsCache);
        }
        if (window.OplixPayrollUI) {
            OplixPayrollUI.init(currentUserId, locationsCache);
        }
        if (window.OplixTaskCheckUI) {
            OplixTaskCheckUI.setLocations(locationsCache);
        }
        if (window.OplixTasksUI?.setLocations) {
            OplixTasksUI.setLocations(locationsCache);
        }
        if (window.OplixSettingsUI) {
            OplixSettingsUI.init(currentUserId);
        }
        if (window.OplixVendorsUI) {
            OplixVendorsUI.setLocations(locationsCache);
        }
        if (window.OplixEmployeesUI) {
            OplixEmployeesUI.setLocations(locationsCache);
        }
        if (window.OplixHomeOverview && profileCache) {
            await OplixHomeOverview.loadAndRender(
                currentUserId,
                locationsCache,
                employeesCache,
                tasksCache,
                profileCache
            );
        }
        return locationsCache;
    }

    window.OplixDashboard = {
        reloadLocations,
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

            await Promise.all([
                window.OplixHomeOverview
                    ? OplixHomeOverview.loadAndRender(
                          user.uid,
                          locationsCache,
                          employeesCache,
                          tasksCache,
                          profile
                      )
                    : Promise.resolve(),
                window.OplixFacilities
                    ? OplixFacilities.refresh(user.uid, locationsCache, tasksCache)
                    : Promise.resolve(),
            ]);

            if (window.OplixDataInput) {
                OplixDataInput.init(user.uid, locationsCache);
            }
            if (window.OplixAnalytics) {
                OplixAnalytics.init(user.uid, locationsCache);
            }
            if (window.OplixReports) {
                OplixReports.init(user.uid, locationsCache);
            }
            if (window.OplixPayrollUI) {
                await runModuleInit("Payroll", () => OplixPayrollUI.init(user.uid, locationsCache));
            }
            if (window.OplixTaskCheckUI) {
                await runModuleInit("Tasks", () => OplixTaskCheckUI.init(user.uid, locationsCache));
            }
            if (window.OplixSettingsUI) {
                await runModuleInit("Settings", () => OplixSettingsUI.init(user.uid));
            }
            if (window.OplixVendorsUI) {
                await runModuleInit("Vendors", () => OplixVendorsUI.init(user.uid, locationsCache));
            }
            if (window.OplixEmployeesUI) {
                await runModuleInit("Employees", () => OplixEmployeesUI.init(user.uid, locationsCache));
            }

            showContent();
            showPanel(restorePanel());
        } catch (err) {
            showError(err.message || "Unable to load your account.");
        }
    });
})();
