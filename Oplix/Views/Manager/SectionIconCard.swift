//
//  SectionIconCard.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct SectionIconCard: View {
    let icon: String
    let title: String
    let color: Color
    let count: Int
    let badgeCount: Int? // Optional badge count for notifications
    let showCount: Bool // Whether to show the count number
    
    init(icon: String, title: String, color: Color, count: Int, badgeCount: Int? = nil, showCount: Bool = true) {
        self.icon = icon
        self.title = title
        self.color = color
        self.count = count
        self.badgeCount = badgeCount
        self.showCount = showCount
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(color)
                    .cornerRadius(20)
                
                // Badge indicator
                if let badgeCount = badgeCount, badgeCount > 0 {
                    Circle()
                        .fill(Color.orange) // Use orange for better visibility on red icons
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("\(badgeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 30, y: -30)
                }
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
            
            if showCount {
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

