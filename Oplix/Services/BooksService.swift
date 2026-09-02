//
//  BooksService.swift
//  Oplix
//
//  Firestore access for web Daily books (reads for reports; payroll run sync writes month payroll fields).
//

import Foundation
import FirebaseFirestore

@MainActor
final class BooksService {
    static let shared = BooksService()

    private let db = Firestore.firestore()

    private init() {}

    private func monthRef(userId: String, locationId: String, monthId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("books")
            .document(monthId)
    }

    private func dayRef(userId: String, locationId: String, monthId: String, dayId: String) -> DocumentReference {
        monthRef(userId: userId, locationId: locationId, monthId: monthId)
            .collection("days")
            .document(dayId)
    }

    static func monthId(from date: Date, calendar: Calendar = .current) -> String {
        BooksDateIds.monthId(from: date, calendar: calendar)
    }

    static func dayId(from date: Date, calendar: Calendar = .current) -> String {
        BooksDateIds.dayId(from: date, calendar: calendar)
    }

    func listMonthIds(userId: String, locationId: String) async throws -> [String] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("books")
            .getDocuments()
        return snapshot.documents.map(\.documentID).sorted(by: >)
    }

    func loadMonth(userId: String, locationId: String, monthId: String) async throws -> BooksMonthPayload {
        let ref = monthRef(userId: userId, locationId: locationId, monthId: monthId)
        async let monthSnap = ref.getDocument()
        async let daysSnap = ref.collection("days").getDocuments()

        let monthDocument = try await monthSnap
        let daysDocuments = try await daysSnap

        let monthData = monthDocument.data() ?? [:]
        var daysById: [String: BooksDayDoc] = [:]
        for doc in daysDocuments.documents {
            daysById[doc.documentID] = BooksFirestoreParser.parseDay(dayId: doc.documentID, data: doc.data())
        }

        return BooksMonthPayload(
            monthId: monthId,
            month: BooksFirestoreParser.parseMonth(data: monthData),
            daysById: daysById
        )
    }

    func loadAllMonths(userId: String, locationId: String) async throws -> [BooksMonthPayload] {
        let monthIds = try await listMonthIds(userId: userId, locationId: locationId)
        var payloads: [BooksMonthPayload] = []
        payloads.reserveCapacity(monthIds.count)

        for monthId in monthIds {
            do {
                let payload = try await loadMonth(userId: userId, locationId: locationId, monthId: monthId)
                payloads.append(payload)
            } catch {
                continue
            }
        }
        return payloads
    }

    func loadDay(userId: String, locationId: String, monthId: String, dayId: String) async throws -> BooksDayDoc? {
        let snap = try await dayRef(userId: userId, locationId: locationId, monthId: monthId, dayId: dayId).getDocument()
        guard snap.exists, let data = snap.data() else { return nil }
        return BooksFirestoreParser.parseDay(dayId: dayId, data: data)
    }

    /// Merge-write month-level fields (preserves days subcollection and other month fields).
    func mergeMonthFields(
        userId: String,
        locationId: String,
        monthId: String,
        fields: [String: Any]
    ) async throws {
        let ref = monthRef(userId: userId, locationId: locationId, monthId: monthId)
        let snap = try await ref.getDocument()
        if snap.exists, snap.data()?["closed"] as? Bool == true {
            throw BooksServiceError.monthClosed
        }

        var payload = fields
        payload["updatedAt"] = FieldValue.serverTimestamp()
        try await ref.setData(payload, merge: true)
    }

    /// Push net pay from an iOS payroll run into Daily books for the pay-through month.
    func syncPayrollRunToBooks(
        userId: String,
        locationId: String,
        run: LocationPayrollRun,
        calendar: Calendar = .current
    ) async throws {
        let monthId = Self.monthId(from: run.periodEnd, calendar: calendar)
        let ref = monthRef(userId: userId, locationId: locationId, monthId: monthId)
        let snap = try await ref.getDocument()
        let existingData = snap.data() ?? BooksFirestoreEncoder.defaultMonthPayload()

        var mergedFields = BooksPayrollSync.mergedMonthPayrollFields(
            existingMonthData: existingData,
            run: run,
            calendar: calendar
        )
        if var syncs = mergedFields["payrollRunSyncs"] as? [String: [String: Any]],
           var record = syncs[run.id] {
            record["syncedAt"] = FieldValue.serverTimestamp()
            syncs[run.id] = record
            mergedFields["payrollRunSyncs"] = syncs
        }

        try await mergeMonthFields(
            userId: userId,
            locationId: locationId,
            monthId: monthId,
            fields: mergedFields
        )
    }
}

enum BooksServiceError: LocalizedError {
    case monthClosed

    var errorDescription: String? {
        switch self {
        case .monthClosed:
            return "Daily books for this month are closed. Reopen the month on web before syncing payroll."
        }
    }
}
