/**
 * Facility Documents — upload, view, and delete.
 */
(function () {
    const Store = () => window.OplixDocumentsStore;

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function toDate(value) {
        return OplixTaskProgress.toDate(value);
    }

    function formatDate(date) {
        if (!date) return "";
        return date.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
    }

    function expiryStatus(doc) {
        const exp = toDate(doc.expiryDate);
        if (!exp) return null;
        const today = OplixTaskProgress.startOfDay(new Date());
        const expDay = OplixTaskProgress.startOfDay(exp);
        if (expDay < today) {
            return { label: "Expired", className: "doc-expiry--expired" };
        }
        const monthOut = new Date(today);
        monthOut.setMonth(monthOut.getMonth() + 1);
        if (expDay <= monthOut) {
            return { label: "Expiring soon", className: "doc-expiry--soon" };
        }
        return { label: `Expires ${formatDate(exp)}`, className: "doc-expiry--ok" };
    }

    function iconForFileType(fileType) {
        const type = String(fileType || "").toLowerCase();
        if (type === "pdf") return "📄";
        if (["jpg", "jpeg", "png", "gif", "webp", "heic"].includes(type)) return "🖼";
        if (["doc", "docx"].includes(type)) return "📝";
        return "📎";
    }

    function sortDocuments(docs) {
        return [...docs].sort((a, b) => {
            const ta = toDate(a.uploadedAt)?.getTime() || 0;
            const tb = toDate(b.uploadedAt)?.getTime() || 0;
            return tb - ta;
        });
    }

    function renderRow(doc) {
        const exp = expiryStatus(doc);
        const uploaded = toDate(doc.uploadedAt);
        const meta = [
            String(doc.fileType || "file").toUpperCase(),
            uploaded ? `Uploaded ${formatDate(uploaded)}` : "",
        ]
            .filter(Boolean)
            .join(" · ");

        return `
            <li class="loc-row-card doc-row" data-doc-id="${escapeHtml(doc.id)}">
                <span class="doc-icon" aria-hidden="true">${iconForFileType(doc.fileType)}</span>
                <div class="doc-row-main">
                    <strong>${escapeHtml(doc.name || "Document")}</strong>
                    <span class="data-list-meta">${escapeHtml(meta)}</span>
                    ${
                        exp
                            ? `<span class="doc-expiry ${exp.className}">${escapeHtml(exp.label)}</span>`
                            : ""
                    }
                </div>
                <div class="dir-row-actions doc-row-actions">
                    ${
                        doc.fileURL
                            ? `<a class="btn btn-nav-outline doc-download" href="${escapeHtml(doc.fileURL)}" target="_blank" rel="noopener noreferrer">Open</a>`
                            : ""
                    }
                    <button type="button" class="btn fac-btn-delete" data-doc-delete="${escapeHtml(doc.id)}">Delete</button>
                </div>
            </li>`;
    }

    function renderAddForm() {
        return `
            <form class="dir-form doc-form" data-doc-form>
                <h3 class="doc-form-title">Upload document</h3>
                <label class="books-label">Document name *
                    <input class="books-input" name="name" required placeholder="e.g. Business license">
                </label>
                <label class="books-label">File *
                    <input type="file" class="books-input doc-file-input" name="file" required
                        accept="image/*,.pdf,application/pdf,.doc,.docx">
                </label>
                <p class="books-hint">PDF, Word, or image — max 10 MB.</p>
                <label class="books-label doc-expiry-toggle">
                    <input type="checkbox" name="hasExpiry" data-doc-has-expiry>
                    Has expiry date
                </label>
                <label class="books-label doc-expiry-field" data-doc-expiry-wrap hidden>
                    Expiry date
                    <input class="books-input" name="expiryDate" type="date">
                </label>
                <div class="doc-reminder-slot" data-doc-reminder-slot hidden>
                    ${window.OplixDueDateReminderModel ? OplixDueDateReminderModel.renderDueReminderFields(null) : ""}
                </div>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Upload</button>
                    <button type="button" class="btn btn-nav-outline" data-doc-cancel>Cancel</button>
                    <span class="dir-status" data-doc-form-status></span>
                </div>
            </form>`;
    }

    function renderSection(ctx) {
        const docs = sortDocuments(ctx.data.documents || []);
        return `
            <div class="doc-section" data-doc-section>
                <h2 class="loc-section-heading">Documents</h2>
                <p class="books-hint dir-hint">Store licenses, permits, and other files for this facility. Expiry dates show alerts on Home when they are due.</p>
                <div class="dir-toolbar">
                    <button type="button" class="btn" data-doc-add>Upload document</button>
                    <span class="dir-status" data-doc-status></span>
                </div>
                <div class="dir-form-slot" data-doc-form-slot hidden></div>
                ${
                    docs.length
                        ? `<ul class="loc-row-list doc-list">${docs.map(renderRow).join("")}</ul>`
                        : `<p class="data-list-empty">No documents yet. Upload a license, permit, or other file.</p>`
                }
            </div>`;
    }

    function bind(container, ctx) {
        if (!container || container.dataset.docBound) return;
        container.dataset.docBound = "1";

        const slot = container.querySelector("[data-doc-form-slot]");
        const statusEl = container.querySelector("[data-doc-status]");

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function closeForm() {
            if (slot) {
                slot.hidden = true;
                slot.innerHTML = "";
            }
        }

        function openForm() {
            if (!slot) return;
            slot.hidden = false;
            slot.innerHTML = renderAddForm();
            slot.scrollIntoView({ behavior: "smooth", block: "nearest" });

            const form = slot.querySelector("[data-doc-form]");
            const expiryWrap = form?.querySelector("[data-doc-expiry-wrap]");
            const reminderSlot = form?.querySelector("[data-doc-reminder-slot]");
            const syncExpiry = (checked) => {
                if (expiryWrap) expiryWrap.hidden = !checked;
                if (reminderSlot) reminderSlot.hidden = !checked;
            };
            form?.querySelector("[data-doc-has-expiry]")?.addEventListener("change", (e) => {
                syncExpiry(e.target.checked);
            });
            if (form && window.OplixDueDateReminderModel) {
                OplixDueDateReminderModel.wireDueReminderForm(form);
            }
            form?.querySelector("[data-doc-cancel]")?.addEventListener("click", closeForm);

            form?.addEventListener("submit", async (e) => {
                e.preventDefault();
                const st = form.querySelector("[data-doc-form-status]");
                const fd = new FormData(form);
                const name = String(fd.get("name") || "").trim();
                const file = fd.get("file");
                const hasExpiry = !!fd.get("hasExpiry");
                const expiryStr = String(fd.get("expiryDate") || "").trim();

                if (!name) {
                    if (st) st.textContent = "Document name is required.";
                    return;
                }
                if (!file || !(file instanceof File) || !file.size) {
                    if (st) st.textContent = "Please choose a file.";
                    return;
                }

                let expiryDate = null;
                let dueReminder = null;
                if (hasExpiry) {
                    if (!expiryStr) {
                        if (st) st.textContent = "Choose an expiry date or turn off expiry.";
                        return;
                    }
                    expiryDate = new Date(`${expiryStr}T12:00:00`);
                    if (Number.isNaN(expiryDate.getTime())) {
                        if (st) st.textContent = "Invalid expiry date.";
                        return;
                    }
                    if (window.OplixDueDateReminderModel) {
                        dueReminder = OplixDueDateReminderModel.readDueReminderFromForm(form);
                    }
                }

                if (st) st.textContent = "Uploading…";
                form.querySelector('[type="submit"]')?.setAttribute("disabled", "disabled");
                try {
                    await OplixSaveBusy.run(async () => {
                        const loc = ctx.data?.location;
                        const PDS = window.OplixProfileDocumentSync;
                        const matchedSlot = PDS?.matchNameToSlot(name, loc?.profileSlotConfig);
                        const created = await Store().create(ctx.userId, ctx.locationId, {
                            name,
                            file,
                            expiryDate,
                            dueReminder,
                            uploadedBy: ctx.userId,
                            profileSlot: matchedSlot?.id,
                        });
                        if (PDS && created?.id && loc) {
                            if (matchedSlot) {
                                await PDS.linkDocumentToSlot(
                                    ctx.userId,
                                    ctx.locationId,
                                    matchedSlot.id,
                                    created.id
                                );
                            } else {
                                await PDS.afterFacilityDocumentUpload(
                                    ctx.userId,
                                    ctx.locationId,
                                    loc,
                                    created
                                );
                            }
                        }
                    }, "Uploading…");
                    closeForm();
                    setStatus("Document uploaded.");
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Upload failed.";
                    form.querySelector('[type="submit"]')?.removeAttribute("disabled");
                }
            });
        }

        container.addEventListener("click", async (e) => {
            if (e.target.matches("[data-doc-add]")) {
                openForm();
                return;
            }
            const delBtn = e.target.closest("[data-doc-delete]");
            if (!delBtn) return;
            e.preventDefault();
            const id = delBtn.dataset.docDelete;
            const doc = (ctx.data.documents || []).find((d) => d.id === id);
            if (!doc) return;
            if (!confirm(`Delete "${doc.name || "this document"}"? This cannot be undone.`)) return;
            setStatus("Deleting…");
            try {
                await OplixSaveBusy.run(async () => {
                    await Store().remove(ctx.userId, ctx.locationId, doc);
                }, "Deleting…");
                setStatus("");
                await ctx.onRefresh();
            } catch (err) {
                setStatus(err.message || "Delete failed.");
            }
        });
    }

    window.OplixFacilityDocuments = {
        renderSection,
        bind,
        isDocumentsSection(sectionId) {
            return sectionId === "documents";
        },
    };
})();
