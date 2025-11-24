//
//  LotteryScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var showingCustomization = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Customization Placeholder
                    Button(action: {
                        showingCustomization = true
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 50))
                                .foregroundColor(Theme.cloudBlue)
                            
                            Text("Customization")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text("Configure lottery form template")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(Theme.cloudWhite)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    
                    // Previous Shifts Placeholder
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 50))
                            .foregroundColor(Theme.cloudBlue)
                        
                        Text("Previous Shifts")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text("Previous lottery shift data coming soon")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Theme.cloudWhite)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .padding()
            }
        }
        .navigationTitle("Lottery")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showingCustomization) {
            LotteryCustomizationView(viewModel: viewModel)
        }
    }
}

