(function () {
    const loadingEl = document.getElementById("app-loading");
    const contentEl = document.getElementById("app-content");
    const employeesList = document.getElementById("employees-list");
    const signOutBtn = document.getElementById("sign-out");
    const sidebarNav = document.getElementById("sidebar-nav");

    let currentUserId = null;
    let locationsCache = [];
    let employeesCache = [];
    let tasksCache = [];
    let profileCache = null;

    const PLACEHOLDER_SECTIONS = ["vendors", "payroll", "tasks", "reports"];

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

    function showPanel(panelId) {
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

        if (snap.empty) {
            employeesList.innerHTML = '<li class="data-list-empty">No employees yet.</li>';
            return;
        }

        employeesList.innerHTML = employeesCache
            .map((doc) => {
                const data = doc;
                const name = data.name || data.username || "Unnamed";
                const username = data.username ? `@${data.username}` : "";
                const rate =
                    data.hourlyRate != null ? `$${Number(data.hourlyRate).toFixed(2)}/hr` : "";
                return `
                <li class="data-list-item">
                    <h3>${escapeHtml(name)}</h3>
                    <p class="data-list-meta">${escapeHtml(username)} ${rate ? " · " + escapeHtml(rate) : ""}</p>
                </li>`;
            })
            .join("");
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

            showContent();
        } catch (err) {
            showError(err.message || "Unable to load your account.");
        }
    });
})();
