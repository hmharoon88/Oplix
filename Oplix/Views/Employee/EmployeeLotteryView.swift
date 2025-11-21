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
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.currentShift != nil {
                VStack(spacing: 20) {
                    LotteryFormView(viewModel: viewModel)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Active Shift")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("You need to clock in to submit lottery forms")
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
        }
    }
}

