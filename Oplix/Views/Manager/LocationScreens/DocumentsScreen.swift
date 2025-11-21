//
//  DocumentsScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct DocumentsScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.indigo)
                
                Text("Documents")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Document management coming soon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        DocumentsScreen(viewModel: LocationDetailViewModel(userId: "test-user", locationId: "test-location"))
    }
}

