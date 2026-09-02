/**
 * Unified facility customize — general info, profile/licenses, daily books.
 */
(function () {
    const FC = () => window.OplixBooksFieldConfig;
    const PM = () => window.OplixFacilityProfileModel;
    const NM = () => window.OplixFacilityNotificationModel;
    const Store = () => window.OplixLocationStore;
    const BooksUI = () => window.OplixFacilityBooksConfig;
    const DocStore = () => window.OplixDocumentsStore;

    const PROFILE_DOC_ACCEPT = "image/*,.pdf,application/pdf,.doc,.docx";

    const FACILITY_TYPES = [
        { id: "c_store", label: "C Store" },
        { id: "c_store_gas", label: "C Store Gas Station" },
    ];

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function hasGasStation(location) {
        return location?.facilityType === "c_store_gas";
    }

    function effectiveFacilityType(loc) {
        return loc?.facilityType === "c_store_gas" ? "c_store_gas" : "c_store";
    }

    function renderFacilityTypeOptions(selected) {
        return FACILITY_TYPES.map(
            (t) => `<option value="${t.id}"${t.id === selected ? " selected" : ""}>${escapeHtml(t.label)}</option>`
        ).join("");
    }

    function renderProfileDocCell(slot, entry, doc) {
        const e = PM().normalizeProfileEntry(entry);
        const realDocId =
            doc?.source === "compliance" || String(doc?.id || "").startsWith("compattach_")
                ? e.documentId || ""
                : doc?.id || e.documentId || "";
        const sourceHint =
            doc?.source === "compliance"
                ? `<span class="fac-profile-doc-source">From Compliance</span>`
                : doc?.source === "documents" && doc?.profileSlot === slot.id
                  ? `<span class="fac-profile-doc-source">Linked</span>`
                  : doc?.source === "documents"
                    ? `<span class="fac-profile-doc-source">From Documents</span>`
                    : "";
        if (doc?.fileURL) {
            const label = doc.name || slot.label;
            return `
                <td class="fac-profile-doc-cell">
                    <div class="fac-profile-doc" data-profile-doc-slot="${escapeHtml(slot.id)}">
                        <a class="fac-profile-doc-link" href="${escapeHtml(doc.fileURL)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>
                        ${sourceHint}
                        <div class="fac-profile-doc-actions">
                            <label class="fac-profile-doc-upload fac-profile-doc-replace">
                                <span class="books-link-btn">Replace</span>
                                <input type="file" class="fac-profile-doc-file" data-profile-doc-upload="${escapeHtml(slot.id)}" accept="${PROFILE_DOC_ACCEPT}" hidden>
                            </label>
                            <button type="button" class="books-link-btn fac-profile-doc-remove" data-profile-doc-remove="${escapeHtml(slot.id)}">Remove</button>
                        </div>
                        <span class="fac-profile-doc-status" data-profile-doc-status="${escapeHtml(slot.id)}"></span>
                        <input type="hidden" name="profile_${slot.id}_documentId" value="${escapeHtml(realDocId)}">
                    </div>
                </td>`;
        }
        return `
            <td class="fac-profile-doc-cell">
                <div class="fac-profile-doc" data-profile-doc-slot="${escapeHtml(slot.id)}">
                    <label class="fac-profile-doc-upload">
                        <span class="btn btn-nav-outline fac-profile-doc-btn">Upload</span>
                        <input type="file" class="fac-profile-doc-file" data-profile-doc-upload="${escapeHtml(slot.id)}" accept="${PROFILE_DOC_ACCEPT}" hidden>
                    </label>
                    <span class="fac-profile-doc-hint">PDF, image, or Word</span>
                    <span class="fac-profile-doc-status" data-profile-doc-status="${escapeHtml(slot.id)}"></span>
                    <input type="hidden" name="profile_${slot.id}_documentId" value="">
                </div>
            </td>`;
    }

    function renderProfileRow(slot, entry, profileLeadDays, documents, complianceItems) {
        const e = PM().normalizeProfileEntry(entry);
        const doc = PM().profileDocumentForSlot(documents, entry, slot.id, {
            slotLabel: slot.label,
            complianceItems,
        });
        const status = PM().profileExpiryStatus(e, profileLeadDays);
        const statusHtml = status
            ? `<span class="fac-profile-status fac-profile-status--${status.tone}">${escapeHtml(status.label)}</span>`
            : "";
        const isCustom = !!slot.custom;
        const labelCell = isCustom
            ? `<input type="text" class="books-input fac-profile-slot-label" name="profile_slot_label_${escapeHtml(slot.id)}" value="${escapeHtml(slot.label)}" required placeholder="Item name" aria-label="Profile item name">`
            : `<strong>${escapeHtml(slot.label)}</strong>`;
        const removeLabel = isCustom ? "Remove" : "Hide";
        return `
            <tr class="fac-profile-row" data-profile-slot="${escapeHtml(slot.id)}" data-profile-custom="${isCustom ? "1" : "0"}" data-profile-builtin="${slot.builtin ? "1" : "0"}">
                <td class="fac-profile-label">
                    ${labelCell}
                    ${statusHtml}
                </td>
                <td>
                    <input type="date" class="books-input fac-profile-expiry" name="profile_${slot.id}_expiry" value="${escapeHtml(e.expiryDate)}" aria-label="${escapeHtml(slot.label)} expiry date">
                </td>
                <td class="fac-profile-notify-cell">
                    <label class="fac-profile-notify">
                        <input type="checkbox" class="fac-profile-notify-cb" name="profile_${slot.id}_notify"${e.notifyOnExpiry ? " checked" : ""} aria-label="Alert on ${escapeHtml(slot.label)} expiry">
                        <span>Alert</span>
                    </label>
                </td>
                <td class="fac-profile-compliance-cell">
                    <label class="fac-profile-notify" title="Also show under Compliance tab">
                        <input type="checkbox" class="fac-profile-compliance-cb" name="profile_${slot.id}_compliance"${e.isComplianceItem ? " checked" : ""} aria-label="Show ${escapeHtml(slot.label)} in Compliance">
                        <span>Compliance</span>
                    </label>
                </td>
                ${renderProfileDocCell(slot, entry, doc)}
                <td>
                    <input type="text" class="books-input" name="profile_${slot.id}_identifier" value="${escapeHtml(e.identifier)}" placeholder="License / policy #" aria-label="${escapeHtml(slot.label)} number">
                </td>
                <td>
                    <input type="text" class="books-input" name="profile_${slot.id}_authority" value="${escapeHtml(e.issuingAuthority)}" placeholder="Issuing authority" aria-label="${escapeHtml(slot.label)} authority">
                </td>
                <td>
                    <input type="date" class="books-input" name="profile_${slot.id}_issue" value="${escapeHtml(e.issueDate)}" aria-label="${escapeHtml(slot.label)} issue date">
                </td>
                <td>
                    <input type="text" class="books-input" name="profile_${slot.id}_notes" value="${escapeHtml(e.notes)}" placeholder="Notes" aria-label="${escapeHtml(slot.label)} notes">
                </td>
                <td class="fac-profile-rm-cell">
                    <button type="button" class="books-link-btn fac-profile-slot-rm" data-profile-slot-rm="${escapeHtml(slot.id)}">${removeLabel}</button>
                </td>
            </tr>`;
    }

    function renderProfileRestoreOptions(hiddenSlots) {
        if (!hiddenSlots.length) return "";
        const options = hiddenSlots
            .map((s) => `<option value="${escapeHtml(s.id)}">${escapeHtml(s.label)}</option>`)
            .join("");
        return `
            <div class="fac-profile-restore">
                <select class="books-select fac-profile-restore-select" data-profile-restore-select aria-label="Add back standard item">
                    <option value="">Add standard item…</option>
                    ${options}
                </select>
                <button type="button" class="btn btn-nav-outline" data-profile-restore-btn>Show</button>
            </div>`;
    }

    function renderProfileSection(profileSlotConfig, profileEntries, profileLeadDays, documents, complianceItems) {
        const slotConfig = PM().normalizeProfileSlotConfig(profileSlotConfig);
        const entries = PM().normalizeProfileEntries(profileEntries, slotConfig);
        const slots = PM().enabledProfileSlots(slotConfig);
        const hidden = PM().hiddenBuiltinSlots(slotConfig);
        const rows = slots.length
            ? slots
                  .map((slot) =>
                      renderProfileRow(slot, entries[slot.id], profileLeadDays, documents, complianceItems)
                  )
                  .join("")
            : `<tr class="fac-profile-empty"><td colspan="10"><span class="data-list-empty">No profile items yet. Add a standard or custom item below.</span></td></tr>`;
        return `
            <section class="fac-customize-section" id="fac-customize-profile">
                <h3 class="fac-customize-section-title">Facility profile</h3>
                <p class="books-hint">Add or remove items for this facility. Documents uploaded under <strong>Documents</strong> or <strong>Compliance</strong> appear here when the name matches the profile item. Check <strong>Compliance</strong> to also list an item under the Compliance tab.</p>
                <div class="fac-profile-toolbar">
                    <div class="fac-profile-add-row">
                        <input type="text" class="books-input fac-profile-new-label" data-profile-new-label placeholder="Custom item name">
                        <button type="button" class="btn btn-nav-outline" data-profile-add-custom>Add custom item</button>
                    </div>
                    ${renderProfileRestoreOptions(hidden)}
                </div>
                <div class="home-card home-cc-table-wrap fac-profile-table-wrap">
                    <table class="home-cc-table fac-profile-table">
                        <thead>
                            <tr>
                                <th>Item</th>
                                <th>Expiry date</th>
                                <th>Notify</th>
                                <th>Compliance</th>
                                <th>Document</th>
                                <th>License / policy #</th>
                                <th>Issuing authority</th>
                                <th>Issue date</th>
                                <th>Notes</th>
                                <th></th>
                            </tr>
                        </thead>
                        <tbody data-profile-tbody>${rows}</tbody>
                    </table>
                </div>
            </section>`;
    }

    function renderNotificationRow(type, item) {
        const leadCell = type.hasLeadDays
            ? `<input type="number" class="books-input fac-notify-lead" min="0" max="365" name="notify_lead_${type.id}" value="${escapeHtml(String(item.leadDays ?? type.defaultLeadDays))}" aria-label="Lead days for ${escapeHtml(type.label)}">`
            : `<span class="fac-notify-na">—</span>`;
        return `
            <tr class="fac-notify-row" data-notify-type="${escapeHtml(type.id)}">
                <td>
                    <input type="checkbox" class="fac-notify-enable" name="notify_enable_${type.id}"${item.enabled !== false ? " checked" : ""} aria-label="Enable ${escapeHtml(type.label)}">
                </td>
                <td>${escapeHtml(type.label)}</td>
                <td>${leadCell}</td>
            </tr>`;
    }

    function renderNotificationsSection(settings) {
        const config = NM().normalizeNotificationSettings(settings);
        const groups = [];
        NM().NOTIFICATION_TYPES.forEach((type) => {
            if (!groups.includes(type.group)) groups.push(type.group);
        });
        const blocks = groups
            .map((group) => {
                const types = NM().NOTIFICATION_TYPES.filter((t) => t.group === group);
                const rows = types
                    .map((type) => renderNotificationRow(type, config.items[type.id]))
                    .join("");
                return `
                    <section class="fac-notify-group">
                        <h4 class="fac-customize-subtitle">${escapeHtml(group)}</h4>
                        <div class="home-card home-cc-table-wrap">
                            <table class="home-cc-table fac-notify-table">
                                <thead>
                                    <tr>
                                        <th>Show</th>
                                        <th>Notification</th>
                                        <th>Lead time (days)</th>
                                    </tr>
                                </thead>
                                <tbody>${rows}</tbody>
                            </table>
                        </div>
                    </section>`;
            })
            .join("");
        return `
            <section class="fac-customize-section" id="fac-customize-notifications">
                <h3 class="fac-customize-section-title">Notifications</h3>
                <p class="books-hint">Choose which alerts appear under <strong>Needs attention</strong> and as <strong>push notifications</strong> for this facility (Home and facility overview). Lead time applies to expiry-based alerts. Scroll down and click <strong>Save all changes</strong> to apply.</p>
                ${blocks}
            </section>`;
    }

    function renderGeneralSection(location) {
        const loc = location || {};
        const type = effectiveFacilityType(loc);
        return `
            <section class="fac-customize-section" id="fac-customize-general">
                <h3 class="fac-customize-section-title">General</h3>
                <div class="books-grid-2">
                    <label class="books-label">Facility name *
                        <input class="books-input" name="name" required value="${escapeHtml(loc.name || "")}">
                    </label>
                    <label class="books-label">Type
                        <select class="books-select" name="facilityType">${renderFacilityTypeOptions(type)}</select>
                    </label>
                </div>
                <label class="books-label">Address *
                    <textarea class="books-input fac-create-address" name="address" rows="2" required>${escapeHtml(loc.address || "")}</textarea>
                </label>
                <label class="lottery-check fac-customize-scan-only">
                    <input type="checkbox" name="lotteryScanOnly" ${loc.lotteryScanOnly ? "checked" : ""} />
                    Scan only for End #
                </label>
                <h4 class="fac-customize-subtitle">Contact person</h4>
                <div class="books-grid-3">
                    <label class="books-label">Name
                        <input class="books-input" name="contactName" value="${escapeHtml(loc.contactName || "")}" placeholder="On-site manager or owner">
                    </label>
                    <label class="books-label">Phone
                        <input class="books-input" name="contactPhone" type="tel" value="${escapeHtml(loc.contactPhone || "")}" placeholder="(555) 555-5555">
                    </label>
                    <label class="books-label">Email
                        <input class="books-input" name="contactEmail" type="email" value="${escapeHtml(loc.contactEmail || "")}" placeholder="name@example.com">
                    </label>
                </div>
            </section>`;
    }

    function renderSection({ location, documents, complianceItems, focusBooks }) {
        const gas = hasGasStation(location);
        const config = FC().normalizeBooksFieldConfig(location.booksFieldConfig, gas);
        const profileEntries = PM().normalizeProfileEntries(
            location.facilityProfile,
            location.profileSlotConfig
        );
        const notificationSettings = NM().normalizeNotificationSettings(location.notificationSettings);
        const profileLeadDays = NM().leadDays(notificationSettings, "profile_expiry");
        return `
            <div class="fac-customize-screen" data-fac-customize-root>
                <h2 class="loc-section-heading">Customize facility</h2>
                <p class="books-hint">Update <strong>${escapeHtml(location.name)}</strong> — name, address, contact, licenses & insurance, notifications, and Daily books layout — all in one place.</p>
                <form id="fac-customize-form" class="fac-customize-form">
                    ${renderGeneralSection(location)}
                    ${renderProfileSection(
                          location.profileSlotConfig,
                          profileEntries,
                          profileLeadDays,
                          documents || [],
                          complianceItems || []
                      )}
                    ${renderNotificationsSection(notificationSettings)}
                    <section class="fac-customize-section" id="fac-customize-books">
                        <h3 class="fac-customize-section-title">Daily books</h3>
                        <p class="books-hint">Choose which fields appear in Daily books and add custom sales or expense lines.</p>
                        <div class="fac-customize-books" data-bfc-embed>
                            ${BooksUI().renderBooksConfigFields(config, gas)}
                        </div>
                    </section>
                    <div class="dir-form-actions fac-customize-actions">
                        <button type="submit" class="btn">Save all changes</button>
                        <button type="button" class="btn btn-nav-outline" id="fac-customize-reset-books">Reset books to defaults</button>
                        <span class="dir-status" id="fac-customize-status"></span>
                    </div>
                </form>
            </div>`;
    }

    function readProfileSlotConfigFromForm(form) {
        const visible = [];
        form.querySelectorAll("#fac-customize-profile .fac-profile-row").forEach((tr) => {
            const id = tr.dataset.profileSlot;
            if (!id) return;
            const custom = tr.dataset.profileCustom === "1";
            let label = "";
            if (custom) {
                label = String(
                    tr.querySelector(`[name="profile_slot_label_${id}"]`)?.value || ""
                ).trim();
            } else {
                label = String(tr.querySelector(".fac-profile-label strong")?.textContent || "").trim();
            }
            visible.push({
                id,
                label: label || (custom ? "Custom item" : id),
                ...(custom ? { custom: true } : { builtin: true }),
                enabled: true,
            });
        });

        const visibleIds = new Set(visible.map((s) => s.id));
        PM().BUILTIN_PROFILE_SLOTS.forEach((b) => {
            if (!visibleIds.has(b.id)) {
                visible.push({ id: b.id, label: b.label, builtin: true, enabled: false });
            }
        });

        return PM().normalizeProfileSlotConfig({ slots: visible });
    }

    function readProfileFromForm(form, existingEntries) {
        const slotConfig = readProfileSlotConfigFromForm(form);
        const entries =
            existingEntries && typeof existingEntries === "object" ? { ...existingEntries } : {};
        const visibleIds = new Set();

        form.querySelectorAll("#fac-customize-profile .fac-profile-row").forEach((tr) => {
            const slotId = tr.dataset.profileSlot;
            if (!slotId) return;
            visibleIds.add(slotId);
            entries[slotId] = {
                expiryDate: String(form.querySelector(`[name="profile_${slotId}_expiry"]`)?.value || "").trim(),
                notifyOnExpiry: !!form.querySelector(`[name="profile_${slotId}_notify"]`)?.checked,
                isComplianceItem: !!form.querySelector(`[name="profile_${slotId}_compliance"]`)?.checked,
                documentId: String(form.querySelector(`[name="profile_${slotId}_documentId"]`)?.value || "").trim(),
                identifier: String(form.querySelector(`[name="profile_${slotId}_identifier"]`)?.value || "").trim(),
                issuingAuthority: String(form.querySelector(`[name="profile_${slotId}_authority"]`)?.value || "").trim(),
                issueDate: String(form.querySelector(`[name="profile_${slotId}_issue"]`)?.value || "").trim(),
                notes: String(form.querySelector(`[name="profile_${slotId}_notes"]`)?.value || "").trim(),
            };
        });

        Object.keys(entries).forEach((key) => {
            if (key.startsWith("pf_") && !visibleIds.has(key)) {
                delete entries[key];
            }
        });

        return PM().normalizeProfileEntries(entries, slotConfig);
    }

    function readNotificationsFromForm(form) {
        const items = {};
        NM().NOTIFICATION_TYPES.forEach((type) => {
            const enabled = !!form.querySelector(`[name="notify_enable_${type.id}"]`)?.checked;
            const item = { enabled };
            if (type.hasLeadDays) {
                const n = parseInt(form.querySelector(`[name="notify_lead_${type.id}"]`)?.value, 10);
                item.leadDays = Number.isFinite(n) && n >= 0 ? n : type.defaultLeadDays;
            }
            items[type.id] = item;
        });
        return NM().normalizeNotificationSettings({ items });
    }

    function readForm(form, location) {
        const gas = hasGasStation({
            ...location,
            facilityType: form.querySelector('[name="facilityType"]')?.value,
        });
        const booksRoot = form.querySelector("[data-bfc-embed]") || form;
        return {
            name: String(form.querySelector('[name="name"]')?.value || "").trim(),
            address: String(form.querySelector('[name="address"]')?.value || "").trim(),
            facilityType: form.querySelector('[name="facilityType"]')?.value,
            contactName: String(form.querySelector('[name="contactName"]')?.value || "").trim(),
            contactPhone: String(form.querySelector('[name="contactPhone"]')?.value || "").trim(),
            contactEmail: String(form.querySelector('[name="contactEmail"]')?.value || "").trim(),
            profileSlotConfig: readProfileSlotConfigFromForm(form),
            facilityProfile: readProfileFromForm(form, location.facilityProfile),
            notificationSettings: readNotificationsFromForm(form),
            booksFieldConfig: BooksUI().readBooksConfigFromDom(booksRoot, gas),
            lotteryScanOnly: !!form.querySelector('[name="lotteryScanOnly"]')?.checked,
        };
    }

    function profileSlotLabelFromForm(form, slotId) {
        const tr = form?.querySelector(`[data-profile-slot="${slotId}"]`);
        if (!tr) return "Document";
        if (tr.dataset.profileCustom === "1") {
            return (
                tr.querySelector(`[name="profile_slot_label_${slotId}"]`)?.value?.trim() ||
                "Document"
            );
        }
        return tr.querySelector(".fac-profile-label strong")?.textContent?.trim() || "Document";
    }

    function ensureProfileTbodyHasRows(tbody) {
        if (tbody.querySelector(".fac-profile-row")) return;
        tbody.innerHTML = `<tr class="fac-profile-empty"><td colspan="10"><span class="data-list-empty">No profile items yet. Add a standard or custom item below.</span></td></tr>`;
    }

    async function syncProfileCompliance(userId, locationId, payload, documents, complianceItems) {
        if (!window.OplixProfileComplianceSync?.sync) return;
        await OplixProfileComplianceSync.sync(userId, locationId, {
            profileSlotConfig: payload.profileSlotConfig,
            facilityProfile: payload.facilityProfile,
            documents: documents || [],
            complianceItems: complianceItems || [],
        });
    }

    function clearProfileEmptyRow(tbody) {
        tbody.querySelector(".fac-profile-empty")?.remove();
    }

    function bindProfileSlotItems(root, ctx) {
        const section = root.querySelector("#fac-customize-profile");
        const tbody = section?.querySelector("[data-profile-tbody]");
        if (!section || !tbody || section.dataset.profileSlotsBound) return;
        section.dataset.profileSlotsBound = "1";

        const profileLeadDays = ctx.profileLeadDays;
        const documents = ctx.documents || [];
        const complianceItems = ctx.complianceItems || [];

        section.addEventListener("click", (e) => {
            if (e.target.closest("[data-profile-add-custom]")) {
                const labelInput = section.querySelector("[data-profile-new-label]");
                const label = String(labelInput?.value || "").trim();
                if (!label) {
                    labelInput?.focus();
                    return;
                }
                const id = PM().newCustomSlotId();
                const slot = { id, label, custom: true, enabled: true };
                clearProfileEmptyRow(tbody);
                tbody.insertAdjacentHTML(
                    "beforeend",
                    renderProfileRow(slot, PM().defaultProfileEntry(), profileLeadDays, documents, complianceItems)
                );
                if (labelInput) labelInput.value = "";
                return;
            }

            if (e.target.closest("[data-profile-restore-btn]")) {
                const select = section.querySelector("[data-profile-restore-select]");
                const slotId = select?.value;
                if (!slotId) return;
                const builtin = PM().BUILTIN_PROFILE_SLOTS.find((s) => s.id === slotId);
                if (!builtin) return;
                if (tbody.querySelector(`[data-profile-slot="${slotId}"]`)) return;
                const slot = { id: builtin.id, label: builtin.label, builtin: true, enabled: true };
                clearProfileEmptyRow(tbody);
                tbody.insertAdjacentHTML(
                    "beforeend",
                    renderProfileRow(slot, PM().defaultProfileEntry(), profileLeadDays, documents, complianceItems)
                );
                select.value = "";
                select.querySelector(`option[value="${slotId}"]`)?.remove();
                if (!select.querySelector('option[value]:not([value=""])')) {
                    section.querySelector(".fac-profile-restore")?.remove();
                }
                return;
            }

            const rm = e.target.closest("[data-profile-slot-rm]");
            if (!rm) return;
            const tr = rm.closest(".fac-profile-row");
            if (!tr) return;
            const isCustom = tr.dataset.profileCustom === "1";
            const msg = isCustom
                ? "Remove this custom item?"
                : "Hide this item from the profile? You can add it back with Add standard item.";
            if (!confirm(msg)) return;

            if (!isCustom) {
                const slotId = tr.dataset.profileSlot;
                const builtin = PM().BUILTIN_PROFILE_SLOTS.find((s) => s.id === slotId);
                let restore = section.querySelector(".fac-profile-restore");
                if (builtin && !restore) {
                    section.querySelector(".fac-profile-toolbar")?.insertAdjacentHTML(
                        "beforeend",
                        renderProfileRestoreOptions([{ id: slotId, label: builtin.label, builtin: true }])
                    );
                } else if (builtin && restore) {
                    const select = restore.querySelector("[data-profile-restore-select]");
                    if (select && !select.querySelector(`option[value="${slotId}"]`)) {
                        const opt = document.createElement("option");
                        opt.value = slotId;
                        opt.textContent = builtin.label;
                        select.appendChild(opt);
                    }
                }
            }

            tr.remove();
            ensureProfileTbodyHasRows(tbody);
        });
    }

    function setProfileDocStatus(root, slotId, message) {
        const el = root.querySelector(`[data-profile-doc-status="${slotId}"]`);
        if (el) el.textContent = message || "";
    }

    function expiryDateFromRow(form, slotId) {
        const expiryStr = String(form.querySelector(`[name="profile_${slotId}_expiry"]`)?.value || "").trim();
        if (!expiryStr) return null;
        const d = new Date(`${expiryStr}T12:00:00`);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function bindProfileDocuments(root, { userId, locationId, location, documents, complianceItems, form, onRefresh, globalStatus }) {
        const profileSection = root.querySelector("#fac-customize-profile");
        if (!profileSection || !DocStore()?.create) return;

        profileSection.addEventListener("change", async (e) => {
            const input = e.target.closest("[data-profile-doc-upload]");
            if (!input || !form) return;
            const slotId = input.dataset.profileDocUpload;
            const file = input.files?.[0];
            input.value = "";
            if (!file || !slotId) return;

            const existingId = form.querySelector(`[name="profile_${slotId}_documentId"]`)?.value;
            const existingDoc = (documents || []).find((d) => d.id === existingId);

            setProfileDocStatus(root, slotId, "Uploading…");
            if (globalStatus) globalStatus.textContent = "";
            try {
                await OplixSaveBusy.run(async () => {
                    if (existingDoc) {
                        await DocStore().remove(userId, locationId, existingDoc);
                    }
                    const created = await DocStore().create(userId, locationId, {
                        name: profileSlotLabelFromForm(form, slotId),
                        file,
                        expiryDate: expiryDateFromRow(form, slotId),
                        uploadedBy: userId,
                        profileSlot: slotId,
                    });
                    if (Store()?.setProfileDocumentId) {
                        await Store().setProfileDocumentId(userId, locationId, slotId, created.id);
                    }
                    if (form.querySelector(`[name="profile_${slotId}_compliance"]`)?.checked) {
                        const payload = {
                            profileSlotConfig: readProfileSlotConfigFromForm(form),
                            facilityProfile: readProfileFromForm(form, location?.facilityProfile),
                        };
                        const nextDocs = (documents || []).filter((d) => d.id !== existingDoc?.id);
                        nextDocs.push({
                            id: created.id,
                            name: created.name || profileSlotLabelFromForm(form, slotId),
                            fileURL: created.fileURL,
                            fileType: created.fileType,
                            profileSlot: slotId,
                        });
                        await syncProfileCompliance(userId, locationId, payload, nextDocs, complianceItems);
                    }
                    if (onRefresh) await onRefresh();
                }, "Uploading…");
                setProfileDocStatus(root, slotId, "Uploaded.");
            } catch (err) {
                setProfileDocStatus(root, slotId, err.message || "Upload failed.");
            }
        });

        profileSection.addEventListener("click", async (e) => {
            const btn = e.target.closest("[data-profile-doc-remove]");
            if (!btn || !form) return;
            e.preventDefault();
            const slotId = btn.dataset.profileDocRemove;
            const existingId = form.querySelector(`[name="profile_${slotId}_documentId"]`)?.value;
            const existingDoc = (documents || []).find((d) => d.id === existingId);
            if (!existingDoc) return;
            if (!confirm(`Remove the uploaded file for ${profileSlotLabelFromForm(form, slotId)}?`)) return;

            setProfileDocStatus(root, slotId, "Removing…");
            try {
                await OplixSaveBusy.run(async () => {
                    await DocStore().remove(userId, locationId, existingDoc);
                    if (Store()?.setProfileDocumentId) {
                        await Store().setProfileDocumentId(userId, locationId, slotId, "");
                    }
                    if (form.querySelector(`[name="profile_${slotId}_compliance"]`)?.checked) {
                        const payload = {
                            profileSlotConfig: readProfileSlotConfigFromForm(form),
                            facilityProfile: readProfileFromForm(form, location?.facilityProfile),
                        };
                        const nextDocs = (documents || []).filter((d) => d.id !== existingDoc?.id);
                        await syncProfileCompliance(userId, locationId, payload, nextDocs, complianceItems);
                    }
                    if (onRefresh) await onRefresh();
                }, "Removing…");
                setProfileDocStatus(root, slotId, "");
            } catch (err) {
                setProfileDocStatus(root, slotId, err.message || "Remove failed.");
            }
        });
    }

    function bind(root, { userId, location, documents, complianceItems, onRefresh, focusBooks }) {
        if (!root || root.dataset.facCustomizeBound) return;
        root.dataset.facCustomizeBound = "1";

        const form = root.querySelector("#fac-customize-form");
        const status = root.querySelector("#fac-customize-status");
        const booksEmbed = root.querySelector("[data-bfc-embed]");
        const notificationSettings = NM().normalizeNotificationSettings(location.notificationSettings);
        const profileLeadDays = NM().leadDays(notificationSettings, "profile_expiry");

        BooksUI().bindBooksConfigHandlers(booksEmbed || root, {
            hasGas: hasGasStation(location),
            statusEl: status,
            resetBtn: root.querySelector("#fac-customize-reset-books"),
            skipSubmit: true,
        });

        if (focusBooks) {
            root.querySelector("#fac-customize-books")?.scrollIntoView({ behavior: "smooth", block: "start" });
        }

        bindProfileSlotItems(root, { profileLeadDays, documents: documents || [], complianceItems: complianceItems || [] });

        bindProfileDocuments(root, {
            userId,
            locationId: location.id,
            location,
            documents: documents || [],
            complianceItems: complianceItems || [],
            form,
            onRefresh,
            globalStatus: status,
        });

        form?.addEventListener("submit", async (e) => {
            e.preventDefault();
            if (!Store()?.updateFacilityCustomization) {
                if (status) {
                    status.textContent =
                        "Save unavailable — reload the page (Cmd+Shift+R) to load the latest scripts.";
                }
                return;
            }
            const payload = readForm(form, location);
            if (!payload.name || !payload.address) {
                if (status) status.textContent = "Name and address are required.";
                return;
            }
            if (status) status.textContent = "Saving…";
            try {
                await OplixSaveBusy.run(async () => {
                    await Store().updateFacilityCustomization(userId, location.id, payload);
                    await syncProfileCompliance(userId, location.id, payload, documents, complianceItems);
                }, "Saving…");
                if (status) status.textContent = "Saved.";
                if (onRefresh) await onRefresh();
            } catch (err) {
                if (status) status.textContent = err.message || "Could not save.";
            }
        });
    }

    function isCustomizeSection(sectionId) {
        return sectionId === "facility-customize" || sectionId === "books-config";
    }

    window.OplixFacilityCustomize = {
        renderSection,
        bind,
        isCustomizeSection,
    };
})();
