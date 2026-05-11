//
//  LotteryForm.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryForm: Identifiable, Codable {
    let id: String
    let locationId: String
    let shiftId: String
    let formData: [String: String]
    let notes: String
    let submittedAt: Date
    var shiftSummary: ShiftSummaryData?
    
    init(id: String, locationId: String, shiftId: String, formData: [String: String], notes: String, submittedAt: Date, shiftSummary: ShiftSummaryData? = nil) {
        self.id = id
        self.locationId = locationId
        self.shiftId = shiftId
        self.formData = formData
        self.notes = notes
        self.submittedAt = submittedAt
        self.shiftSummary = shiftSummary
    }
}

struct ShiftSummaryData: Codable {
    let totalSold: Int
    let totalDollars: Int
    let totalBooks: Int
    let instantTotal: Double
    let onlineTotal: Double
    let totalSoldAmount: Double
    let registerCash: Double
    let totalCash: Double
    let onlineCashes: Double
    let instantCashes: Double
    let totalCashes: Double
    let cashInBag: Double
    let cashInBagNet: Double
    var overShort: Double? // Optional - entered by employee in shift summary
}

