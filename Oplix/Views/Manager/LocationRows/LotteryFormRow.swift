//
//  LotteryFormRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryFormRow: View {
    let form: LotteryForm
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Form #\(form.id.prefix(8))")
                .font(.headline)
            Text(form.notes)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(form.submittedAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .cloudCard()
    }
}

