//
//  BooksService.swift
//  Oplix
//
//  Read-only Firestore access for web Daily books.
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
}
