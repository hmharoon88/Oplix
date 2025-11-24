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
    
    init(locationId: String, rows: [LotteryFormTemplateRow] = [], lastUpdated: Date = Date()) {
        self.locationId = locationId
        self.rows = rows
        self.lastUpdated = lastUpdated
    }
}

