//
//  Location.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Location: Identifiable, Codable {
    let id: String
    let name: String
    let address: String
    let managerId: String // Manager who owns this location
    var employees: [String] // Employee IDs
    var tasks: [String] // Task IDs
    var lotteryForms: [String] // LotteryForm IDs
}

