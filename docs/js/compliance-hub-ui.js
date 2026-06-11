/**
 * Sidebar Compliance tab — matrix dashboard: facilities across the top, records down the left.
 */
(function () {
    const M = () => window.OplixComplianceModel;
    const Store = () => window.OplixComplianceStore;

    let userId = null;
    let locations = [];
    let items = [];
    let filterStatus = "all";
    let loading = false;

    function $(id) {
        return document.getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function formatDate(iso) {
        if (!iso) return "";
        const d = M().parseISODate(iso);
        if (!d) return iso;
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function locationName(locationId) {
        return locations.find((l) => l.id === locationId)?.name || "Facility";
    }

    function statusRank(item) {
        const d = M().displayStatus(item);
        if (d.id === "expired") return 0;
        if (d.id === "pending_renewal" && M().isRenewalOverdue(item)) return 1;
        if (d.id === "expiring_soon") return 2;
        if (d.id === "pending_renewal") return 3;
        return 4;
    }

    function matchesStatusFilter(item) {
        if (filterStatus === "all") return true;
        const d = M().displayStatus(item);
        if (filterStatus === "attention") return M().needsAttention(item);
        if (filterStatus === "expired") return d.id === "expired";
        if (filterStatus === "expiring_soon") return d.id === "expiring_soon";
        if (filterStatus === "pending_renewal") return d.id === "pending_renewal";
        if (filterStatus === "active") return d.id === "active";
        return true;
    }

    function rowKey(item) {
        const title = (item.title || M().categoryLabel(item.category)).trim().toLowerCase();
        return `${item.recordType}|${item.category}|${title}`;
    }

    function buildMatrixRows(sourceItems) {
        const rows = new Map();
        sourceItems.forEach((item) => {
            const key = rowKey(item);
            if (!rows.has(key)) {
                rows.set(key, {
                    key,
                    recordType: item.recordType,
                    category: item.category,
                    title: item.title || M().categoryLabel(item.category),
                    byLoc: {},
                });
            }
            const row = rows.get(key);
            const existing = row.byLoc[item.locationId];
            if (!existing || statusRank(item) < statusRank(existing)) {
                row.byLoc[item.locationId] = item;
            }
        });

        return [...rows.values()].sort((a, b) => {
            const typeCmp = M().recordTypeLabel(a.recordType).localeCompare(
                M().recordTypeLabel(b.recordType)
            );
            if (typeCmp !== 0) return typeCmp;
            const catCmp = M().categoryLabel(a.category).localeCompare(M().categoryLabel(b.category));
            if (catCmp !== 0) return catCmp;
            return a.title.localeCompare(b.title);
        });
    }

    function visibleRows(allRows) {
        if (filterStatus === "all") return allRows;
        return allRows.filter((row) =>
            Object.values(row.byLoc).some((item) => matchesStatusFilter(item))
        );
    }

    async function loadItems() {
        if (!userId || !locations.length) {
            items = [];
            return;
        }
        items = await Store().listAll(userId, locations);
    }

    function renderGlobalSummary(list) {
        const c = M().summaryCounts(list);
        if (!c.total && !locations.length) {
            return `<p class="books-hint comp-hub-empty-hint">Add a facility first, then track licenses under each location's Compliance section.</p>`;
        }
        if (!c.total) {
            return `<p class="books-hint comp-hub-empty-hint">No licenses tracked yet — use <strong>Add records</strong> on a facility column to get started.</p>`;
        }
        return `
            <div class="comp-summary comp-hub-summary" role="status">
                <span class="comp-summary-stat"><strong>${c.total}</strong> total</span>
                ${c.active ? `<span class="comp-summary-stat comp-summary-stat--active">${c.active} active</span>` : ""}
                ${c.expiring ? `<span class="comp-summary-stat comp-summary-stat--expiring">${c.expiring} expiring soon</span>` : ""}
                ${c.pending ? `<span class="comp-summary-stat comp-summary-stat--pending">${c.pending} renewal</span>` : ""}
                ${c.expired ? `<span class="comp-summary-stat comp-summary-stat--expired">${c.expired} expired</span>` : ""}
            </div>`;
    }

    function facilityColumnStats(locId) {
        const locItems = items.filter((i) => i.locationId === locId);
        const c = M().summaryCounts(locItems);
        const attention = M().needsAttentionCount(locItems);
        return { ...c, attention };
    }

    function renderFacilityCards() {
        if (!locations.length) return "";
        return `
            <div class="comp-matrix-fac-cards" role="list">
                ${locations
                    .map((loc) => {
                        const stats = facilityColumnStats(loc.id);
                        const parts = [
                            stats.total ? `${stats.total} record${stats.total === 1 ? "" : "s"}` : "No records",
                            stats.expired ? `${stats.expired} expired` : "",
                            stats.expiring ? `${stats.expiring} expiring` : "",
                        ].filter(Boolean);
                        return `
                    <button type="button" class="comp-matrix-fac-card${stats.attention ? " comp-matrix-fac-card--warn" : ""}" data-comp-open="${escapeHtml(loc.id)}" role="listitem">
                        <span class="comp-matrix-fac-card-name">${escapeHtml(loc.name || "Facility")}</span>
                        <span class="comp-matrix-fac-card-meta">${escapeHtml(parts.join(" · "))}</span>
                        ${
                            stats.attention
                                ? `<span class="comp-matrix-fac-card-badge">${stats.attention} need attention</span>`
                                : stats.total
                                  ? `<span class="comp-matrix-fac-card-badge comp-matrix-fac-card-badge--ok">Up to date</span>`
                                  : ""
                        }
                    </button>`;
                    })
                    .join("")}
            </div>`;
    }

    function renderMatrixCell(item, locId) {
        if (!item) {
            return `
                <td class="comp-matrix-cell comp-matrix-cell--empty">
                    <span class="comp-matrix-empty">—</span>
                    <button type="button" class="comp-matrix-add" data-comp-open="${escapeHtml(locId)}" title="Add at this facility">+</button>
                </td>`;
        }

        if (filterStatus !== "all" && !matchesStatusFilter(item)) {
            return `
                <td class="comp-matrix-cell comp-matrix-cell--filtered">
                    <span class="comp-matrix-empty">—</span>
                </td>`;
        }

        const disp = M().displayStatus(item);
        const hint = M().expiryHint(item);
        const cellClass =
            disp.id === "expired"
                ? "comp-matrix-cell--expired"
                : disp.id === "expiring_soon"
                  ? "comp-matrix-cell--expiring"
                  : disp.id === "pending_renewal"
                    ? "comp-matrix-cell--pending"
                    : "";

        return `
            <td class="comp-matrix-cell ${cellClass}">
                <button type="button" class="comp-matrix-cell-btn" data-comp-open="${escapeHtml(locId)}" title="Open ${escapeHtml(locationName(locId))} compliance">
                    <span class="comp-status-pill ${disp.className}">${escapeHtml(disp.label)}</span>
                    ${
                        item.expiryDate
                            ? `<span class="comp-matrix-exp">Expires ${escapeHtml(formatDate(item.expiryDate))}</span>`
                            : ""
                    }
                    ${hint ? `<span class="comp-expiry-hint">${escapeHtml(hint)}</span>` : ""}
                    ${
                        item.lastRenewedDate
                            ? `<span class="comp-matrix-renewed">Renewed ${escapeHtml(formatDate(item.lastRenewedDate))}</span>`
                            : ""
                    }
                    ${
                        item.renewalDueDate
                            ? `<span class="comp-matrix-due">Renew by ${escapeHtml(formatDate(item.renewalDueDate))}</span>`
                            : ""
                    }
                    ${item.identifier ? `<span class="comp-matrix-id">#${escapeHtml(item.identifier)}</span>` : ""}
                </button>
            </td>`;
    }

    function renderMatrix() {
        if (!locations.length) {
            return `<p class="data-list-empty">Add a facility first to track compliance.</p>`;
        }

        const allRows = buildMatrixRows(items);
        const rows = visibleRows(allRows);

        if (!rows.length) {
            return `
                ${renderFacilityCards()}
                <p class="data-list-empty">No records match your filters.</p>`;
        }

        const colCount = locations.length;
        const colWidth = colCount ? `${Math.max(12, Math.floor(88 / colCount))}%` : "auto";

        const headerCells = locations
            .map((loc) => {
                const stats = facilityColumnStats(loc.id);
                return `
                <th class="comp-matrix-loc" style="width:${colWidth}">
                    <button type="button" class="comp-matrix-loc-btn" data-comp-open="${escapeHtml(loc.id)}">
                        <span class="comp-matrix-loc-name">${escapeHtml(loc.name || "Facility")}</span>
                        <span class="comp-matrix-loc-meta">
                            ${stats.total ? `${stats.total} record${stats.total === 1 ? "" : "s"}` : "No records"}
                            ${stats.attention ? ` · ${stats.attention} alert${stats.attention === 1 ? "" : "s"}` : ""}
                        </span>
                    </button>
                </th>`;
            })
            .join("");

        const bodyRows = rows
            .map((row) => {
                const cells = locations
                    .map((loc) => renderMatrixCell(row.byLoc[loc.id], loc.id))
                    .join("");
                return `
                <tr class="comp-matrix-row">
                    <th class="comp-matrix-row-label" scope="row">
                        <span class="comp-matrix-row-type">${escapeHtml(M().recordTypeLabel(row.recordType))}</span>
                        <strong class="comp-matrix-row-title">${escapeHtml(row.title)}</strong>
                        <span class="comp-matrix-row-cat">${escapeHtml(M().categoryLabel(row.category))}</span>
                    </th>
                    ${cells}
                </tr>`;
            })
            .join("");

        return `
            ${renderFacilityCards()}
            <div class="comp-matrix-scroll home-card">
                <table class="comp-matrix-table">
                    <thead>
                        <tr>
                            <th class="comp-matrix-corner" scope="col">
                                <span class="comp-matrix-corner-label">License / cert</span>
                            </th>
                            ${headerCells}
                        </tr>
                    </thead>
                    <tbody>${bodyRows}</tbody>
                </table>
            </div>`;
    }

    function renderPanel() {
        const root = $("compliance-root");
        if (!root) return;

        const statusOptions = [
            { id: "all", label: "All statuses" },
            { id: "attention", label: "Needs attention" },
            { id: "expired", label: "Expired" },
            { id: "expiring_soon", label: "Expiring soon (60 days)" },
            { id: "pending_renewal", label: "Pending renewal" },
            { id: "active", label: "Active" },
        ]
            .map(
                (o) =>
                    `<option value="${o.id}"${o.id === filterStatus ? " selected" : ""}>${escapeHtml(o.label)}</option>`
            )
            .join("");

        const body = loading
            ? `<p class="data-list-empty">Loading compliance records…</p>`
            : renderMatrix();

        root.innerHTML = `
            <div class="comp-hub comp-hub--matrix" data-comp-hub>
                <p class="books-hint">Matrix view — each row is a license or certification; each column is a facility. Click any cell to manage records at that location.</p>
                ${renderGlobalSummary(items)}
                <div class="comp-hub-toolbar">
                    <label class="books-label comp-hub-filter">
                        <span class="comp-hub-filter-label">Show</span>
                        <select class="books-select" id="comp-hub-filter-status">${statusOptions}</select>
                    </label>
                </div>
                ${body}
            </div>`;
    }

    async function refresh() {
        loading = true;
        renderPanel();
        await loadItems();
        loading = false;
        renderPanel();
    }

    async function setLocations(locs) {
        locations = locs || [];
        await refresh();
    }

    async function openFacilityCompliance(locationId) {
        if (!locationId) return;
        if (typeof window.showDashboardPanel === "function") {
            showDashboardPanel("facilities");
        }
        if (window.OplixFacilities?.openLocation) {
            await OplixFacilities.openLocation(locationId, { sectionId: "compliance" });
        }
    }

    function bind() {
        const root = $("compliance-root");
        if (!root || root.dataset.compHubBound) return;
        root.dataset.compHubBound = "1";

        root.addEventListener("click", async (e) => {
            const openBtn = e.target.closest("[data-comp-open]");
            if (openBtn) {
                await openFacilityCompliance(openBtn.dataset.compOpen);
            }
        });

        root.addEventListener("change", (e) => {
            if (e.target.id === "comp-hub-filter-status") {
                filterStatus = e.target.value;
                renderPanel();
            }
        });
    }

    async function init(uid, locs) {
        userId = uid;
        locations = locs || [];
        filterStatus = "all";
        const hubRoot = $("compliance-root");
        if (hubRoot) hubRoot.dataset.compHubBound = "";
        bind();
        await refresh();
    }

    async function onShow() {
        if (!userId) return;
        await refresh();
    }

    function resetToRoot() {
        filterStatus = "all";
        renderPanel();
    }

    window.OplixComplianceHubUI = { init, onShow, refresh, setLocations, resetToRoot };
})();
