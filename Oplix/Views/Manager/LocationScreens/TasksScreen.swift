//
//  TasksScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

// Hub screen for the Tasks tile. Shows two large category cards — Recurring
// and Corrective — and pushes a TaskCategoryListScreen when tapped. All of
// the actual list management (add, edit, delete, multi-select) lives on the
// per-category screen.
struct TasksScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel

    private var recurringCount: Int {
        viewModel.tasks.filter { $0.frequency.isRecurring }.count
    }

    private var correctiveCount: Int {
        viewModel.tasks.filter { $0.frequency == .oneTime }.count
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink(
                        destination: TaskCategoryListScreen(viewModel: viewModel, category: .recurring)
                    ) {
                        categoryCard(category: .recurring, count: recurringCount)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(
                        destination: TaskCategoryListScreen(viewModel: viewModel, category: .corrective)
                    ) {
                        categoryCard(category: .corrective, count: correctiveCount)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func categoryCard(category: TaskCategory, count: Int) -> some View {
        HStack(spacing: 16) {
            // Tinted icon disc — same visual weight as the location dashboard tiles.
            ZStack {
                Circle()
                    .fill(category.tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: category.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(category.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(countText(count: count))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(category.tint)
                    .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private func countText(count: Int) -> String {
        if count == 0 { return "No tasks" }
        return "\(count) task\(count == 1 ? "" : "s")"
    }
}
