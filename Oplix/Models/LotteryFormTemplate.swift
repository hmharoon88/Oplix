//
//  LotteryFormTemplate.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryFormTemplateRow: Identifiable, Codable {
    let id: String
    var values: [String] // 8 values corresponding to the 8 columns
    
    init(id: String = UUID().uuidString, values: [String] = Array(repeating: "", count: 8)) {
        self.id = id
        self.values = values.count == 8 ? values : Array(repeating: "", count: 8)
    }
}

struct LotteryFormTemplate: Identifiable, Codable {
    let id: String
    let locationId: String
    var columnHeaders: [String] // 8 column headers
    var rows: [LotteryFormTemplateRow] // Rows of data
    
    enum CodingKeys: String, CodingKey {
        case id
        case locationId
        case columnHeaders
        case rows
    }
    
    init(id: String = UUID().uuidString, locationId: String, columnHeaders: [String] = [], rows: [LotteryFormTemplateRow] = []) {
        self.id = id
        self.locationId = locationId
        self.columnHeaders = columnHeaders.isEmpty ? ["Column 1", "Column 2", "Column 3", "Column 4", "Column 5", "Column 6", "Column 7", "Column 8"] : columnHeaders
        self.rows = rows
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        locationId = try container.decode(String.self, forKey: .locationId)
        columnHeaders = try container.decode([String].self, forKey: .columnHeaders)
        rows = try container.decode([LotteryFormTemplateRow].self, forKey: .rows)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(locationId, forKey: .locationId)
        try container.encode(columnHeaders, forKey: .columnHeaders)
        try container.encode(rows, forKey: .rows)
    }
}

