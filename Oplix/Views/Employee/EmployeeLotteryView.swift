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
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = true
    @State private var showingLotterySelection = false

    /// Whether *any* terminal at this location has rows configured.
    /// Multi-terminal locations only show the empty state when no
    /// terminal at all is set up — otherwise the employee can pick
    /// the configured terminals from the close-out sheet.
    private var hasUsableLotteryForm: Bool {
        if viewModel.hasMultipleLotteryTerminals {
            return viewModel.lotteryTemplates.values.contains { !$0.rows.isEmpty }
        }
        if let template = viewModel.lotteryTemplate {
            return !template.rows.isEmpty
        }
        return false
    }

    private var isSupervisor: Bool {
        authViewModel.currentUser?.role == .supervisor
    }
    
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
            } else if hasUsableLotteryForm {
                // Show selection view first (supervisors also get Pack inventory there)
                LotterySelectionView(viewModel: viewModel, showsPackInventory: isSupervisor)
            } else {
                VStack(spacing: 20) {
                    if isSupervisor,
                       let employee = viewModel.employee,
                       let location = viewModel.location {
                        NavigationLink {
                            LotteryPackInventoryView(
                                managerUserId: employee.managerUserId,
                                location: location
                            )
                        } label: {
                            LotterySelectionCard(
                                title: "Pack inventory",
                                subtitle: "Assign, return, and move packs",
                                icon: "shippingbox.fill",
                                color: .orange,
                                isEnabled: true
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.loadLotteryTemplate() }
            }
        }
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

