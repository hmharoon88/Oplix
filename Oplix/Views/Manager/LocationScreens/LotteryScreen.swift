//
//  LotteryScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            List {
                ForEach(viewModel.lotteryForms) { form in
                    LotteryFormRow(form: form)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Lottery")
        .navigationBarTitleDisplayMode(.large)
    }
}

