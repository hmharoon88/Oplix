/**
 * Ohio instant pack/ticket barcode parser — mirrors iOS OhioLotteryBarcodeParser.
 */
(function () {
    const DASHED = /^(\d{3,4})-(\d{6,7})-(\d{3})-(\d)$/;
    const COMPACT = /^(\d{4})(\d{7})(\d{3})(\d)$/;

    function normalizeTicketPosition(ticketPosition) {
        const value = parseInt(ticketPosition, 10);
        if (!Number.isFinite(value)) return "";
        if (value === 0) return "00";
        return String(value);
    }

    function canonicalGameNumber(game) {
        const trimmed = String(game).trim();
        const n = parseInt(trimmed, 10);
        return Number.isFinite(n) ? String(n) : trimmed;
    }

    function isKnownGame(gameNumber, knownGames) {
        const canonical = canonicalGameNumber(gameNumber);
        if (knownGames.includes(canonical)) return true;
        return knownGames.some((g) => gameNumbersMatch(g, canonical));
    }

    function normalizeGameNumber(game) {
        return canonicalGameNumber(game);
    }

    function normalizePackSerial(pack) {
        const n = parseInt(pack, 10);
        return Number.isFinite(n) ? String(n).padStart(7, "0") : pack;
    }

    function formatDashedLabel(gameNumber, packSerial, ticketPosition, checkDigit) {
        const n = parseInt(gameNumber, 10);
        const gamePart = Number.isFinite(n) && n >= 1000 ? String(n).padStart(4, "0") : gameNumber;
        let packPart = packSerial;
        if (gamePart.length === 3 && packSerial.length === 7 && packSerial.startsWith("0")) {
            packPart = packSerial.slice(1);
        }
        return `${gamePart}-${packPart}-${ticketPosition}-${checkDigit}`;
    }

    function coreDigitCount(parts) {
        const packLen = String(parts.pack).length;
        const gameLen = String(parts.game).length;
        if (gameLen === 4 && packLen === 7) return 15;
        if (gameLen === 4 && packLen === 6) return 14;
        return 13;
    }

    function matchThreeDigitRetail(digits) {
        if (digits.length !== 13) return null;
        return {
            game: digits.slice(0, 3),
            pack: digits.slice(3, 9),
            ticket: digits.slice(9, 12),
            check: digits.slice(12, 13),
        };
    }

    function matchFourDigitRetail(digits) {
        if (digits.length !== 14) return null;
        return {
            game: digits.slice(0, 4),
            pack: digits.slice(4, 10),
            ticket: digits.slice(10, 13),
            check: digits.slice(13, 14),
        };
    }

    function matchFlexibleDigits(digits) {
        const d = digits.replace(/\D/g, "");
        if (d.length === 15) {
            const m = d.match(COMPACT);
            if (m) return { game: m[1], pack: m[2], ticket: m[3], check: m[4] };
            return null;
        }
        if (d.length === 14) {
            return matchFourDigitRetail(d);
        }
        if (d.length === 13) {
            return matchThreeDigitRetail(d);
        }
        if (d.length >= 19) {
            if (d.startsWith("0")) {
                const retail14 = matchFourDigitRetail(d.slice(0, 14));
                if (retail14) return retail14;
                const compact = d.slice(0, 15).match(COMPACT);
                if (compact) return { game: compact[1], pack: compact[2], ticket: compact[3], check: compact[4] };
            } else {
                const compact = d.slice(0, 15).match(COMPACT);
                if (compact) return { game: compact[1], pack: compact[2], ticket: compact[3], check: compact[4] };
                const retail14 = matchFourDigitRetail(d.slice(0, 14));
                if (retail14) return retail14;
            }
        }
        if (d.length >= 18) {
            const retail = matchThreeDigitRetail(d.slice(0, 13));
            if (retail) return retail;
        }
        if (d.length >= 15) {
            const m = d.slice(0, 15).match(COMPACT);
            if (m) return { game: m[1], pack: m[2], ticket: m[3], check: m[4] };
        }
        if (d.length >= 14) {
            const retail = matchFourDigitRetail(d.slice(0, 14));
            if (retail) return retail;
        }
        if (d.length >= 13) {
            return matchThreeDigitRetail(d.slice(0, 13));
        }
        return null;
    }

    function gameLookupCandidates(gameNumber) {
        const candidates = [];
        function add(value) {
            if (value && !candidates.includes(value)) candidates.push(value);
        }
        const canonical = canonicalGameNumber(gameNumber);
        add(canonical);
        add(gameNumber);
        const n = parseInt(canonical, 10);
        if (Number.isFinite(n)) add(String(n).padStart(4, "0"));
        return candidates;
    }

    function gameNumbersMatch(a, b) {
        const ta = String(a).trim();
        const tb = String(b).trim();
        const na = parseInt(ta, 10);
        const nb = parseInt(tb, 10);
        if (Number.isFinite(na) && Number.isFinite(nb)) return na === nb;
        return ta === tb;
    }

    function isRetailProductBarcode(raw) {
        const digits = String(raw).replace(/\D/g, "");
        if (String(raw).includes("-")) return false;
        if (digits.length === 12) return true;
        if (digits.length === 13 && digits.charAt(0) === "0") return true;
        return false;
    }

    function matchParts(trimmed) {
        let m = trimmed.match(DASHED);
        if (m) {
            return { game: m[1], pack: m[2], ticket: m[3], check: m[4] };
        }
        const digits = trimmed.replace(/\D/g, "");
        if (digits.length === 15) {
            m = digits.match(COMPACT);
            if (m) return { game: m[1], pack: m[2], ticket: m[3], check: m[4] };
        }
        return matchFlexibleDigits(trimmed);
    }

    function parse(raw) {
        const trimmed = raw != null ? String(raw).trim() : "";
        if (!trimmed) return { ok: false, error: "empty" };

        const lower = trimmed.toLowerCase();
        if (lower.includes("http") || lower.includes("://")) {
            return { ok: false, error: "notLotteryBarcode" };
        }

        if (isRetailProductBarcode(trimmed)) {
            return { ok: false, error: "notLotteryBarcode" };
        }

        const parts = matchParts(trimmed);
        if (!parts) {
            const digitsOnly = trimmed.replace(/\D/g, "");
            if (digitsOnly.length === 12 && !trimmed.includes("-")) {
                return { ok: false, error: "notLotteryBarcode" };
            }
            return { ok: false, error: "invalidFormat" };
        }

        const bookDigits = trimmed.replace(/\D/g, "").slice(0, coreDigitCount(parts));
        const barcode = {
            raw: trimmed,
            gameNumber: normalizeGameNumber(parts.game),
            packSerial: normalizePackSerial(parts.pack),
            ticketPosition: parts.ticket,
            ticketNumber: normalizeTicketPosition(parts.ticket),
            checkDigit: parts.check,
            bookDigits,
            dashedLabel: formatDashedLabel(
                normalizeGameNumber(parts.game),
                normalizePackSerial(parts.pack),
                parts.ticket,
                parts.check
            ),
            isSealedPack: parts.ticket === "000",
            extraScannerDigitCount: Math.max(0, trimmed.replace(/\D/g, "").length - bookDigits.length),
        };
        return { ok: true, barcode };
    }

    function isLikelyOhioLotteryBarcode(raw) {
        const trimmed = raw != null ? String(raw).trim() : "";
        if (!trimmed || isRetailProductBarcode(trimmed)) return false;
        return parse(raw).ok === true;
    }

    window.OplixOhioLotteryBarcode = {
        parse,
        isLikelyOhioLotteryBarcode,
        normalizeTicketPosition,
        canonicalGameNumber,
        isKnownGame,
        gameLookupCandidates,
        gameNumbersMatch,
    };
})();
