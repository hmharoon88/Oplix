//
//  LotteryTodayLocationCard.swift
//  Oplix
//
//  "Recent Lottery" card on the employee + supervisor home screen.
//  Shows the over/short readout for the 3 most recent lottery shifts
//  at the active location (across all terminals). Pure derivation from
//  data EmployeeHomeViewModel already loads (`recentLotteryForms`) — no
//  extra Firestore calls.
//
//  Why "last 3" instead of "today only": the home screen needs to be
//  useful even before the day's first close-out. A rolling history is
//  also a quicker pulse on whether the location's lottery shifts are
//  trending over, short, or even.
//

import SwiftUI

struct LotteryTodayLocationCard: View {
    let forms: [LotteryForm]
    let locationName: String
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT LOTTERY")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()
                Text(locationName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(forms.enumerated()), id: \.element.id) { idx, form in
                    shiftRow(form)
                    if idx < forms.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .oplixCard()
        }
        .padding(.horizontal)
    }
    
    // MARK: - Row
    
    private func shiftRow(_ form: LotteryForm) -> some View {
        let summary = form.shiftSummary
        let sold = summary?.totalSoldAmount ?? 0
        let overShort = summary?.overShort
        
        return HStack(spacing: 12) {
            // Per-shift icon — consistent with the manager-side lottery
            // card so the visual language stays the same across roles.
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "ticket.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(relativeDateLabel(form.submittedAt))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    // Terminal chip — quietly renders only when the shift
                    // is tagged with a terminal number (i.e. the location
                    // uses multi-terminal lottery). Single-terminal sites
                    // get a clean row without a "Terminal 1" label.
                    if let terminal = form.terminalNumber {
                        Text("T\(terminal)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.cloudBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.cloudBlue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text("\(formatTime(form.submittedAt)) · \(formatCurrency(sold)) sold")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            overShortPill(value: overShort ?? 0, hasData: overShort != nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Pill
    
    @ViewBuilder
    private func overShortPill(value: Double, hasData: Bool) -> some View {
        let (text, color, icon): (String, Color, String?) = {
            guard hasData else { return ("—", .gray, nil) }
            if abs(value) < 0.005 { return ("Even", .blue, "equal") }
            if value > 0 { return ("+\(formatCurrency(value))", .green, "arrow.up") }
            return ("-\(formatCurrency(abs(value)))", .red, "arrow.down")
        }()
        
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(text)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    // MARK: - Date helpers
    
    /// "Today" / "Yesterday" / weekday for the current week, otherwise
    /// "MMM d". Keeps the row label scannable and short.
    private func relativeDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let now = Date()
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days > 0, days < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
