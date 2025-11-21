//
//  TaskCheckView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct TaskCheckView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ManagerDashboardViewModel()
    @State private var selectedLocation: Location?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                        Text("Task Check")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),
                                Color(red: 0.15, green: 0.4, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    
                    // Content Area
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    } else if viewModel.locations.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No locations yet")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                                Button(action: {
                                    print("🟡 TaskCheck: Tapped location \(location.name) (ID: \(location.id))")
                                    selectedLocation = location
                                    print("🟡 TaskCheck: selectedLocation set to \(selectedLocation?.name ?? "nil")")
                                }) {
                                    LocationRow(
                                        location: location,
                                        index: index,
                                        userId: authViewModel.currentUser?.id
                                    )
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    
                    // Colored Footer
                    HStack {
                        Spacer()
                        Text("© 2025 Oplix")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),
                                Color(red: 0.15, green: 0.4, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $selectedLocation) { location in
                if let userId = authViewModel.currentUser?.id {
                    NavigationStack {
                        TaskStatusView(userId: userId, location: location)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {
                                        selectedLocation = nil
                                    }
                                }
                            }
                    }
                }
            }
            .task {
                if let userId = authViewModel.currentUser?.id {
                    viewModel.userId = userId
                    await viewModel.loadLocations()
                    viewModel.startObservingLocations()
                }
            }
        }
    }
}

#Preview {
    TaskCheckView()
        .environmentObject(AuthViewModel())
}

