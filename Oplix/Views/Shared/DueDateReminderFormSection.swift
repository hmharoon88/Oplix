//
//  DueDateReminderFormSection.swift
//  Oplix
//

import SwiftUI

/// Reusable reminder controls shown when an item has a due / expiry date.
struct DueDateReminderFormSection: View {
    @Binding var reminder: DueDateReminder

    var body: some View {
        Section {
            Toggle("Remind me", isOn: $reminder.enabled)
            if reminder.enabled {
                Picker("When", selection: $reminder.daysBefore) {
                    ForEach(DueDateReminder.daysBeforeOptions, id: \.self) { days in
                        Text(DueDateReminder.label(forDaysBefore: days)).tag(days)
                    }
                }
                Toggle("Push notification", isOn: $reminder.push)
            }
        } header: {
            Text("Reminder")
        } footer: {
            if reminder.enabled {
                Text("You'll get a push on the selected day if push notifications are enabled in Settings.")
            }
        }
    }
}
