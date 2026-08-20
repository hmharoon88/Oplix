/**
 * Organization-wide vendor directory — shared by all facilities.
 *
 * Firestore: users/{uid}/vendors/{id}
 *
 * Legacy per-facility vendors (users/{uid}/locations/{locationId}/vendors) are
 * merged into this collection once on first load.
 */
(function () {
    const M = () => window.OplixLocationDirectoryModel;

    function colRef(userId) {
        return window.oplixDb.collection("users").doc(userId).collection("vendors");
    }

    function vendorKey(name) {
        return String(name || "")
            .trim()
            .toLowerCase()
            .replace(/\s+/g, " ");
    }

    function migrationKey(userId) {
        return `oplix.globalVendorsMigrated.${userId}`;
    }

    function fieldScore(v) {
        const fields = ["category", "contactName", "phone", "email", "accountNumber", "notes"];
        return fields.reduce((n, f) => n + (String(v[f] || "").trim() ? 1 : 0), 0);
    }

    async function list(userId) {
        const snap = await colRef(userId).get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    async function save(userId, id, data) {
        const payload = {
            ...data,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!data.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await colRef(userId).doc(id).set(payload, { merge: true });
    }

    async function remove(userId, id) {
        await colRef(userId).doc(id).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    async function ensureMigrated(userId, locations) {
        if (!userId || !M()) return;
        try {
            if (localStorage.getItem(migrationKey(userId)) === "1") return;
        } catch {
            /* ignore */
        }

        const existing = await list(userId);
        if (existing.length > 0) {
            try {
                localStorage.setItem(migrationKey(userId), "1");
            } catch {
                /* ignore */
            }
            return;
        }

        const LDS = window.OplixLocationDirectoryStore;
        if (!LDS?.list || !(locations || []).length) return;

        const byName = new Map();
        await Promise.all(
            locations.map(async (loc) => {
                const rows = await LDS.list(userId, loc.id, M().COLLECTIONS.vendors);
                rows.forEach((row) => {
                    const norm = M().normalizeVendor(row);
                    const key = vendorKey(norm.name);
                    if (!key) return;
                    const prev = byName.get(key);
                    if (!prev || fieldScore(norm) > fieldScore(prev)) {
                        byName.set(key, norm);
                    }
                });
            })
        );

        await Promise.all(
            [...byName.values()].map((v) => save(userId, newId(), { ...v, active: v.active !== false }))
        );

        try {
            localStorage.setItem(migrationKey(userId), "1");
        } catch {
            /* ignore */
        }
    }

    function seedKey(userId) {
        return `oplix.canonicalVendorsSeeded.20260819v1.${userId}`;
    }

    async function ensureCanonicalSeed(userId) {
        if (!userId || !M()) return;
        try {
            if (localStorage.getItem(seedKey(userId)) === "1") return;
        } catch {
            /* ignore */
        }

        const seed = window.OplixVendorDirectorySeed;
        if (!Array.isArray(seed) || !seed.length) return;

        const existing = await list(userId);
        const have = new Set();
        existing.forEach((row) => {
            const norm = M().normalizeVendor(row);
            have.add(vendorKey(norm.name));
            (norm.aliases || []).forEach((a) => have.add(vendorKey(a)));
        });

        const toAdd = seed.filter((item) => {
            const name = String(item.name || "").trim();
            if (!name || have.has(vendorKey(name))) return false;
            return !(item.aliases || []).some((a) => have.has(vendorKey(a)));
        });

        const chunk = 20;
        for (let i = 0; i < toAdd.length; i += chunk) {
            await Promise.all(
                toAdd.slice(i, i + chunk).map((item) => {
                    const payload = M().normalizeVendor({
                        name: item.name,
                        aliases: item.aliases || [],
                        active: true,
                    });
                    have.add(vendorKey(payload.name));
                    return save(userId, newId(), payload);
                })
            );
        }

        try {
            localStorage.setItem(seedKey(userId), "1");
        } catch {
            /* ignore */
        }
    }

    async function listNames(userId) {
        const rows = await list(userId);
        const seen = new Set();
        const out = [];
        rows.forEach((v) => {
            if (v.active === false) return;
            const name = String(v.name || "").trim();
            if (!name) return;
            const key = vendorKey(name);
            if (seen.has(key)) return;
            seen.add(key);
            out.push(name);
        });
        return out.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
    }

    window.OplixGlobalVendorsStore = {
        list,
        save,
        remove,
        newId,
        ensureMigrated,
        ensureCanonicalSeed,
        listNames,
        vendorKey,
    };
})();
