//
//  EmployeeLotteryView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeLotteryView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @State private var isLoading = true
    @State private var showingLotterySelection = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading lottery form...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else if let template = viewModel.lotteryTemplate, !template.rows.isEmpty {
                // Show selection view first
                LotterySelectionView(viewModel: viewModel)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Lottery Form")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("Manager has not set up the lottery form template yet")
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Lottery")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Configure navigation bar appearance for visible text
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            
            // Load lottery template
            Task {
                await viewModel.loadLotteryTemplate()
                isLoading = false
            }
        }
    }
}

