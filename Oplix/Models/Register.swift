//
//  Register.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Register: Identifiable, Codable, Equatable {
    let id: String
    var cashSale: Double?
    var cashInHand: Double?
    var cashExpense: Double? // Total cash expense (for backward compatibility)
    var cashExpenseDescription: String? // First description (for backward compatibility)
    var cashExpenseDescriptions: [String]? // Multiple cash expense descriptions
    var cashExpenseAmounts: [Double]? // Multiple cash expense amounts
    var overShort: Double?
    var creditCard: Double?
    var fuelSaleGallons: Double?
    var fuelSaleDollars: Double?
    
    init(id: String = UUID().uuidString, cashSale: Double? = nil, cashInHand: Double? = nil, cashExpense: Double? = nil, cashExpenseDescription: String? = nil, cashExpenseDescriptions: [String]? = nil, cashExpenseAmounts: [Double]? = nil, overShort: Double? = nil, creditCard: Double? = nil, fuelSaleGallons: Double? = nil, fuelSaleDollars: Double? = nil) {
        self.id = id
        self.cashSale = cashSale
        self.cashInHand = cashInHand
        self.cashExpense = cashExpense
        self.cashExpenseDescription = cashExpenseDescription
        self.cashExpenseDescriptions = cashExpenseDescriptions
        self.cashExpenseAmounts = cashExpenseAmounts
        self.overShort = overShort
        self.creditCard = creditCard
        self.fuelSaleGallons = fuelSaleGallons
        self.fuelSaleDollars = fuelSaleDollars
    }
}

