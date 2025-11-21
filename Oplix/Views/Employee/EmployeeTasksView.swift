//
//  EmployeeTasksView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeTasksView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @State private var taskToComplete: WorkTask?
    @State private var showingImageCapture = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.tasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checklist")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.darkGray)
                            Text("No tasks assigned")
                                .font(.subheadline)
                                .foregroundColor(Theme.darkGray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let employee = viewModel.employee {
                        ForEach(viewModel.tasks) { task in
                            let completeAction: () -> Void = {
                                taskToComplete = task
                                showingImageCapture = true
                            }
                            TaskCard(
                                task: task,
                                employee: employee,
                                onComplete: completeAction
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Tasks")
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
        .sheet(item: $taskToComplete) { task in
            TaskImageCaptureView(
                task: task,
                onImageCaptured: { imageData in
                    Task { @MainActor in
                        await viewModel.completeTask(task, imageData: imageData)
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        showingImageCapture = false
                        taskToComplete = nil
                    }
                },
                onCancel: {
                    showingImageCapture = false
                    taskToComplete = nil
                }
            )
        }
    }
}

