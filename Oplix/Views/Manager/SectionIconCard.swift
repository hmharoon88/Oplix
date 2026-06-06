//
//  SectionIconCard.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

/// iOS-Home-Screen-style icon tile used on `LocationDetailView`.
///
/// Renders as a free-floating squircle icon with a small label beneath
/// (no card chrome) so the section grid feels like the iPhone Home
/// Screen rather than a stack of buttons. Optional red badge sits in
/// the icon's upper-right corner, mirroring iOS app-icon notifications.
struct SectionIconCard: View {
    let icon: String
    let title: String
    let color: Color
    let count: Int
    /// Optional badge count for notifications (red dot in the icon's
    /// upper-right). `nil` or `0` hides the badge.
    let badgeCount: Int?
    /// When `true`, an extra count label is rendered beneath the title
    /// (e.g. "12 employees"). Off by default at the home screen scale.
    let showCount: Bool
    
    init(icon: String, title: String, color: Color, count: Int, badgeCount: Int? = nil, showCount: Bool = true) {
        self.icon = icon
        self.title = title
        self.color = color
        self.count = count
        self.badgeCount = badgeCount
        self.showCount = showCount
    }
    
    private static let iconSize: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 8) {
            iconSquircle
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            
            if showCount {
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    
    private var iconSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 3)
            
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
            
            if let badgeCount = badgeCount, badgeCount > 0 {
                // Red badge in upper-right, just like iOS app icons.
                Text("\(badgeCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.cloudWhite, lineWidth: 2)
                    )
                    .offset(x: Self.iconSize / 2 - 4, y: -Self.iconSize / 2 + 4)
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
    }
}

