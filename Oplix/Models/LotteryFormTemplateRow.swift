//
//  LotteryFormTemplateRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryFormTemplateRow: Identifiable, Codable {
    let id: String
    var gameNumber: String
    var value: String
    var tickets: String
    var beginningNumber: String
    var endingNumber: String
    var sold: String
    var dollar: String
    var books: String
    
    init(id: String = UUID().uuidString, gameNumber: String = "", value: String = "", tickets: String = "", beginningNumber: String = "", endingNumber: String = "", sold: String = "", dollar: String = "", books: String = "") {
        self.id = id
        self.gameNumber = gameNumber
        self.value = value
        self.tickets = tickets
        self.beginningNumber = beginningNumber
        self.endingNumber = endingNumber
        self.sold = sold
        self.dollar = dollar
        self.books = books
    }
}

