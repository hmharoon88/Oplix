//
//  LotteryFormTemplate.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryFormTemplate: Codable {
    let locationId: String
    var rows: [LotteryFormTemplateRow]
    let lastUpdated: Date
    var lotteryRegisterAmount: String
    var reverseOrder: Bool
    
    init(locationId: String, rows: [LotteryFormTemplateRow] = [], lastUpdated: Date = Date(), lotteryRegisterAmount: String = "", reverseOrder: Bool = false) {
        self.locationId = locationId
        self.rows = rows
        self.lastUpdated = lastUpdated
        self.lotteryRegisterAmount = lotteryRegisterAmount
        self.reverseOrder = reverseOrder
    }
}

