/**
 * Manager Home overview — alerts, pulse, lottery, and month-to-date stats.
 */
(function () {
    const VARIANCE_THRESHOLD = 5;
    const VARIANCE_CRITICAL = 20;
    const UNCLOSED_SHIFT_HOURS = 12;
    const VARIANCE_LOOKBACK_DAYS = 7;
    const MISSING_REGISTER_LOOKBACK_DAYS = 7;
    const LOTTERY_ACTIVITY_DAYS = 30;
    const DOC_EXPIRY_DAYS = 30;

    const WEEKDAY_KEYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

    function toDate(value) {
        if (!value) return null;
        if (value instanceof Date) return value;
        if (typeof value.toDate === "function") return value.toDate();
        if (typeof value === "number") return new Date(value);
        if (typeof value === "string") return new Date(value);
        return null;
    }

    function startOfDay(d) {
        const x = new Date(d);
        x.setHours(0, 0, 0, 0);
        return x;
    }

    function addDays(d, n) {
        const x = new Date(d);
        x.setDate(x.getDate() + n);
        return x;
    }

    function dateParts(d) {
        return { y: d.getFullYear(), m: d.getMonth() + 1, day: d.getDate() };
    }

    function isInDateRange(date, rangeStart, rangeEnd) {
        const { y, m, day } = dateParts(date);
        const s = dateParts(rangeStart);
        const e = dateParts(rangeEnd);
        const afterStart =
            y > s.y || (y === s.y && m > s.m) || (y === s.y && m === s.m && day >= s.day);
        const beforeEnd =
            y < e.y || (y === e.y && m < e.m) || (y === e.y && m === e.m && day <= e.day);
        return afterStart && beforeEnd;
    }

    function isInHalfOpenRange(date, start, endExclusive) {
        return date >= start && date < endExclusive;
    }

    function greetingForHour(h) {
        if (h >= 5 && h < 12) return "Good morning";
        if (h >= 12 && h < 17) return "Good afternoon";
        if (h >= 17 && h < 22) return "Good evening";
        return "Hi";
    }

    function formatCurrency(amount, { maxFraction = 0 } = {}) {
        return new Intl.NumberFormat("en-US", {
            style: "currency",
            currency: "USD",
            maximumFractionDigits: maxFraction,
            minimumFractionDigits: maxFraction,
        }).format(amount || 0);
    }

    function formatCurrencyCompact(amount) {
        const abs = Math.abs(amount);
        if (abs >= 1_000_000) return formatCurrency(amount / 1_000_000, { maxFraction: 1 }) + "M";
        if (abs >= 10_000) return formatCurrency(amount / 1_000, { maxFraction: 1 }) + "K";
        return formatCurrency(amount, { maxFraction: 0 });
    }

    function formatDateMedium(d) {
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function escapeHtml(text) {
        const div = document.createElement("div");
        div.textContent = text == null ? "" : String(text);
        return div.innerHTML;
    }

    function shiftIsActive(shift) {
        return shift.clockInTime && !shift.clockOutTime;
    }

    function shiftHasRegisterData(shift) {
        const regs = shift.registers || [];
        return (
            regs.length > 0 ||
            shift.cashSale != null ||
            shift.cashInHand != null ||
            shift.overShort != null ||
            shift.creditCard != null
        );
    }

    function shiftHoursWorked(shift) {
        const clockIn = toDate(shift.clockInTime);
        if (!clockIn) return null;
        let endTime;
        if (shift.isAutoClockedOut && shift.scheduledEndTime) {
            endTime = toDate(shift.scheduledEndTime);
        } else if (shift.clockOutTime) {
            endTime = toDate(shift.clockOutTime);
        } else {
            return null;
        }
        if (!endTime) return null;
        const hours = (endTime - clockIn) / 3600000;
        return hours > 0 ? hours : null;
    }

    function isGasLocation(location) {
        return location?.facilityType === "c_store_gas";
    }

    /** C Store shift register total — card + cash only (all registers). */
    function shiftRegisterCardCash(shift) {
        const regs = shift.registers || [];
        if (regs.length) {
            return regs.reduce((sum, r) => sum + (r.cashSale || 0) + (r.creditCard || 0), 0);
        }
        return (shift.cashSale || 0) + (shift.creditCard || 0);
    }

    function monthBooksPrefix(now) {
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    }

    function hasMonthBooksDays(daysById, now) {
        const M = window.OplixBooksModel;
        if (!M) return false;
        const prefix = monthBooksPrefix(now);
        const todayDay = M.dayIdFromDate(now);
        return Object.keys(daysById || {}).some((id) => id.startsWith(prefix) && id <= todayDay);
    }

    function storeSalesFromBooksDay(location, day) {
        const M = window.OplixBooksModel;
        if (!M || !day) return 0;
        return M.daySalesForAggregate(M.normalizeDayDoc(day), isGasLocation(location));
    }

    function formatNumberCompact(value) {
        const n = Number(value) || 0;
        return new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(n);
    }

    function monthToDateFuelFromBooks(daysById, now) {
        const M = window.OplixBooksModel;
        if (!M) return { gallons: 0, dollars: 0 };
        const prefix = monthBooksPrefix(now);
        const todayDay = M.dayIdFromDate(now);
        let gallons = 0;
        let dollars = 0;
        Object.entries(daysById || {}).forEach(([dayId, day]) => {
            if (!dayId.startsWith(prefix) || dayId > todayDay) return;
            const fuel = M.fuelDayTotal(M.normalizeDayDoc(day));
            gallons += fuel.gallons;
            dollars += fuel.dollars;
        });
        return { gallons, dollars };
    }

    function monthToDateStoreSalesFromBooks(location, daysById, now) {
        const M = window.OplixBooksModel;
        if (!M) return 0;
        const prefix = monthBooksPrefix(now);
        const todayDay = M.dayIdFromDate(now);
        let total = 0;
        Object.entries(daysById || {}).forEach(([dayId, day]) => {
            if (!dayId.startsWith(prefix) || dayId > todayDay) return;
            total += M.daySalesForAggregate(M.normalizeDayDoc(day), isGasLocation(location));
        });
        return total;
    }

    function storeSalesForDayId(location, dayId, daysById, shifts) {
        const booksDay = daysById?.[dayId];
        if (booksDay) {
            return storeSalesFromBooksDay(location, booksDay);
        }
        if (isGasLocation(location)) return 0;
        const M = window.OplixBooksModel;
        if (!M) return 0;
        let total = 0;
        for (const shift of shifts) {
            if (!shiftHasRegisterData(shift)) continue;
            const dateRef = shiftDateRef(shift);
            if (!dateRef) continue;
            if (M.dayIdFromDate(dateRef) !== dayId) continue;
            total += shiftRegisterCardCash(shift);
        }
        return total;
    }

    function shiftDateRef(shift) {
        return toDate(shift.registerClosedAt) || toDate(shift.clockOutTime) || toDate(shift.clockInTime);
    }

    function employeeWorksOn(employee, date) {
        const schedule = employee.weeklySchedule;
        if (!schedule) return false;
        const key = WEEKDAY_KEYS[date.getDay()];
        const day = schedule[key];
        return day && day.isWorking !== false;
    }

    function getTaskCycleStart(task, now) {
        const freq = task.frequency || "one_time";
        if (freq === "one_time") return new Date(0);
        if (freq === "daily") return startOfDay(now);
        if (freq === "weekly") {
            const d = new Date(now);
            const day = d.getDay();
            const diff = day === 0 ? 6 : day - 1;
            d.setDate(d.getDate() - diff);
            return startOfDay(d);
        }
        if (freq === "monthly") {
            return new Date(now.getFullYear(), now.getMonth(), 1);
        }
        return startOfDay(now);
    }

    function taskHasCompletion(task, now) {
        const freq = task.frequency || "one_time";
        const completions = task.employeeCompletions || {};
        const cycleStart = getTaskCycleStart(task, now);
        return Object.values(completions).some((c) => {
            if (c.isApproved === false) return false;
            if (freq === "one_time") return true;
            const ts = toDate(c.timestamp);
            return ts && ts >= cycleStart;
        });
    }

    function cashEnclosedFromSummary(summary) {
        if (!summary) return 0;
        return (summary.cashInBagNet || 0) + (summary.overShort || 0);
    }

    function lotterySoldAmount(form) {
        const summary = form.shiftSummary;
        if (summary && summary.totalSoldAmount != null) return summary.totalSoldAmount;
        const fd = form.formData || {};
        const raw = fd.amount || fd.sale || fd.total;
        return raw != null ? Number(raw) || 0 : 0;
    }

    function getAcknowledgedSet(userId) {
        try {
            const raw = localStorage.getItem(`oplix.acknowledgedAlerts.${userId}`);
            return raw ? new Set(JSON.parse(raw)) : new Set();
        } catch {
            return new Set();
        }
    }

    function acknowledgeAlert(userId, alertId) {
        const set = getAcknowledgedSet(userId);
        set.add(alertId);
        localStorage.setItem(`oplix.acknowledgedAlerts.${userId}`, JSON.stringify([...set]));
    }

    function applyAcknowledgedFilter(data, userId) {
        if (!data) return data;
        const acknowledged = getAcknowledgedSet(userId);
        return {
            ...data,
            alerts: (data.alerts || []).filter((a) => !acknowledged.has(a.id)),
        };
    }

    async function fetchSubcollection(userId, locationId, name) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(name)
            .get();
        return snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    }

    async function fetchLocationBundle(userId, locationId, options = {}) {
        if (options.light) {
            const [shifts, lotteryForms, locationEmployees] = await Promise.all([
                fetchSubcollection(userId, locationId, "shifts"),
                fetchSubcollection(userId, locationId, "lotteryForms"),
                fetchSubcollection(userId, locationId, "employees"),
            ]);
            return {
                shifts,
                lotteryForms,
                locationEmployees,
                payables: [],
                receivables: [],
                documents: [],
            };
        }

        const [shifts, lotteryForms, payables, receivables, locationEmployees, documents] =
            await Promise.all([
                fetchSubcollection(userId, locationId, "shifts"),
                fetchSubcollection(userId, locationId, "lotteryForms"),
                fetchSubcollection(userId, locationId, "payables"),
                fetchSubcollection(userId, locationId, "receivables"),
                fetchSubcollection(userId, locationId, "employees"),
                fetchSubcollection(userId, locationId, "documents"),
            ]);
        return { shifts, lotteryForms, payables, receivables, locationEmployees, documents };
    }

    function buildAlertsForLocation(location, bundle, nameLookup) {
        const alerts = [];
        const now = new Date();
        const todayStart = startOfDay(now);
        const tomorrowStart = addDays(todayStart, 1);
        const cutoffUnclosed = new Date(now.getTime() - UNCLOSED_SHIFT_HOURS * 3600000);
        const cutoffVariance = addDays(now, -VARIANCE_LOOKBACK_DAYS);
        const cutoffRegister = addDays(now, -MISSING_REGISTER_LOOKBACK_DAYS);

        for (const shift of bundle.shifts) {
            const clockIn = toDate(shift.clockInTime);
            if (shiftIsActive(shift) && clockIn && clockIn < cutoffUnclosed) {
                const name = nameLookup[shift.employeeId] || "Employee";
                const hours = Math.floor((now - clockIn) / 3600000);
                alerts.push({
                    id: `clockout_${shift.id}`,
                    locationId: location.id,
                    severity: 0,
                    title: `${name} forgot to clock out`,
                    subtitle: `${location.name} · clocked in ${hours}h ago`,
                    sortKey: 0,
                });
            }

            const clockOut = toDate(shift.clockOutTime);
            if (clockOut && clockOut >= cutoffRegister && !shiftHasRegisterData(shift)) {
                const hours = shiftHoursWorked(shift);
                if (hours == null || hours >= 1) {
                    const name = nameLookup[shift.employeeId] || "Employee";
                    alerts.push({
                        id: `noregister_${shift.id}`,
                        locationId: location.id,
                        severity: 0,
                        title: `${location.name} — register data missing`,
                        subtitle: `${name}'s shift · ${formatDateMedium(clockOut)}`,
                        sortKey: 1,
                    });
                }
            }

            const dateRef = shiftDateRef(shift);
            if (dateRef && dateRef >= cutoffVariance) {
                const regs = shift.registers || [];
                if (regs.length) {
                    regs.forEach((reg, i) => {
                        const v = reg.overShort;
                        if (v != null && Math.abs(v) >= VARIANCE_THRESHOLD) {
                            alerts.push(makeVarianceAlert(location, "register", v, dateRef, `regvar_${shift.id}_${i}`));
                        }
                    });
                } else if (shift.overShort != null && Math.abs(shift.overShort) >= VARIANCE_THRESHOLD) {
                    alerts.push(
                        makeVarianceAlert(location, "register", shift.overShort, dateRef, `regvar_legacy_${shift.id}`)
                    );
                }
            }
        }

        const forms = bundle.lotteryForms;
        const activityCutoff = addDays(now, -LOTTERY_ACTIVITY_DAYS);
        const hasLottery = forms.some((f) => {
            const t = toDate(f.submittedAt);
            return t && t >= activityCutoff;
        });
        if (hasLottery) {
            const yesterday = addDays(todayStart, -1);
            const submittedYesterday = forms.some((f) => {
                const t = toDate(f.submittedAt);
                return t && t >= yesterday && t < todayStart;
            });
            if (!submittedYesterday) {
                alerts.push({
                    id: `lotteryclose_${location.id}`,
                    locationId: location.id,
                    severity: 0,
                    title: `${location.name} — lottery not closed`,
                    subtitle: `No submission for ${formatDateMedium(yesterday)}`,
                    sortKey: 2,
                });
            }
        }

        for (const form of forms) {
            const submitted = toDate(form.submittedAt);
            const v = form.shiftSummary?.overShort;
            if (submitted && submitted >= cutoffVariance && v != null && Math.abs(v) >= VARIANCE_THRESHOLD) {
                alerts.push(makeVarianceAlert(location, "lottery", v, submitted, `lotvar_${form.id}`));
            }
        }

        const overdue = bundle.payables.filter((p) => {
            if (p.isPaid) return false;
            const due = toDate(p.dueDate);
            return due && startOfDay(due) < todayStart;
        });
        if (overdue.length) {
            const total = overdue.reduce((s, p) => s + (p.amount || 0), 0);
            alerts.push({
                id: `payables_${location.id}`,
                locationId: location.id,
                severity: 2,
                title: `${overdue.length} payable${overdue.length === 1 ? "" : "s"} overdue · ${formatCurrency(total)}`,
                subtitle: location.name,
                sortKey: 20,
            });
        }

        return alerts;
    }

    function makeVarianceAlert(location, kind, value, date, id) {
        const severity = Math.abs(value) >= VARIANCE_CRITICAL ? 0 : 1;
        const label = value < 0 ? "SHORT" : "OVER";
        return {
            id,
            locationId: location.id,
            severity,
            title: `${location.name} ${kind} ${label} ${formatCurrency(Math.abs(value))}`,
            subtitle: formatDateMedium(date),
            sortKey: kind === "lottery" ? 11 : 10,
        };
    }

    function alertLocationId(alert) {
        if (alert?.locationId) return alert.locationId;
        const id = String(alert?.id || "");
        if (id.startsWith("lotteryclose_")) return id.slice("lotteryclose_".length);
        if (id.startsWith("payables_")) return id.slice("payables_".length);
        if (id.startsWith("disapp_")) return id.slice("disapp_".length);
        return null;
    }

    function alertSectionId(alert) {
        const id = String(alert?.id || "");
        if (id.startsWith("clockout_") || id.startsWith("noregister_") || id.startsWith("regvar_")) {
            return "shifts";
        }
        if (id.startsWith("lotteryclose_") || id.startsWith("lotvar_")) return "lottery";
        if (id.startsWith("payables_")) return "payables";
        if (id.startsWith("doc_")) return "documents";
        if (id.startsWith("disapp_")) return "tasks";
        return null;
    }

    let needsAttentionExpanded = false;
    let lastHomeUserId = null;
    let lastBundlesByLocationId = {};

    async function persistOrgTodo(userId, id, patch, existing) {
        const M = window.OplixOrgTodosModel;
        const Store = window.OplixOrgTodosStore;
        if (!M || !Store) return;
        const base = existing || M.normalizeItem({ id });
        const payload = {
            title: patch.title != null ? patch.title : base.title,
            notes: patch.notes != null ? patch.notes : base.notes,
            dueDate: patch.dueDate != null ? patch.dueDate : base.dueDate,
            isCompleted: patch.isCompleted != null ? patch.isCompleted : base.isCompleted,
            completedAt:
                patch.completedAt !== undefined ? patch.completedAt : base.completedAt,
        };
        if (base.createdAt) payload.createdAt = base.createdAt;
        await Store.save(userId, id, payload);
    }

    async function refreshOrgTodosOnHome(userId) {
        const data = window._oplixHomeData;
        if (!data || !window.OplixOrgTodosStore) return;
        try {
            data.orgTodos = await OplixOrgTodosStore.list(userId);
            window._oplixHomeData = data;
            render(data, userId);
        } catch (err) {
            console.error("[Oplix] org todos refresh failed:", err);
        }
    }

    function openOrgTodoEditForm(container, userId, item) {
        const M = window.OplixOrgTodosModel;
        const slot = container.querySelector("[data-todo-form-slot]");
        if (!slot || !M) return;
        const v = M.normalizeItem(item);
        slot.hidden = false;
        slot.innerHTML = `
            <form class="home-todo-edit-form" data-todo-edit-form data-todo-id="${escapeHtml(v.id)}">
                <label class="books-label">Title
                    <input class="books-input" name="title" required maxlength="200" value="${escapeHtml(v.title)}">
                </label>
                <label class="books-label">Due date
                    <input class="books-input" name="dueDate" type="date" value="${escapeHtml(v.dueDate)}">
                </label>
                <label class="books-label">Notes
                    <textarea class="books-input" name="notes" rows="2" maxlength="500">${escapeHtml(v.notes)}</textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-todo-edit-cancel>Cancel</button>
                </div>
            </form>`;
        slot.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }

    function bindOrgTodos(el, userId, data) {
        const card = el.querySelector("[data-home-todos]");
        if (!card || card.dataset.todosBound) return;
        card.dataset.todosBound = "1";

        const todos = () => data.orgTodos || [];

        card.addEventListener("click", async (e) => {
            const toggleId = e.target.closest("[data-todo-toggle]")?.dataset.todoToggle;
            if (toggleId) {
                const item = todos().find((t) => t.id === toggleId);
                if (!item) return;
                const completed = !item.isCompleted;
                await persistOrgTodo(userId, toggleId, {
                    isCompleted: completed,
                    completedAt: completed ? new Date().toISOString() : null,
                }, item);
                await refreshOrgTodosOnHome(userId);
                return;
            }

            const editId = e.target.closest("[data-todo-edit]")?.dataset.todoEdit;
            if (editId) {
                const item = todos().find((t) => t.id === editId);
                if (item) openOrgTodoEditForm(card, userId, item);
                return;
            }

            const deleteId = e.target.closest("[data-todo-delete]")?.dataset.todoDelete;
            if (deleteId) {
                if (!confirm("Delete this to-do?")) return;
                await OplixOrgTodosStore.remove(userId, deleteId);
                const slot = card.querySelector("[data-todo-form-slot]");
                if (slot) {
                    slot.hidden = true;
                    slot.innerHTML = "";
                }
                await refreshOrgTodosOnHome(userId);
            }
        });

        card.addEventListener("submit", async (e) => {
            if (e.target.matches("[data-todo-add-form]")) {
                e.preventDefault();
                const fd = new FormData(e.target);
                const title = String(fd.get("title") || "").trim();
                if (!title) return;
                const dueDate = String(fd.get("dueDate") || "").trim();
                const id = OplixOrgTodosStore.newId();
                await persistOrgTodo(userId, id, {
                    title,
                    notes: "",
                    dueDate,
                    isCompleted: false,
                    completedAt: null,
                });
                e.target.reset();
                await refreshOrgTodosOnHome(userId);
                return;
            }

            if (e.target.matches("[data-todo-edit-form]")) {
                e.preventDefault();
                const id = e.target.dataset.todoId;
                const item = todos().find((t) => t.id === id);
                if (!item) return;
                const fd = new FormData(e.target);
                const title = String(fd.get("title") || "").trim();
                if (!title) return;
                await persistOrgTodo(userId, id, {
                    title,
                    notes: String(fd.get("notes") || "").trim(),
                    dueDate: String(fd.get("dueDate") || "").trim(),
                }, item);
                const slot = card.querySelector("[data-todo-form-slot]");
                if (slot) {
                    slot.hidden = true;
                    slot.innerHTML = "";
                }
                await refreshOrgTodosOnHome(userId);
            }
        });

        card.addEventListener("click", (e) => {
            if (e.target.matches("[data-todo-edit-cancel]")) {
                const slot = card.querySelector("[data-todo-form-slot]");
                if (slot) {
                    slot.hidden = true;
                    slot.innerHTML = "";
                }
            }
        });
    }

    function computeWeeklyPulse(location, payables, receivables) {
        const todayStart = startOfDay(new Date());
        const windowEnd = addDays(todayStart, 7);
        const slice = {
            id: location.id,
            name: location.name,
            receivablesDue: 0,
            receivablesCount: 0,
            payablesDue: 0,
            payablesCount: 0,
        };
        for (const p of payables) {
            if (p.isPaid) continue;
            const due = toDate(p.dueDate);
            if (!due || due >= windowEnd) continue;
            slice.payablesDue += p.amount || 0;
            slice.payablesCount += 1;
        }
        for (const r of receivables) {
            if (r.isReceived) continue;
            const due = toDate(r.dueDate);
            if (!due || due >= windowEnd) continue;
            slice.receivablesDue += r.amount || 0;
            slice.receivablesCount += 1;
        }
        return slice;
    }

    function computeLotteryToday(location, forms) {
        const todayStart = startOfDay(new Date());
        const tomorrowStart = addDays(todayStart, 1);
        const row = {
            id: location.id,
            name: location.name,
            formsCount: 0,
            cashEnclosed: 0,
            overShort: 0,
            hadOverShortData: false,
        };
        for (const form of forms) {
            const submitted = toDate(form.submittedAt);
            if (!submitted || submitted < todayStart || submitted >= tomorrowStart) continue;
            row.formsCount += 1;
            const summary = form.shiftSummary;
            if (summary) {
                row.cashEnclosed += cashEnclosedFromSummary(summary);
                if (summary.overShort != null) {
                    row.overShort += summary.overShort;
                    row.hadOverShortData = true;
                }
            }
        }
        return row;
    }

    function sameDayPriorMonth(now) {
        const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        d.setMonth(d.getMonth() - 1);
        return d;
    }

    /** Month-to-date metrics through asOfDate (same calendar days vs prior month for trends). */
    function computeMtdMetrics(location, bundle, daysById, allEmployeesDict, asOfDate) {
        const { shifts, lotteryForms } = bundle;
        const monthStart = new Date(asOfDate.getFullYear(), asOfDate.getMonth(), 1);
        const monthEnd = new Date(
            asOfDate.getFullYear(),
            asOfDate.getMonth(),
            asOfDate.getDate(),
            23,
            59,
            59
        );
        const M = window.OplixBooksModel;

        let monthToDateFuelGallons = 0;
        let monthToDateFuelDollars = 0;
        let monthToDateLotterySales = 0;
        let monthToDatePayroll = 0;
        let monthToDateExpenses = 0;

        const useBooks = hasMonthBooksDays(daysById, asOfDate);
        let monthToDateStoreSales = useBooks
            ? monthToDateStoreSalesFromBooks(location, daysById, asOfDate)
            : 0;
        if (!useBooks && !isGasLocation(location)) {
            for (const shift of shifts) {
                if (!shiftHasRegisterData(shift)) continue;
                const date = shiftDateRef(shift);
                if (!date || !isInDateRange(date, monthStart, monthEnd)) continue;
                monthToDateStoreSales += shiftRegisterCardCash(shift);
            }
        }

        if (useBooks && M) {
            const fuel = monthToDateFuelFromBooks(daysById, asOfDate);
            monthToDateFuelGallons = fuel.gallons;
            monthToDateFuelDollars = fuel.dollars;
        } else {
            for (const shift of shifts) {
                if (!shiftHasRegisterData(shift)) continue;
                const date = shiftDateRef(shift);
                if (!date || !isInDateRange(date, monthStart, monthEnd)) continue;

                const regs = shift.registers || [];
                if (regs.length) {
                    regs.forEach((r) => {
                        monthToDateFuelGallons += r.fuelSaleGallons || 0;
                        monthToDateFuelDollars += r.fuelSaleDollars || 0;
                    });
                }
            }
        }

        for (const form of lotteryForms) {
            const submitted = toDate(form.submittedAt);
            if (!submitted) continue;
            const sold = lotterySoldAmount(form);
            if (isInDateRange(submitted, monthStart, monthEnd)) {
                monthToDateLotterySales += sold;
            }
        }

        const monthShifts = shifts.filter((s) => {
            const d = shiftDateRef(s);
            return d && isInDateRange(d, monthStart, monthEnd);
        });

        const byEmployee = {};
        monthShifts.forEach((s) => {
            if (!byEmployee[s.employeeId]) byEmployee[s.employeeId] = [];
            byEmployee[s.employeeId].push(s);
        });
        Object.entries(byEmployee).forEach(([empId, empShifts]) => {
            const emp = allEmployeesDict[empId];
            if (!emp || emp.hourlyRate == null) return;
            const hours = empShifts.reduce((sum, s) => sum + (shiftHoursWorked(s) || 0), 0);
            monthToDatePayroll += hours * emp.hourlyRate;
        });

        monthShifts.forEach((shift) => {
            (shift.expenses || []).forEach((e) => {
                monthToDateExpenses += e.amount || 0;
            });
            (shift.registers || []).forEach((r) => {
                if (r.cashExpenseAmounts) {
                    monthToDateExpenses += r.cashExpenseAmounts.reduce((a, b) => a + b, 0);
                } else if (r.cashExpense != null) {
                    monthToDateExpenses += r.cashExpense;
                }
            });
        });

        return {
            monthToDateSales: monthToDateStoreSales,
            monthToDateLotterySales,
            monthToDatePayroll,
            monthToDateExpenses,
            monthToDateFuelGallons,
            monthToDateFuelDollars,
        };
    }

    function computeLocationStats(location, bundle, daysById, allEmployeesDict, now) {
        const { shifts } = bundle;
        const todayStart = startOfDay(now);
        const lastWeekStart = addDays(todayStart, -7);
        const M = window.OplixBooksModel;
        const todayDayId = M ? M.dayIdFromDate(todayStart) : null;
        const lastWeekDayId = M ? M.dayIdFromDate(lastWeekStart) : null;

        const snapshotPart = { revenue: 0, revenueLastWeek: 0, clockedIn: 0 };

        const mtd = computeMtdMetrics(location, bundle, daysById, allEmployeesDict, now);

        if (todayDayId) {
            snapshotPart.revenue = storeSalesForDayId(location, todayDayId, daysById, shifts);
        }
        if (lastWeekDayId) {
            snapshotPart.revenueLastWeek = storeSalesForDayId(
                location,
                lastWeekDayId,
                daysById,
                shifts
            );
        }

        for (const shift of shifts) {
            if (shiftIsActive(shift)) snapshotPart.clockedIn += 1;
        }

        return {
            stats: {
                id: location.id,
                locationName: location.name,
                ...mtd,
            },
            snapshotPart,
            locationName: location.name,
        };
    }

    function buildGlobalAlerts(employees, tasks, locations, allDocs) {
        const alerts = [];
        const now = new Date();
        const todayStart = startOfDay(now);
        const docCutoff = addDays(now, DOC_EXPIRY_DAYS);
        const nameById = Object.fromEntries(locations.map((l) => [l.id, l.name]));

        allDocs.forEach((doc) => {
            const exp = toDate(doc.expiryDate);
            if (!exp || exp < now || exp > docCutoff) return;
            const days = Math.max(0, Math.floor((exp - now) / 86400000));
            alerts.push({
                id: `doc_${doc.id}`,
                locationId: doc.locationId,
                severity: days <= 7 ? 1 : 2,
                title: `${doc.name || "Document"} expires in ${days} day${days === 1 ? "" : "s"}`,
                subtitle: nameById[doc.locationId] || "Location",
                sortKey: 21,
            });
        });

        const weekStart = (() => {
            const d = new Date(now);
            const day = d.getDay();
            const diff = day === 0 ? 6 : day - 1;
            d.setDate(d.getDate() - diff);
            return startOfDay(d);
        })();

        employees.forEach((emp) => {
            if (!emp.weeklySchedule) return;
            let workingDays = 0;
            for (let i = 0; i < 7; i++) {
                const day = addDays(weekStart, i);
                if (employeeWorksOn(emp, day)) workingDays += 1;
            }
            if (workingDays === 0) {
                alerts.push({
                    id: `schedgap_${emp.id}`,
                    severity: 2,
                    title: `${emp.name || "Employee"} has no shifts this week`,
                    subtitle: "",
                    sortKey: 30,
                });
            }
        });

        const byLoc = {};
        tasks.forEach((task) => {
            if (!task.locationId) return;
            const comps = task.employeeCompletions || {};
            const hasDisapproved = Object.values(comps).some((c) => c.isApproved === false);
            if (hasDisapproved) byLoc[task.locationId] = (byLoc[task.locationId] || 0) + 1;
        });
        Object.entries(byLoc).forEach(([locId, count]) => {
            alerts.push({
                id: `disapp_${locId}`,
                locationId: locId,
                severity: 1,
                title: `${count} task${count === 1 ? "" : "s"} need rework`,
                subtitle: nameById[locId] || "Location",
                sortKey: 12,
            });
        });

        return alerts;
    }

    async function loadOverview(userId, locations, employees, tasks, profile, options = {}) {
        const light = options.light === true;
        const now = new Date();
        const allEmployeesDict = {};
        employees.forEach((e) => {
            allEmployeesDict[e.id] = e;
        });

        const nameLookup = {};
        employees.forEach((e) => {
            nameLookup[e.id] = e.name || e.username || "Employee";
        });

        let alerts = [];
        let weeklyPulse = { receivablesDue: 0, receivablesCount: 0, payablesDue: 0, payablesCount: 0 };
        const lotteryToday = [];
        const locationStats = [];
        const todaySnapshot = {
            revenue: 0,
            revenueLastWeekSameDay: 0,
            clockedInCount: 0,
            scheduledTodayCount: 0,
            clockedInLocationNames: new Set(),
            tasksCompleted: 0,
            tasksTotal: 0,
        };

        const allDocs = [];
        const booksDaysByLocation = {};
        const booksDaysByLocationPrev = {};
        const M = window.OplixBooksModel;
        const monthId = M
            ? M.monthIdFromDate(now)
            : `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
        const prevAsOf = sameDayPriorMonth(now);
        const prevMonthId = M
            ? M.monthIdFromDate(prevAsOf)
            : `${prevAsOf.getFullYear()}-${String(prevAsOf.getMonth() + 1).padStart(2, "0")}`;

        const bundles = await Promise.all(
            locations.map(async (loc) => {
                const monthLoads = [
                    fetchLocationBundle(userId, loc.id, { light }),
                    window.OplixBooksStore
                        ? window.OplixBooksStore.loadMonth(userId, loc.id, monthId).catch(() => ({
                              daysById: {},
                          }))
                        : Promise.resolve({ daysById: {} }),
                ];
                if (!light) {
                    monthLoads.push(
                        window.OplixBooksStore
                            ? window.OplixBooksStore.loadMonth(userId, loc.id, prevMonthId).catch(() => ({
                                  daysById: {},
                              }))
                            : Promise.resolve({ daysById: {} })
                    );
                }
                const results = await Promise.all(monthLoads);
                const bundle = results[0];
                const books = results[1];
                const prevBooks = light ? { daysById: {} } : results[2];
                booksDaysByLocation[loc.id] = books.daysById || {};
                booksDaysByLocationPrev[loc.id] = prevBooks.daysById || {};
                if (!light) {
                    bundle.documents.forEach((d) => allDocs.push({ ...d, locationId: loc.id }));
                }
                bundle.locationEmployees.forEach((e) => {
                    if (!allEmployeesDict[e.id]) allEmployeesDict[e.id] = e;
                    nameLookup[e.id] = e.name || e.username || "Employee";
                });
                return { location: loc, bundle };
            })
        );

        lastBundlesByLocationId = {};
        bundles.forEach(({ location, bundle }) => {
            lastBundlesByLocationId[location.id] = bundle;
            alerts = alerts.concat(buildAlertsForLocation(location, bundle, nameLookup));

            const pulse = computeWeeklyPulse(location, bundle.payables, bundle.receivables);
            weeklyPulse.receivablesDue += pulse.receivablesDue;
            weeklyPulse.receivablesCount += pulse.receivablesCount;
            weeklyPulse.payablesDue += pulse.payablesDue;
            weeklyPulse.payablesCount += pulse.payablesCount;

            lotteryToday.push(computeLotteryToday(location, bundle.lotteryForms));

            const { stats, snapshotPart } = computeLocationStats(
                location,
                bundle,
                booksDaysByLocation[location.id],
                allEmployeesDict,
                now
            );
            if (light) {
                stats.prevMtd = {};
                stats.prevMtdPending = true;
            } else {
                stats.prevMtd = computeMtdMetrics(
                    location,
                    bundle,
                    booksDaysByLocationPrev[location.id],
                    allEmployeesDict,
                    prevAsOf
                );
            }
            locationStats.push(stats);
            todaySnapshot.revenue += snapshotPart.revenue;
            todaySnapshot.revenueLastWeekSameDay += snapshotPart.revenueLastWeek;
            todaySnapshot.clockedInCount += snapshotPart.clockedIn;
            if (snapshotPart.clockedIn > 0) todaySnapshot.clockedInLocationNames.add(location.name);
        });

        alerts = alerts.concat(buildGlobalAlerts(employees, tasks, locations, allDocs));
        alerts.sort((a, b) => {
            if (a.severity !== b.severity) return a.severity - b.severity;
            return a.sortKey - b.sortKey;
        });

        lotteryToday.sort((a, b) => {
            if (a.hadOverShortData !== b.hadOverShortData) return a.hadOverShortData ? -1 : 1;
            if (a.hadOverShortData) {
                const diff = Math.abs(b.overShort) - Math.abs(a.overShort);
                if (diff !== 0) return diff;
            }
            return a.name.localeCompare(b.name);
        });

        employees.forEach((e) => {
            if (employeeWorksOn(e, now)) todaySnapshot.scheduledTodayCount += 1;
        });

        tasks.forEach((task) => {
            if (!task.locationId) return;
            todaySnapshot.tasksTotal += 1;
            if (taskHasCompletion(task, now)) todaySnapshot.tasksCompleted += 1;
        });

        const acknowledged = getAcknowledgedSet(userId);
        alerts = alerts.filter((a) => !acknowledged.has(a.id));

        weeklyPulse.net = weeklyPulse.receivablesDue - weeklyPulse.payablesDue;

        let orgTodos = [];
        if (window.OplixOrgTodosStore) {
            try {
                orgTodos = await OplixOrgTodosStore.list(userId);
            } catch {
                orgTodos = [];
            }
        }

        return {
            profile,
            locations,
            employees,
            tasks,
            alerts,
            orgTodos,
            weeklyPulse,
            lotteryToday,
            locationStats,
            todaySnapshot: {
                ...todaySnapshot,
                clockedInLocationNames: [...todaySnapshot.clockedInLocationNames].sort(),
            },
        };
    }

    async function enrichOverview(userId, locations, employees, tasks, profile, data) {
        const now = new Date();
        const prevAsOf = sameDayPriorMonth(now);
        const M = window.OplixBooksModel;
        const prevMonthId = M
            ? M.monthIdFromDate(prevAsOf)
            : `${prevAsOf.getFullYear()}-${String(prevAsOf.getMonth() + 1).padStart(2, "0")}`;

        const allEmployeesDict = {};
        employees.forEach((e) => {
            allEmployeesDict[e.id] = e;
        });
        Object.values(lastBundlesByLocationId).forEach((bundle) => {
            bundle.locationEmployees.forEach((e) => {
                if (!allEmployeesDict[e.id]) allEmployeesDict[e.id] = e;
            });
        });

        let weeklyPulse = {
            receivablesDue: 0,
            receivablesCount: 0,
            payablesDue: 0,
            payablesCount: 0,
        };
        const allDocs = [];

        await Promise.all(
            locations.map(async (loc) => {
                const [payables, receivables, documents, prevBooks] = await Promise.all([
                    fetchSubcollection(userId, loc.id, "payables"),
                    fetchSubcollection(userId, loc.id, "receivables"),
                    fetchSubcollection(userId, loc.id, "documents"),
                    window.OplixBooksStore
                        ? window.OplixBooksStore.loadMonth(userId, loc.id, prevMonthId).catch(() => ({
                              daysById: {},
                          }))
                        : Promise.resolve({ daysById: {} }),
                ]);

                const bundle = lastBundlesByLocationId[loc.id];
                if (bundle) {
                    bundle.payables = payables;
                    bundle.receivables = receivables;
                    bundle.documents = documents;
                }

                documents.forEach((d) => allDocs.push({ ...d, locationId: loc.id }));

                const pulse = computeWeeklyPulse(loc, payables, receivables);
                weeklyPulse.receivablesDue += pulse.receivablesDue;
                weeklyPulse.receivablesCount += pulse.receivablesCount;
                weeklyPulse.payablesDue += pulse.payablesDue;
                weeklyPulse.payablesCount += pulse.payablesCount;

                const stat = data.locationStats.find((s) => s.id === loc.id);
                if (stat && bundle) {
                    stat.prevMtd = computeMtdMetrics(
                        loc,
                        bundle,
                        prevBooks.daysById || {},
                        allEmployeesDict,
                        prevAsOf
                    );
                    delete stat.prevMtdPending;
                }
            })
        );

        weeklyPulse.net = weeklyPulse.receivablesDue - weeklyPulse.payablesDue;
        data.weeklyPulse = weeklyPulse;

        const docAlerts = buildGlobalAlerts(employees, tasks, locations, allDocs).filter((a) =>
            a.id.startsWith("doc_")
        );
        const nonDocAlerts = data.alerts.filter((a) => !a.id.startsWith("doc_"));
        const acknowledged = getAcknowledgedSet(userId);
        data.alerts = [...nonDocAlerts, ...docAlerts]
            .filter((a) => !acknowledged.has(a.id))
            .sort((a, b) => {
                if (a.severity !== b.severity) return a.severity - b.severity;
                return a.sortKey - b.sortKey;
            });

        return data;
    }

    function severityClass(severity) {
        if (severity === 0) return "home-severity--critical";
        if (severity === 1) return "home-severity--warning";
        return "home-severity--info";
    }

    function renderGreeting(data) {
        const hour = new Date().getHours();
        const greeting = greetingForHour(hour);
        const org = data.profile.organizationName;
        const title = org ? `${greeting}, ${org}` : greeting;
        const dateStr = new Date()
            .toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" })
            .replace(",", " ·");
        return `
            <header class="home-greeting">
                <h1 class="home-greeting-title">${escapeHtml(title)}</h1>
                <p class="home-greeting-date">${escapeHtml(dateStr)}</p>
            </header>`;
    }

    function renderNeedsAttention(alerts, userId) {
        const header = `
            <div class="home-card-header">
                <span class="home-card-header-icon">⚠️</span>
                <h2>Needs Attention</h2>
                ${alerts.length ? `<span class="home-badge">${alerts.length}</span>` : ""}
            </div>`;
        let body;
        if (!alerts.length) {
            body = `
                <div class="home-empty-row">
                    <span class="home-empty-icon">✓</span>
                    <div>
                        <p class="home-empty-title">All caught up</p>
                        <p class="home-empty-sub">Nothing needs you right now</p>
                    </div>
                </div>`;
        } else {
            const limit = 5;
            const visible = needsAttentionExpanded ? alerts : alerts.slice(0, limit);
            body = `
                <ul class="home-alert-list" id="home-alert-list">
                    ${visible
                        .map((a) => {
                            const locId = alertLocationId(a);
                            const sectionId = alertSectionId(a);
                            const canOpen = !!locId;
                            return `
                        <li class="home-alert-item">
                            <button type="button" class="home-alert-main"${canOpen ? ` data-alert-location="${escapeHtml(locId)}"${sectionId ? ` data-alert-section="${escapeHtml(sectionId)}"` : ""}` : ""}${canOpen ? "" : " disabled"}>
                                <span class="home-severity-dot ${severityClass(a.severity)}"></span>
                                <span class="home-alert-text">
                                    <span class="home-alert-title">${escapeHtml(a.title)}</span>
                                    ${a.subtitle ? `<span class="home-alert-sub">${escapeHtml(a.subtitle)}</span>` : ""}
                                </span>
                                ${canOpen ? `<span class="home-alert-chevron">›</span>` : ""}
                            </button>
                            <button type="button" class="home-alert-ack" data-alert-id="${escapeHtml(a.id)}" title="Acknowledge">✓</button>
                        </li>`;
                        })
                        .join("")}
                </ul>
                ${
                    alerts.length > limit
                        ? `<button type="button" class="home-alert-more" id="home-alert-toggle">${needsAttentionExpanded ? "Show less" : `Show ${alerts.length - limit} more`}</button>`
                        : ""
                }`;
        }
        return `<div class="home-cc-block home-card">${header}${body}</div>`;
    }

    function formatTodoDate(iso) {
        if (!iso) return "";
        const d = window.OplixOrgTodosModel?.parseISODate(iso);
        if (!d) return iso;
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
    }

    function renderOrgTodos(todos) {
        const M = window.OplixOrgTodosModel;
        if (!M) return "";
        const sorted = M.sortItems(todos || []);
        const open = sorted.filter((t) => !t.isCompleted);
        const done = sorted.filter((t) => t.isCompleted);
        const openCount = open.length;

        const renderRow = (item) => {
            const hint = M.dueHint(item);
            const overdue = M.isOverdue(item);
            const dueToday = M.isDueToday(item);
            const rowClass = item.isCompleted
                ? "home-todo-row--done"
                : overdue
                  ? "home-todo-row--overdue"
                  : dueToday
                    ? "home-todo-row--today"
                    : "";
            return `
                <li class="home-todo-row ${rowClass}" data-todo-id="${escapeHtml(item.id)}">
                    <button type="button" class="home-todo-check" data-todo-toggle="${escapeHtml(item.id)}" aria-label="${item.isCompleted ? "Mark incomplete" : "Mark complete"}">
                        ${item.isCompleted ? "✓" : ""}
                    </button>
                    <button type="button" class="home-todo-main" data-todo-edit="${escapeHtml(item.id)}">
                        <span class="home-todo-title">${escapeHtml(item.title)}</span>
                        ${
                            item.dueDate
                                ? `<span class="home-todo-due${overdue ? " home-todo-due--overdue" : ""}">${escapeHtml(formatTodoDate(item.dueDate))}${hint ? ` · ${escapeHtml(hint)}` : ""}</span>`
                                : hint
                                  ? `<span class="home-todo-due">${escapeHtml(hint)}</span>`
                                  : ""
                        }
                        ${item.notes ? `<span class="home-todo-notes">${escapeHtml(item.notes)}</span>` : ""}
                    </button>
                    <button type="button" class="home-todo-delete" data-todo-delete="${escapeHtml(item.id)}" title="Delete">×</button>
                </li>`;
        };

        const listHtml =
            open.length || done.length
                ? `<ul class="home-todo-list">${open.map(renderRow).join("")}${done.length ? `<li class="home-todo-divider">Completed (${done.length})</li>${done.map(renderRow).join("")}` : ""}</ul>`
                : `<div class="home-empty-row home-todo-empty">
                    <span class="home-empty-icon">☐</span>
                    <div>
                        <p class="home-empty-title">Nothing on your list</p>
                        <p class="home-empty-sub">Add items you need to handle — org-wide, not tied to a facility</p>
                    </div>
                </div>`;

        return `
            <div class="home-cc-block home-card home-todo-card" data-home-todos>
                <div class="home-card-header">
                    <span class="home-card-header-icon">☐</span>
                    <h2>To-Do</h2>
                    ${openCount ? `<span class="home-badge">${openCount}</span>` : ""}
                </div>
                ${listHtml}
                <form class="home-todo-add" data-todo-add-form>
                    <input class="home-todo-add-input" name="title" type="text" placeholder="Add something to do…" autocomplete="off" maxlength="200">
                    <input class="home-todo-add-date" name="dueDate" type="date" title="Due date (optional)">
                    <button type="submit" class="btn home-todo-add-btn">Add</button>
                </form>
                <div class="home-todo-form-slot" data-todo-form-slot hidden></div>
            </div>`;
    }

    function renderToday(snapshot) {
        let trend = "";
        if (snapshot.revenueLastWeekSameDay > 0) {
            const pct =
                ((snapshot.revenue - snapshot.revenueLastWeekSameDay) / snapshot.revenueLastWeekSameDay) * 100;
            const isFlat = Math.abs(pct) < 0.5;
            const isUp = pct >= 0;
            const weekday = new Date().toLocaleDateString("en-US", { weekday: "short" });
            trend = `<span class="home-trend ${isFlat ? "home-trend--flat" : isUp ? "home-trend--up" : "home-trend--down"}">
                ${isFlat ? "—" : isUp ? "▲" : "▼"} ${Math.abs(pct).toFixed(0)}% vs last ${weekday}
            </span>`;
        }
        const denom = Math.max(snapshot.scheduledTodayCount, snapshot.clockedInCount);
        const clockPct = denom > 0 ? snapshot.clockedInCount / denom : 0;
        const taskPct = snapshot.tasksTotal > 0 ? snapshot.tasksCompleted / snapshot.tasksTotal : 0;
        let clockSub = "";
        const names = snapshot.clockedInLocationNames;
        if (!names.length) {
            clockSub = snapshot.scheduledTodayCount > 0 ? "No one is on shift" : "";
        } else if (names.length <= 2) {
            clockSub = names.join(", ");
        } else {
            clockSub = `${names.slice(0, 2).join(", ")} +${names.length - 2}`;
        }
        const taskSub =
            snapshot.tasksTotal > 0 ? `${Math.round(taskPct * 100)}% done` : "No tasks today";

        return `
            <div class="home-cc-block">
                <h2 class="home-cc-heading">Today at a glance</h2>
                <div class="home-card home-today-revenue">
                    <p class="home-today-amount">${formatCurrency(snapshot.revenue)}</p>
                    <p class="home-today-meta">Store sales today ${trend}</p>
                </div>
                <div class="home-tiles">
                    <div class="home-card home-tile">
                        <p class="home-tile-label">Clocked in</p>
                        <p class="home-tile-value">${snapshot.clockedInCount} / ${denom}</p>
                        <div class="home-progress"><div class="home-progress-fill home-progress-fill--blue" style="width:${Math.min(clockPct * 100, 100)}%"></div></div>
                        ${clockSub ? `<p class="home-tile-sub">${escapeHtml(clockSub)}</p>` : ""}
                    </div>
                    <div class="home-card home-tile">
                        <p class="home-tile-label">Tasks</p>
                        <p class="home-tile-value">${snapshot.tasksCompleted} / ${snapshot.tasksTotal}</p>
                        <div class="home-progress"><div class="home-progress-fill home-progress-fill--orange" style="width:${Math.min(taskPct * 100, 100)}%"></div></div>
                        <p class="home-tile-sub">${escapeHtml(taskSub)}</p>
                    </div>
                </div>
            </div>`;
    }

    function renderThisWeek(pulse) {
        const netPrefix = pulse.net >= 0 ? "+" : "-";
        const netFormatted = `${netPrefix}${formatCurrency(Math.abs(pulse.net))}`;
        const netClass = pulse.net >= 0 ? "home-amount--pos" : "home-amount--neg";
        return `
            <div class="home-cc-block">
                <h2 class="home-cc-heading">This week</h2>
                <div class="home-card home-stack">
                    ${pulseRow("Receivables due", pulse.receivablesCount, pulse.receivablesDue, "pos")}
                    ${pulseRow("Payables due", pulse.payablesCount, pulse.payablesDue, "neg")}
                    <div class="home-stack-row home-stack-row--net">
                        <span class="home-stack-label"><strong>Net</strong></span>
                        <span class="home-stack-amount ${netClass}">${netFormatted}</span>
                    </div>
                </div>
            </div>`;
    }

    function pulseRow(label, count, amount, tone) {
        const sub =
            count > 0
                ? `${count} item${count === 1 ? "" : "s"} · next 7 days`
                : "Nothing due in the next 7 days";
        const amtClass = count > 0 ? (tone === "pos" ? "home-amount--pos" : "home-amount--neg") : "";
        return `
            <div class="home-stack-row">
                <div>
                    <p class="home-stack-label">${escapeHtml(label)}</p>
                    <p class="home-stack-sub">${escapeHtml(sub)}</p>
                </div>
                <span class="home-stack-amount ${amtClass}">${formatCurrency(amount)}</span>
            </div>`;
    }

    function lotteryStatus(row) {
        if (!row.hadOverShortData) return { text: "—", class: "home-pill--muted" };
        if (Math.abs(row.overShort) < 0.005) return { text: "Even", class: "home-pill--even" };
        if (row.overShort > 0) return { text: `+${formatCurrency(row.overShort, { maxFraction: 2 })}`, class: "home-pill--pos" };
        return { text: `-${formatCurrency(Math.abs(row.overShort), { maxFraction: 2 })}`, class: "home-pill--neg" };
    }

    function renderLotteryTable(rows) {
        const sorted = [...rows].sort((a, b) => {
            if (a.formsCount !== b.formsCount) return b.formsCount - a.formsCount;
            return a.name.localeCompare(b.name);
        });

        if (!sorted.length) {
            return `
                <div class="home-cc-block">
                    <h2 class="home-cc-heading">Lottery today</h2>
                    <div class="home-card home-cc-empty">No facilities to show</div>
                </div>`;
        }

        const active = sorted.filter((r) => r.formsCount > 0);
        if (!active.length) {
            return `
                <div class="home-cc-block">
                    <h2 class="home-cc-heading">Lottery today</h2>
                    <div class="home-card home-cc-empty">No lottery shifts closed yet today (${sorted.length} facilit${sorted.length === 1 ? "y" : "ies"})</div>
                </div>`;
        }

        const tableRows = active
            .map((row) => {
                const pill = lotteryStatus(row);
                const shifts =
                    row.formsCount === 0
                        ? "—"
                        : `${row.formsCount} shift${row.formsCount === 1 ? "" : "s"}`;
                return `
                <tr>
                    <td>${escapeHtml(row.name)}</td>
                    <td>${shifts}</td>
                    <td class="home-cc-num"><span class="home-pill ${pill.class}">${pill.text}</span></td>
                </tr>`;
            })
            .join("");

        return `
            <div class="home-cc-block">
                <h2 class="home-cc-heading">Lottery today</h2>
                <div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table">
                        <thead>
                            <tr>
                                <th>Facility</th>
                                <th>Shifts</th>
                                <th>Over / short</th>
                            </tr>
                        </thead>
                        <tbody>${tableRows}</tbody>
                    </table>
                </div>
            </div>`;
    }

    function renderQuickActions() {
        const items = [
            { panel: "facilities", label: "Facilities" },
            { panel: "payroll", label: "Payroll" },
            { panel: "tasks", label: "Tasks" },
            { panel: "employees", label: "Employees" },
            { panel: "reports", label: "Reports" },
        ];
        return `
            <div class="home-cc-actions">
                <span class="home-cc-actions-label">Quick actions</span>
                <div class="home-cc-actions-btns">
                    ${items
                        .map(
                            (s) =>
                                `<button type="button" class="home-cc-action-btn" data-panel="${s.panel}">${escapeHtml(s.label)}</button>`
                        )
                        .join("")}
                </div>
            </div>`;
    }

    function renderMtdTrend(current, previous, options) {
        const cur = Number(current) || 0;
        const prev = Number(previous) || 0;
        const invert = options?.invert === true;
        if (cur === 0 && prev === 0) return "";
        let pct;
        let isUp;
        if (prev === 0) {
            if (cur === 0) return "";
            pct = 100;
            isUp = true;
        } else {
            pct = ((cur - prev) / prev) * 100;
            if (Math.abs(pct) < 0.5) {
                return `<span class="home-mtd-trend home-trend home-trend--flat">— 0%</span>`;
            }
            isUp = pct >= 0;
        }
        const visualUp = invert ? !isUp : isUp;
        const cls = visualUp ? "home-trend--up" : "home-trend--down";
        const arrow = isUp ? "▲" : "▼";
        return `<span class="home-mtd-trend home-trend ${cls}">${arrow} ${Math.abs(pct).toFixed(0)}%</span>`;
    }

    function renderMtdCell(current, previous, formatFn, trendOpts) {
        const trend = trendOpts?.pending
            ? ""
            : renderMtdTrend(current, previous, trendOpts);
        return `<td class="home-cc-num home-cc-num--mtd">
            <span class="home-mtd-value">${formatFn(current)}</span>
            ${trend}
        </td>`;
    }

    function renderMonthToDateTable(stats) {
        if (!stats.length) return "";
        const rows = [...stats].sort((a, b) => b.monthToDateSales - a.monthToDateSales);
        const prev = (s) => s.prevMtd || {};
        const trendOpts = (s) => ({ pending: s.prevMtdPending, invert: false });
        const trendOptsInvert = (s) => ({ pending: s.prevMtdPending, invert: true });

        return `
            <div class="home-cc-block home-cc-full">
                <h2 class="home-cc-heading">Month to date</h2>
                <p class="books-hint home-mtd-hint">Compared to the same days last month. Store sales — merch for gas; register card + cash for C Store.</p>
                <div class="home-card home-cc-table-wrap">
                    <table class="home-cc-table home-cc-table--mtd">
                        <thead>
                            <tr>
                                <th>Facility</th>
                                <th class="home-cc-num">Store sales</th>
                                <th class="home-cc-num">Gallons</th>
                                <th class="home-cc-num">Fuel</th>
                                <th class="home-cc-num">Lottery</th>
                                <th class="home-cc-num">Payroll</th>
                                <th class="home-cc-num">Expenses</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${rows
                                .map(
                                    (s) => `
                            <tr>
                                <td><strong>${escapeHtml(s.locationName)}</strong></td>
                                ${renderMtdCell(s.monthToDateSales, prev(s).monthToDateSales, formatCurrencyCompact, trendOpts(s))}
                                ${renderMtdCell(s.monthToDateFuelGallons, prev(s).monthToDateFuelGallons, formatNumberCompact, trendOpts(s))}
                                ${renderMtdCell(s.monthToDateFuelDollars, prev(s).monthToDateFuelDollars, formatCurrencyCompact, trendOpts(s))}
                                ${renderMtdCell(s.monthToDateLotterySales, prev(s).monthToDateLotterySales, formatCurrencyCompact, trendOpts(s))}
                                ${renderMtdCell(s.monthToDatePayroll, prev(s).monthToDatePayroll, formatCurrencyCompact, trendOptsInvert(s))}
                                ${renderMtdCell(s.monthToDateExpenses, prev(s).monthToDateExpenses, formatCurrencyCompact, trendOptsInvert(s))}
                            </tr>`
                                )
                                .join("")}
                        </tbody>
                    </table>
                </div>
            </div>`;
    }

    function renderCommandCenter(data, userId) {
        const Layout = window.OplixHomeLayoutStore;
        const prefs = Layout ? Layout.load(userId) : null;
        const filteredAlerts = Layout
            ? Layout.filterAlerts(data.alerts, prefs)
            : data.alerts;

        const sections = {
            orgTodos: renderOrgTodos(data.orgTodos),
            actionCenter: renderNeedsAttention(filteredAlerts, userId),
            thisWeek: renderThisWeek(data.weeklyPulse),
            today: renderToday(data.todaySnapshot),
            lotteryToday: renderLotteryTable(data.lotteryToday),
            monthToDate: renderMonthToDateTable(data.locationStats),
            shortcuts: renderQuickActions(),
        };

        const order = Layout
            ? Layout.visibleSectionsInOrder(prefs)
            : ["orgTodos", "actionCenter", "today", "lotteryToday", "thisWeek", "shortcuts", "monthToDate"];

        const blocks = order.map((id) => sections[id]).filter(Boolean).join("");

        return `
            ${renderGreeting(data)}
            <div class="home-sections-stack">${blocks}</div>`;
    }

    function render(data, userId) {
        const html = renderCommandCenter(data, userId);

        const el = document.getElementById("home-overview");
        el.innerHTML = html;
        el.hidden = false;

        el.querySelectorAll(".home-alert-ack").forEach((btn) => {
            btn.addEventListener("click", () => {
                const alertId = btn.dataset.alertId;
                if (!alertId) return;
                acknowledgeAlert(userId, alertId);
                const base = window._oplixHomeData || data;
                const updated = applyAcknowledgedFilter(base, userId);
                window._oplixHomeData = updated;
                render(updated, userId);
            });
        });

        el.querySelector("#home-alert-toggle")?.addEventListener("click", () => {
            needsAttentionExpanded = !needsAttentionExpanded;
            render(data, userId);
        });

        el.querySelectorAll(".home-cc-action-btn[data-panel]").forEach((btn) => {
            btn.addEventListener("click", () => {
                if (typeof window.showDashboardPanel === "function") {
                    window.showDashboardPanel(btn.dataset.panel);
                }
            });
        });

        el.querySelectorAll(".home-alert-main[data-alert-location]").forEach((btn) => {
            btn.addEventListener("click", async () => {
                const locationId = btn.dataset.alertLocation;
                const sectionId = btn.dataset.alertSection || null;
                if (!locationId) return;
                if (typeof window.showDashboardPanel === "function") {
                    window.showDashboardPanel("facilities");
                }
                if (window.OplixFacilities?.openLocation) {
                    await OplixFacilities.openLocation(locationId, { sectionId });
                }
            });
        });

        bindOrgTodos(el, userId, data);
    }

    window.OplixHomeOverview = {
        async loadAndRender(userId, locations, employees, tasks, profile, options = {}) {
            const deferHeavy = options.deferHeavy === true;
            lastHomeUserId = userId;
            const loading = document.getElementById("home-loading");
            const overview = document.getElementById("home-overview");
            loading.hidden = false;
            overview.hidden = true;
            try {
                const data = await loadOverview(userId, locations, employees, tasks, profile, {
                    light: deferHeavy,
                });
                loading.hidden = true;
                render(data, userId);
                window._oplixHomeData = data;
                if (deferHeavy) {
                    enrichOverview(userId, locations, employees, tasks, profile, data)
                        .then((enriched) => {
                            render(enriched, userId);
                            window._oplixHomeData = enriched;
                        })
                        .catch((err) => {
                            console.error("[Oplix] Home overview enrich failed:", err);
                        });
                }
            } catch (err) {
                loading.innerHTML = `<p class="app-error">${escapeHtml(err.message || "Failed to load home overview.")}</p>`;
            }
        },
        async reload(userId, locations, employees, tasks, profile) {
            lastHomeUserId = userId;
            const data = await loadOverview(userId, locations, employees, tasks, profile);
            render(data, userId);
            window._oplixHomeData = data;
        },
        resetToRoot() {
            needsAttentionExpanded = false;
            const data = window._oplixHomeData;
            if (data && lastHomeUserId) {
                render(data, lastHomeUserId);
            }
        },
    };
})();
