//
//  TaskStatusView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct TaskStatusView: View {
    let userId: String
    let location: Location
    @StateObject private var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    init(userId: String, location: Location) {
        self.userId = userId
        self.location = location
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: userId, locationId: location.id))
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading tasks...")
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Error Loading Tasks")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task {
                            await loadTasks()
                        }
                    }
                    .cloudButton()
                }
                .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Location Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text(location.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                Text(location.address)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cloudWhite)
                            .cornerRadius(12)
                            .padding(.horizontal)
                            
                            // Tasks List
                            if viewModel.tasks.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "checklist")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    Text("No tasks for this location")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Tasks Status")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .padding(.horizontal)
                                    
                                    ForEach(viewModel.tasks) { task in
                                        TaskStatusRow(task: task, employees: viewModel.employees)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        .navigationTitle("Task Status")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadTasks()
        }
    }
    
    private func loadTasks() async {
        isLoading = true
        errorMessage = nil
        print("🟢 TaskStatusView: Loading tasks for location \(location.name) (ID: \(location.id))")
        do {
            await viewModel.loadData()
            print("🟢 TaskStatusView: Loaded \(viewModel.tasks.count) tasks, \(viewModel.employees.count) employees")
            if let error = viewModel.errorMessage {
                print("🔴 TaskStatusView: Error from viewModel: \(error)")
                errorMessage = error
            }
        } catch {
            print("🔴 TaskStatusView: Exception during load: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct TaskStatusRow: View {
    let task: WorkTask
    let employees: [Employee]
    
    @State private var selectedImage: (url: String, employeeName: String, timestamp: Date)?
    
    private func getEmployeeName(employeeId: String) -> String {
        employees.first(where: { $0.id == employeeId })?.name ?? "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Task Description
            Text(task.description)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Show assigned employees
            if !task.assignedEmployeeIds.isEmpty {
                let assignedNames = task.assignedEmployeeIds.map { getEmployeeName(employeeId: $0) }.joined(separator: ", ")
                Text("Assigned to: \(assignedNames)")
                    .font(.caption)
                    .foregroundColor(.blue)
            } else {
                Text("Unassigned")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Show completion status per employee with photos
            if !task.employeeCompletions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(task.employeeCompletions.keys.sorted()), id: \.self) { employeeId in
                        if let completion = task.employeeCompletions[employeeId] {
                            TaskCompletionCard(
                                employeeName: getEmployeeName(employeeId: employeeId),
                                completion: completion,
                                onImageTap: {
                                    selectedImage = (url: completion.imageURL, employeeName: getEmployeeName(employeeId: employeeId), timestamp: completion.timestamp)
                                }
                            )
                        }
                    }
                }
                .padding(.top, 8)
            } else {
                HStack {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text("Not completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(item: Binding(
            get: { selectedImage.map { ImageData(url: $0.url, employeeName: $0.employeeName, timestamp: $0.timestamp) } },
            set: { _ in selectedImage = nil }
        )) { imageData in
            TaskImageView(imageURL: imageData.url, timestamp: imageData.timestamp, employeeName: imageData.employeeName)
        }
    }
}

struct TaskCompletionCard: View {
    let employeeName: String
    let completion: TaskCompletion
    let onImageTap: () -> Void
    
    @State private var previewImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        HStack(spacing: 12) {
            // Preview Image
            Button(action: onImageTap) {
                Group {
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if isLoading {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView().scaleEffect(0.8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .frame(width: 80, height: 80)
                .cornerRadius(8)
                .clipped()
            }
            
            // Employee Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Completed by \(employeeName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                Text(completion.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(completion.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Tap photo to view full size")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .task {
            await loadPreviewImage()
        }
    }
    
    private func loadPreviewImage() async {
        guard let url = URL(string: completion.imageURL) else {
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    previewImage = image
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            print("Failed to load preview image: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

struct ImageData: Identifiable {
    let id = UUID()
    let url: String
    let employeeName: String
    let timestamp: Date
}

#Preview {
    TaskStatusView(
        userId: "test-user",
        location: Location(
            id: "test-location",
            name: "Test Location",
            address: "123 Test St",
            managerId: "test-manager",
            employees: [],
            tasks: [],
            lotteryForms: []
        )
    )
}

