//
//  Theme.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct Theme {
    // Use explicit sRGB color space for consistent colors across devices
    static let cloudBlue = Color(.sRGB, red: 0.3, green: 0.7, blue: 1.0, opacity: 1.0)
    static let sunshineYellow = Color(.sRGB, red: 1.0, green: 0.85, blue: 0.3, opacity: 1.0)
    static let softGray = Color(.sRGB, red: 0.9, green: 0.9, blue: 0.92, opacity: 1.0)
    static let cloudWhite = Color(.sRGB, red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
    static let skyBlue = Color(.sRGB, red: 0.5, green: 0.8, blue: 1.0, opacity: 1.0)
    static let darkGray = Color(.sRGB, red: 0.4, green: 0.4, blue: 0.4, opacity: 1.0) // High contrast dark gray for better visibility
    
    // System color replacements with explicit colors
    static let systemBlue = Color(.sRGB, red: 0.0, green: 0.478, blue: 1.0, opacity: 1.0)
    static let systemGreen = Color(.sRGB, red: 0.196, green: 0.804, blue: 0.196, opacity: 1.0)
    static let systemRed = Color(.sRGB, red: 1.0, green: 0.231, blue: 0.188, opacity: 1.0)
    static let systemOrange = Color(.sRGB, red: 1.0, green: 0.584, blue: 0.0, opacity: 1.0)
    static let systemPurple = Color(.sRGB, red: 0.686, green: 0.322, blue: 0.871, opacity: 1.0)
    static let systemIndigo = Color(.sRGB, red: 0.345, green: 0.337, blue: 0.839, opacity: 1.0)
    static let systemTeal = Color(.sRGB, red: 0.204, green: 0.780, blue: 0.780, opacity: 1.0)
    
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

