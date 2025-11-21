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
}

