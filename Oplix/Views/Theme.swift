//
//  Theme.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct Theme {
    static let cloudBlue = Color(red: 0.3, green: 0.7, blue: 1.0)
    static let sunshineYellow = Color(red: 1.0, green: 0.85, blue: 0.3)
    static let softGray = Color(red: 0.9, green: 0.9, blue: 0.92)
    static let cloudWhite = Color.white
    static let skyBlue = Color(red: 0.5, green: 0.8, blue: 1.0)
    static let darkGray = Color(red: 0.4, green: 0.4, blue: 0.4) // High contrast dark gray for better visibility
    
    static let primaryGradient = LinearGradient(
        colors: [skyBlue, cloudBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let secondaryGradient = LinearGradient(
        colors: [cloudWhite, softGray],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    func cloudCard() -> some View {
        self
            .background(Theme.cloudWhite)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    func cloudButton(backgroundColor: Color = Theme.cloudBlue) -> some View {
        self
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(color: backgroundColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

