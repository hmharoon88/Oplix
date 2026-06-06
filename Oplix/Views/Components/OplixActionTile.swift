//
//  OplixActionTile.swift
//  Oplix
//
//  Shared "tap-to-go-somewhere" tile used across the app for any
//  navigation row (employee/supervisor home tab buttons, supervisor
//  controls, etc). One canonical size + visual language so every list
//  of nav rows looks the same regardless of which screen it's on.
//
//  Use this instead of bespoke per-screen card structs.
//

import SwiftUI

struct OplixActionTile: View {
    let icon: String
    let title: String
    let color: Color
    /// Defaults to `true`. When `false`, the tile dims and the icon
    /// background goes grey — used by callers that gate the action
    /// on some condition (e.g. Register Data only enabled while
    /// clocked in).
    var isEnabled: Bool = true
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? color : Color.gray)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isEnabled ? .black : Theme.darkGray)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.darkGray.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(Theme.cloudWhite)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}
