/**
 * Settings helpers — notification preferences.
 */
(function () {
    function resolvedChannels(prefs) {
        const c = prefs?.channels || {};
        return {
            push: c.push !== false,
            email: c.email !== false,
        };
    }

    function resolvedCategories(prefs) {
        const c = prefs?.categories || {};
        return {
            tasks: c.tasks !== false,
            schedule: c.schedule !== false,
            assignment: c.assignment !== false,
            shiftSummary: c.shiftSummary !== false,
            cashAlert: c.cashAlert !== false,
            financeAlert: c.financeAlert !== false,
            complianceAlert: c.complianceAlert !== false,
            dueReminder: c.dueReminder !== false,
            dailyDigest: c.dailyDigest === true,
        };
    }

    function resolvedQuietHours(prefs) {
        const q = prefs?.quietHours || {};
        return {
            enabled: q.enabled === true,
            startMin: Number.isFinite(q.startMin) ? q.startMin : 22 * 60,
            endMin: Number.isFinite(q.endMin) ? q.endMin : 7 * 60,
        };
    }

    function minutesToTimeInput(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
    }

    function timeInputToMinutes(value) {
        const parts = String(value || "0:0").split(":");
        const h = parseInt(parts[0], 10) || 0;
        const m = parseInt(parts[1], 10) || 0;
        return h * 60 + m;
    }

    function buildNotificationPrefs(form) {
        return {
            channels: {
                push: !!form.push,
                email: !!form.email,
            },
            categories: {
                tasks: !!form.tasks,
                schedule: !!form.schedule,
                assignment: !!form.assignment,
                shiftSummary: !!form.shiftSummary,
                cashAlert: !!form.cashAlert,
                financeAlert: !!form.financeAlert,
                complianceAlert: !!form.complianceAlert,
                dueReminder: !!form.dueReminder,
                dailyDigest: !!form.dailyDigest,
            },
            quietHours: {
                enabled: !!form.quietHoursEnabled,
                startMin: timeInputToMinutes(form.quietStart),
                endMin: timeInputToMinutes(form.quietEnd),
            },
        };
    }

    function notificationFormFromProfile(profile) {
        const prefs = profile?.notificationPrefs || {};
        const ch = resolvedChannels(prefs);
        const cat = resolvedCategories(prefs);
        const q = resolvedQuietHours(prefs);
        return {
            push: ch.push,
            email: ch.email,
            tasks: cat.tasks,
            schedule: cat.schedule,
            assignment: cat.assignment,
            shiftSummary: cat.shiftSummary,
            cashAlert: cat.cashAlert,
            financeAlert: cat.financeAlert,
            complianceAlert: cat.complianceAlert,
            dueReminder: cat.dueReminder,
            dailyDigest: cat.dailyDigest,
            quietHoursEnabled: q.enabled,
            quietStart: minutesToTimeInput(q.startMin),
            quietEnd: minutesToTimeInput(q.endMin),
        };
    }

    window.OplixSettingsModel = {
        resolvedChannels,
        resolvedCategories,
        resolvedQuietHours,
        buildNotificationPrefs,
        notificationFormFromProfile,
        minutesToTimeInput,
        timeInputToMinutes,
    };
})();
