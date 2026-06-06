/**
 * Firestore CRUD + Firebase Storage for facility documents.
 */
(function () {
    const MAX_BYTES = 10 * 1024 * 1024;

    function storage() {
        if (!window.oplixStorage && typeof firebase !== "undefined" && firebase.storage) {
            window.oplixStorage = firebase.storage();
        }
        return window.oplixStorage;
    }

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("documents");
    }

    function sanitizeFileName(name) {
        return String(name || "document")
            .replace(/\s+/g, "_")
            .replace(/[^a-zA-Z0-9._-]/g, "");
    }

    function fileExtension(name) {
        const ext = String(name || "")
            .split(".")
            .pop()
            .toLowerCase();
        return ext && ext !== String(name).toLowerCase() ? ext : "pdf";
    }

    function contentTypeFromName(fileName, fallback) {
        const ext = fileExtension(fileName);
        const map = {
            pdf: "application/pdf",
            jpg: "image/jpeg",
            jpeg: "image/jpeg",
            png: "image/png",
            gif: "image/gif",
            webp: "image/webp",
            heic: "image/heic",
            doc: "application/msword",
            docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        };
        return map[ext] || fallback || "application/octet-stream";
    }

    async function uploadFile(userId, locationId, file) {
        const st = storage();
        if (!st) throw new Error("File storage is not available. Reload the page and try again.");
        if (!file) throw new Error("No file selected.");
        if (file.size > MAX_BYTES) {
            throw new Error("File must be 10 MB or smaller.");
        }
        const sanitized = sanitizeFileName(file.name) || "document";
        const path = `documents/${userId}/${locationId}/${sanitized}`;
        const ref = st.ref().child(path);
        const metadata = {
            contentType: file.type || contentTypeFromName(file.name),
        };
        const snap = await ref.put(file, metadata);
        return snap.ref.getDownloadURL();
    }

    async function deleteFile(url) {
        if (!url) return;
        const st = storage();
        if (!st) return;
        try {
            await st.refFromURL(url).delete();
        } catch (err) {
            console.warn("Document file delete:", err);
        }
    }

    async function create(userId, locationId, { name, file, expiryDate, uploadedBy }) {
        const trimmed = String(name || "").trim();
        if (!trimmed) throw new Error("Document name is required.");
        if (!file) throw new Error("Please choose a file to upload.");

        const id = window.oplixDb.collection("users").doc().id;
        const fileURL = await uploadFile(userId, locationId, file);
        const fileType = fileExtension(file.name);

        const payload = {
            id,
            locationId,
            name: trimmed,
            fileURL,
            fileType,
            uploadedAt: firebase.firestore.FieldValue.serverTimestamp(),
            uploadedBy: uploadedBy || userId,
        };
        if (expiryDate) {
            payload.expiryDate = firebase.firestore.Timestamp.fromDate(expiryDate);
        }

        await colRef(userId, locationId).doc(id).set(payload);
        return id;
    }

    async function remove(userId, locationId, document) {
        if (document?.fileURL) await deleteFile(document.fileURL);
        await colRef(userId, locationId).doc(document.id).delete();
    }

    window.OplixDocumentsStore = {
        create,
        remove,
        MAX_BYTES,
    };
})();
