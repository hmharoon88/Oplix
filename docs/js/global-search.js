/**
 * Global dashboard search — facilities, employees, documents, payables, etc.
 */
(function () {
    const FACILITY_SECTIONS = [
        { id: "employees", title: "Employees", keywords: "staff people" },
        { id: "supervisors", title: "Supervisors", keywords: "manager lead" },
        { id: "tasks", title: "Tasks", keywords: "checklist audit" },
        { id: "shifts", title: "Shift Manager", keywords: "shift register" },
        { id: "lottery", title: "Lottery", keywords: "lotto scratch" },
        { id: "documents", title: "Documents", keywords: "document file license upload" },
        { id: "compliance", title: "Compliance", keywords: "license permit certification renewal" },
        { id: "reminders", title: "Reminders", keywords: "reminder todo" },
        { id: "payroll", title: "Payroll", keywords: "hours pay wages" },
        { id: "reports", title: "Reports", keywords: "export pdf csv" },
        { id: "sales", title: "Sales", keywords: "revenue" },
        { id: "payables", title: "Payables", keywords: "payable bill vendor owe" },
        { id: "receivables", title: "Receivables", keywords: "receivable owed collect" },
        { id: "vendors", title: "Vendors", keywords: "vendor supplier" },
        { id: "utility-providers", title: "Utilities", keywords: "utility electric gas water" },
        { id: "servicers", title: "Servicers", keywords: "service hvac pest" },
    ];

    const PANELS = [
        { id: "home", title: "Home", keywords: "overview dashboard needs attention todo" },
        { id: "facilities", title: "Facilities", keywords: "locations stores sites" },
        { id: "employees", title: "Employees", keywords: "staff people team" },
        { id: "vendors", title: "Vendors", keywords: "suppliers directory" },
        { id: "compliance", title: "Compliance", keywords: "licenses certifications renewals matrix" },
        { id: "payroll", title: "Payroll", keywords: "hours wages pay" },
        { id: "tasks", title: "Tasks", keywords: "completions checklist" },
        { id: "data-input", title: "Daily books", keywords: "books register daily entry" },
        { id: "analytics", title: "Books summary", keywords: "analytics totals monthly" },
        { id: "reports", title: "Reports", keywords: "export pdf csv" },
        { id: "settings", title: "Settings", keywords: "preferences layout notifications" },
    ];

    const TYPE_LABELS = {
        facility: "Facility",
        employee: "Employee",
        document: "Document",
        payable: "Payable",
        receivable: "Receivable",
        reminder: "Reminder",
        compliance: "Compliance",
        vendor: "Vendor",
        utility: "Utility",
        servicer: "Servicer",
        task: "Task",
        orgTodo: "Home to-do",
        section: "Section",
        page: "Page",
    };

    let userId = null;
    let getContext = () => ({ locations: [], employees: [], tasks: [] });
    let index = [];
    let indexBuilding = false;
    let selectedIndex = -1;
    let debounceTimer = null;

    const root = () => document.getElementById("global-search");
    const input = () => document.getElementById("global-search-input");
    const resultsEl = () => document.getElementById("global-search-results");

    function escapeHtml(text) {
        const div = document.createElement("div");
        div.textContent = text == null ? "" : String(text);
        return div.innerHTML;
    }

    function normalize(text) {
        return String(text || "")
            .toLowerCase()
            .replace(/[^\w\s]/g, " ")
            .replace(/\s+/g, " ")
            .trim();
    }

    function tokens(query) {
        const q = normalize(query);
        return q ? q.split(" ") : [];
    }

    function money(v) {
        return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
            parseFloat(v) || 0
        );
    }

    function locMap(locations) {
        const map = {};
        (locations || []).forEach((loc) => {
            map[loc.id] = loc;
        });
        return map;
    }

    function makeItem(item) {
        const searchText = normalize(item.searchText || `${item.title} ${item.subtitle}`);
        return { ...item, searchText };
    }

    function buildFastIndex(ctx) {
        const locations = ctx.locations || [];
        const employees = ctx.employees || [];
        const tasks = ctx.tasks || [];
        const byLoc = locMap(locations);
        const items = [];

        PANELS.forEach((panel) => {
            items.push(
                makeItem({
                    id: `page:${panel.id}`,
                    type: "page",
                    title: panel.title,
                    subtitle: "Go to page",
                    searchText: `${panel.title} ${panel.keywords} page`,
                    action: { panel: panel.id },
                })
            );
        });

        locations.forEach((loc) => {
            const name = loc.name || "Unnamed";
            items.push(
                makeItem({
                    id: `fac:${loc.id}`,
                    type: "facility",
                    title: name,
                    subtitle: loc.address ? String(loc.address).split("\n")[0] : "Facility",
                    searchText: `${name} ${loc.address || ""} facility location store`,
                    action: { panel: "facilities", locationId: loc.id },
                })
            );

            FACILITY_SECTIONS.forEach((section) => {
                items.push(
                    makeItem({
                        id: `sec:${loc.id}:${section.id}`,
                        type: "section",
                        title: section.title,
                        subtitle: name,
                        searchText: `${section.title} ${section.keywords} ${name} section`,
                        action: { panel: "facilities", locationId: loc.id, sectionId: section.id },
                    })
                );
            });
        });

        employees.forEach((emp) => {
            const title = emp.name || emp.username || "Employee";
            const locNames = (emp.assignedLocationIds || [])
                .map((id) => byLoc[id]?.name)
                .filter(Boolean)
                .join(", ");
            items.push(
                makeItem({
                    id: `emp:${emp.id}`,
                    type: "employee",
                    title,
                    subtitle: locNames || "Employee",
                    searchText: `${title} ${emp.username || ""} employee staff ${locNames}`,
                    action: { panel: "employees", employeeId: emp.id },
                })
            );
        });

        tasks.forEach((task) => {
            const locName = byLoc[task.locationId]?.name || "";
            const title = task.description || "Task";
            items.push(
                makeItem({
                    id: `task:${task.id}`,
                    type: "task",
                    title,
                    subtitle: locName ? `${locName} · Task` : "Organization task",
                    searchText: `${title} task ${locName}`,
                    action: task.locationId
                        ? { panel: "facilities", locationId: task.locationId, sectionId: "tasks" }
                        : { panel: "tasks" },
                })
            );
        });

        return items;
    }

    async function fetchSub(uid, locationId, name) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(uid)
            .collection("locations")
            .doc(locationId)
            .collection(name)
            .get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    async function buildDeepIndex(ctx) {
        const uid = userId;
        const locations = ctx.locations || [];
        const items = [];

        await Promise.all(
            locations.map(async (loc) => {
                const locName = loc.name || "Facility";
                const [
                    documents,
                    payables,
                    receivables,
                    reminders,
                    complianceItems,
                    directory,
                ] = await Promise.all([
                    fetchSub(uid, loc.id, "documents"),
                    fetchSub(uid, loc.id, "payables"),
                    fetchSub(uid, loc.id, "receivables"),
                    fetchSub(uid, loc.id, "reminders"),
                    window.OplixComplianceStore
                        ? OplixComplianceStore.list(uid, loc.id)
                        : Promise.resolve([]),
                    window.OplixLocationDirectoryStore
                        ? OplixLocationDirectoryStore.loadAll(uid, loc.id)
                        : Promise.resolve({ vendors: [], utilityProviders: [], servicers: [] }),
                ]);

                documents.forEach((doc) => {
                    items.push(
                        makeItem({
                            id: `doc:${loc.id}:${doc.id}`,
                            type: "document",
                            title: doc.name || "Document",
                            subtitle: locName,
                            searchText: `${doc.name} document file ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "documents" },
                        })
                    );
                });

                payables.forEach((p) => {
                    items.push(
                        makeItem({
                            id: `pay:${loc.id}:${p.id}`,
                            type: "payable",
                            title: `${money(p.amount)} · ${p.payTo || "Payable"}`,
                            subtitle: locName,
                            searchText: `${p.payTo} ${p.notes || ""} payable bill ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "payables" },
                        })
                    );
                });

                receivables.forEach((r) => {
                    items.push(
                        makeItem({
                            id: `rec:${loc.id}:${r.id}`,
                            type: "receivable",
                            title: `${money(r.amount)} · ${r.receiveFrom || "Receivable"}`,
                            subtitle: locName,
                            searchText: `${r.receiveFrom} ${r.notes || ""} receivable owed ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "receivables" },
                        })
                    );
                });

                reminders.forEach((r) => {
                    items.push(
                        makeItem({
                            id: `rem:${loc.id}:${r.id}`,
                            type: "reminder",
                            title: r.title || r.text || "Reminder",
                            subtitle: locName,
                            searchText: `${r.title || r.text || ""} ${r.notes || ""} reminder ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "reminders" },
                        })
                    );
                });

                (complianceItems || []).forEach((c) => {
                    items.push(
                        makeItem({
                            id: `comp:${loc.id}:${c.id}`,
                            type: "compliance",
                            title: c.title || c.category || "Compliance record",
                            subtitle: locName,
                            searchText: `${c.title} ${c.category} ${c.notes || ""} compliance license permit ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "compliance" },
                        })
                    );
                });

                (directory.vendors || []).forEach((v) => {
                    items.push(
                        makeItem({
                            id: `ven:${loc.id}:${v.id}`,
                            type: "vendor",
                            title: v.name || "Vendor",
                            subtitle: locName,
                            searchText: `${v.name} ${v.category || ""} ${v.contactName || ""} vendor supplier ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "vendors" },
                        })
                    );
                });

                (directory.utilityProviders || []).forEach((u) => {
                    items.push(
                        makeItem({
                            id: `util:${loc.id}:${u.id || u.utilityType}`,
                            type: "utility",
                            title: u.providerName || u.utilityType || "Utility",
                            subtitle: locName,
                            searchText: `${u.providerName} ${u.utilityType} utility ${locName}`,
                            action: {
                                panel: "facilities",
                                locationId: loc.id,
                                sectionId: "utility-providers",
                            },
                        })
                    );
                });

                (directory.servicers || []).forEach((s) => {
                    items.push(
                        makeItem({
                            id: `srv:${loc.id}:${s.id}`,
                            type: "servicer",
                            title: s.name || s.serviceType || "Servicer",
                            subtitle: locName,
                            searchText: `${s.name} ${s.serviceType || ""} servicer service ${locName}`,
                            action: { panel: "facilities", locationId: loc.id, sectionId: "servicers" },
                        })
                    );
                });
            })
        );

        if (window.OplixOrgTodosStore) {
            try {
                const todos = await OplixOrgTodosStore.list(uid);
                todos.forEach((todo) => {
                    items.push(
                        makeItem({
                            id: `todo:${todo.id}`,
                            type: "orgTodo",
                            title: todo.title || "To-do",
                            subtitle: "Home · Organization to-do",
                            searchText: `${todo.title} ${todo.notes || ""} todo home organization`,
                            action: { panel: "home" },
                        })
                    );
                });
            } catch {
                /* ignore */
            }
        }

        return items;
    }

    async function rebuildIndex() {
        if (!userId || indexBuilding) return;
        indexBuilding = true;
        setIndexingState(true);

        const ctx = getContext();
        const fast = buildFastIndex(ctx);
        index = fast;

        const q = input()?.value?.trim();
        if (q) renderResults(search(q));

        try {
            const deep = await buildDeepIndex(ctx);
            index = fast.concat(deep);
        } catch (err) {
            console.error("[Oplix] Search index build failed:", err);
        }

        indexBuilding = false;
        setIndexingState(false);

        const q2 = input()?.value?.trim();
        if (q2) renderResults(search(q2));
    }

    function setIndexingState(active) {
        const el = root();
        if (!el) return;
        el.classList.toggle("global-search--indexing", !!active);
    }

    function scoreItem(item, queryTokens) {
        const text = item.searchText;
        let score = 0;
        queryTokens.forEach((tok) => {
            const idx = text.indexOf(tok);
            if (idx === -1) return;
            score += 10;
            if (item.title && normalize(item.title).startsWith(tok)) score += 20;
            else if (item.title && normalize(item.title).includes(tok)) score += 12;
            if (idx === 0) score += 5;
        });
        if (item.type === "facility") score += 2;
        if (item.type === "page") score += 1;
        return score;
    }

    function search(query) {
        const queryTokens = tokens(query);
        if (!queryTokens.length) return [];

        const matched = index
            .filter((item) => queryTokens.every((tok) => item.searchText.includes(tok)))
            .map((item) => ({ item, score: scoreItem(item, queryTokens) }))
            .sort((a, b) => b.score - a.score || a.item.title.localeCompare(b.item.title))
            .slice(0, 24)
            .map((row) => row.item);

        return matched;
    }

    function closeResults() {
        const el = resultsEl();
        if (el) {
            el.hidden = true;
            el.innerHTML = "";
        }
        selectedIndex = -1;
        root()?.classList.remove("global-search--open");
    }

    function renderResults(results) {
        const el = resultsEl();
        if (!el) return;

        if (!results.length) {
            el.hidden = false;
            el.innerHTML = `<p class="global-search-empty">${indexBuilding ? "Still indexing documents and records…" : "No results."}</p>`;
            selectedIndex = -1;
            root()?.classList.add("global-search--open");
            return;
        }

        el.hidden = false;
        el.innerHTML = results
            .map((item, i) => {
                const typeLabel = TYPE_LABELS[item.type] || item.type;
                return `
                    <button type="button" class="global-search-result${i === selectedIndex ? " is-selected" : ""}" data-search-index="${i}">
                        <span class="global-search-result-type">${escapeHtml(typeLabel)}</span>
                        <span class="global-search-result-main">
                            <strong>${escapeHtml(item.title)}</strong>
                            <span>${escapeHtml(item.subtitle)}</span>
                        </span>
                    </button>`;
            })
            .join("");
        root()?.classList.add("global-search--open");
    }

    function currentResults() {
        const q = input()?.value?.trim();
        return q ? search(q) : [];
    }

    function highlightSelection() {
        const el = resultsEl();
        if (!el) return;
        el.querySelectorAll(".global-search-result").forEach((btn, i) => {
            btn.classList.toggle("is-selected", i === selectedIndex);
            if (i === selectedIndex) btn.scrollIntoView({ block: "nearest" });
        });
    }

    async function navigate(action) {
        closeResults();
        const field = input();
        if (field) field.value = "";
        field?.blur();

        if (!action) return;

        if (typeof window.showDashboardPanel === "function" && action.panel) {
            await window.showDashboardPanel(action.panel);
        }

        if (action.employeeId && window.OplixEmployeesUI?.openEdit) {
            await OplixEmployeesUI.openEdit(action.employeeId);
            return;
        }

        if (action.locationId && window.OplixFacilities?.openLocation) {
            await OplixFacilities.openLocation(action.locationId, {
                sectionId: action.sectionId || null,
            });
        }
    }

    function onInput() {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
            const q = input()?.value?.trim() || "";
            if (!q) {
                closeResults();
                return;
            }
            selectedIndex = -1;
            renderResults(search(q));
        }, 120);
    }

    function bindShell() {
        const shell = root();
        if (!shell || shell.dataset.searchBound) return;
        shell.dataset.searchBound = "1";

        const kbd = shell.querySelector(".global-search-kbd");
        if (kbd && !/Mac|iPhone|iPad/.test(navigator.platform)) {
            kbd.textContent = "Ctrl K";
        }

        const field = input();
        field?.addEventListener("input", onInput);
        field?.addEventListener("focus", () => {
            const q = field.value.trim();
            if (q) onInput();
        });
        field?.addEventListener("keydown", (e) => {
            const results = currentResults();
            if (e.key === "Escape") {
                closeResults();
                field.blur();
                return;
            }
            if (e.key === "ArrowDown") {
                e.preventDefault();
                if (!results.length) return;
                selectedIndex = Math.min(selectedIndex + 1, results.length - 1);
                highlightSelection();
                return;
            }
            if (e.key === "ArrowUp") {
                e.preventDefault();
                if (!results.length) return;
                selectedIndex = Math.max(selectedIndex - 1, 0);
                highlightSelection();
                return;
            }
            if (e.key === "Enter") {
                e.preventDefault();
                const pick = selectedIndex >= 0 ? results[selectedIndex] : results[0];
                if (pick) navigate(pick.action);
            }
        });

        resultsEl()?.addEventListener("click", (e) => {
            const btn = e.target.closest("[data-search-index]");
            if (!btn) return;
            const idx = parseInt(btn.dataset.searchIndex, 10);
            const results = currentResults();
            const pick = results[idx];
            if (pick) navigate(pick.action);
        });

        document.addEventListener("click", (e) => {
            if (!shell.contains(e.target)) closeResults();
        });

        document.addEventListener("keydown", (e) => {
            if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
                e.preventDefault();
                field?.focus();
                field?.select();
            }
        });
    }

    function init(uid, contextFn) {
        userId = uid;
        getContext = contextFn || getContext;
        bindShell();
        rebuildIndex();
    }

    window.OplixGlobalSearch = {
        init,
        rebuildIndex,
    };
})();
