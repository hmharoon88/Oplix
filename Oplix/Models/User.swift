//
//  User.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct User: Identifiable, Codable {
    let id: String
    let username: String
    let role: UserRole
    var locationId: String? // Can be updated when employee is assigned to locations
    let managerUserId: String? // For employees: the manager who owns their location
    let createdAt: Date
    var organizationName: String? // Organization/company name for managers
    
    enum UserRole: String, Codable {
        case manager
        case employee
    }
}

