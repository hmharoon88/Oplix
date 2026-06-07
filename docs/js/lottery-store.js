/**
 * Firestore CRUD for lottery templates and forms (same paths as iOS).
 */
(function () {
    const Calc = () => window.OplixLotteryCalc;

    function locationRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId);
    }

    function templateColRef(userId, locationId) {
        return locationRef(userId, locationId).collection("lotteryFormTemplate");
    }

    function formsColRef(userId, locationId) {
        return locationRef(userId, locationId).collection("lotteryForms");
    }

    function storage() {
        if (!window.oplixStorage && typeof firebase !== "undefined" && firebase.storage) {
            window.oplixStorage = firebase.storage();
        }
        return window.oplixStorage;
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    function templateDocId(terminalNumber) {
        const n = terminalNumber == null ? 1 : terminalNumber;
        return n <= 1 ? "template" : `terminal_${n}`;
    }

    function effectiveTerminalNumber(template) {
        return template?.terminalNumber ?? 1;
    }

    function normalizeRow(row, index) {
        return {
            id: row.id || newId(),
            binNumber: row.binNumber != null ? String(row.binNumber) : String(index + 1),
            gameNumber: row.gameNumber != null ? String(row.gameNumber) : "",
            value: row.value != null ? String(row.value) : "",
            tickets: row.tickets != null ? String(row.tickets) : "",
            beginningNumber: row.beginningNumber != null ? String(row.beginningNumber) : "",
            endingNumber: row.endingNumber != null ? String(row.endingNumber) : "",
            sold: row.sold != null ? String(row.sold) : "",
            dollar: row.dollar != null ? String(row.dollar) : "",
            books: row.books != null ? String(row.books) : "",
        };
    }

    function normalizeTemplate(data, locationId, terminalNumber) {
        const rows = Array.isArray(data?.rows) ? data.rows.map(normalizeRow) : [];
        return {
            locationId: data?.locationId || locationId,
            rows,
            lastUpdated: data?.lastUpdated || null,
            lotteryRegisterAmount: data?.lotteryRegisterAmount != null ? String(data.lotteryRegisterAmount) : "",
            reverseOrder: !!data?.reverseOrder,
            terminalNumber: terminalNumber ?? data?.terminalNumber ?? null,
        };
    }

    function emptyTemplate(locationId, terminalNumber) {
        return normalizeTemplate(
            {
                locationId,
                rows: [],
                lotteryRegisterAmount: "",
                reverseOrder: false,
            },
            locationId,
            terminalNumber
        );
    }

    async function fetchTemplate(userId, locationId, terminalNumber) {
        const docId = templateDocId(terminalNumber);
        const snap = await templateColRef(userId, locationId).doc(docId).get();
        if (!snap.exists) return null;
        const n = terminalNumber == null ? 1 : terminalNumber;
        return normalizeTemplate(snap.data(), locationId, n <= 1 ? null : n);
    }

    async function fetchAllTemplates(userId, locationId) {
        const snap = await templateColRef(userId, locationId).get();
        const templates = snap.docs.map((d) => {
            const data = d.data();
            let terminalNumber = data.terminalNumber;
            if (terminalNumber == null && d.id.startsWith("terminal_")) {
                terminalNumber = parseInt(d.id.replace("terminal_", ""), 10) || null;
            }
            return normalizeTemplate(data, locationId, terminalNumber);
        });
        templates.sort((a, b) => effectiveTerminalNumber(a) - effectiveTerminalNumber(b));
        return templates;
    }

    async function saveTemplate(userId, locationId, template) {
        const terminalNumber = template.terminalNumber ?? null;
        const docId = templateDocId(terminalNumber);
        const payload = {
            locationId,
            rows: (template.rows || []).map(normalizeRow),
            lastUpdated: firebase.firestore.FieldValue.serverTimestamp(),
            lotteryRegisterAmount: template.lotteryRegisterAmount || "",
            reverseOrder: !!template.reverseOrder,
        };
        if (terminalNumber != null && terminalNumber > 1) {
            payload.terminalNumber = terminalNumber;
        }
        await templateColRef(userId, locationId).doc(docId).set(payload, { merge: true });
    }

    async function fetchForms(userId, locationId, limit) {
        let q = formsColRef(userId, locationId).orderBy("submittedAt", "desc");
        if (limit) q = q.limit(limit);
        const snap = await q.get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    async function createForm(userId, locationId, form) {
        await formsColRef(userId, locationId).doc(form.id).set(form);
    }

    async function updateFormImageUrl(userId, locationId, formId, imageURL) {
        await formsColRef(userId, locationId).doc(formId).update({
            "formData.imageURL": imageURL,
        });
    }

    async function uploadFormImage(userId, locationId, formId, file) {
        const st = storage();
        if (!st) throw new Error("Storage is not available.");
        const path = `lottery_form_images/${userId}/${locationId}/${formId}.jpg`;
        const ref = st.ref().child(path);
        const metadata = { contentType: file.type || "image/jpeg" };
        const snap = await ref.put(file, metadata);
        return snap.ref.getDownloadURL();
    }

    /**
     * Close shift: calculate totals, save form, roll template forward (matches iOS).
     */
    async function closeShift(userId, locationId, options) {
        const {
            template,
            endingByRowId,
            onlineTotals,
            onlineCashes,
            instantCashes,
            cashInHand,
            shiftId,
            notes,
            imageFile,
            terminalNumber,
        } = options;

        const working = JSON.parse(JSON.stringify(template));
        const reverseOrder = !!working.reverseOrder;
        const registerCash = working.lotteryRegisterAmount || null;

        for (let i = 0; i < working.rows.length; i++) {
            const row = working.rows[i];
            const ending = endingByRowId[row.id];
            if (ending != null && ending !== "") {
                row.endingNumber = String(ending);
            }
            if (!row.beginningNumber || !row.endingNumber || !row.tickets) continue;

            const { sold, books } = Calc().calculateSoldAndBooks(
                row.beginningNumber === "0" ? "00" : row.beginningNumber,
                row.endingNumber === "0" ? "00" : row.endingNumber,
                row.tickets,
                reverseOrder
            );
            const dollars = row.value ? Calc().calculateDollars(sold, row.value) : 0;
            row.sold = String(sold);
            row.dollar = String(dollars);
            row.books = String(books);
        }

        const templateTotals = Calc().calculateTemplateTotals(working.rows, reverseOrder);
        const onlineTotal = (onlineTotals || []).map(Calc().parseCashAmount).find((n) => n != null) ?? null;
        const shiftSummary = Calc().calculateShiftSummary(
            templateTotals,
            onlineTotal,
            onlineCashes || [],
            instantCashes || [],
            registerCash
        );

        const formData = {};
        for (const row of working.rows) {
            if (row.beginningNumber) formData[`begin_${row.id}`] = row.beginningNumber;
            formData[`row_${row.id}`] = row.endingNumber || "";
        }
        (onlineTotals || []).forEach((v, i) => {
            if (v) formData[`onlineTotal_${i}`] = v;
        });
        (onlineCashes || []).forEach((v, i) => {
            if (v) formData[`onlineCash_${i}`] = v;
        });
        (instantCashes || []).forEach((v, i) => {
            if (v) formData[`instantCash_${i}`] = v;
        });
        if (registerCash) formData.registerCash = registerCash;
        if (cashInHand != null) formData.cashInHand = String(cashInHand);

        const overShort = cashInHand - shiftSummary.cashInBagNet;
        const summaryData = {
            ...shiftSummary,
            overShort,
        };

        const rolled = JSON.parse(JSON.stringify(working));
        for (let i = 0; i < rolled.rows.length; i++) {
            if (rolled.rows[i].endingNumber) {
                rolled.rows[i].beginningNumber = rolled.rows[i].endingNumber;
                rolled.rows[i].endingNumber = "";
            }
            rolled.rows[i].sold = "";
            rolled.rows[i].dollar = "";
            rolled.rows[i].books = "";
        }
        rolled.terminalNumber = terminalNumber ?? rolled.terminalNumber;
        await saveTemplate(userId, locationId, rolled);

        const formId = newId();
        const form = {
            id: formId,
            locationId,
            shiftId: shiftId || `web_${Date.now()}`,
            formData,
            notes: notes || "",
            submittedAt: firebase.firestore.FieldValue.serverTimestamp(),
            shiftSummary: summaryData,
        };
        if (terminalNumber != null && terminalNumber > 1) {
            form.terminalNumber = terminalNumber;
        }

        await createForm(userId, locationId, form);

        if (imageFile) {
            try {
                const url = await uploadFormImage(userId, locationId, formId, imageFile);
                await updateFormImageUrl(userId, locationId, formId, url);
                form.formData.imageURL = url;
            } catch (err) {
                console.warn("Lottery image upload failed:", err);
            }
        }

        return { form, summary: summaryData, rolledTemplate: rolled };
    }

    window.OplixLotteryStore = {
        templateDocId,
        effectiveTerminalNumber,
        newId,
        normalizeRow,
        emptyTemplate,
        fetchTemplate,
        fetchAllTemplates,
        saveTemplate,
        fetchForms,
        createForm,
        closeShift,
        uploadFormImage,
    };
})();
