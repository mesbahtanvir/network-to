import SwiftUI

struct MeetupPlannerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var area = TodayAvailability.Area.downtown
    @State private var note = "Near Union Station"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("When", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Picker("Broad area", selection: $area) {
                        ForEach(TodayAvailability.Area.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Optional place suggestion", text: $note)
                } header: { Text("A simple proposal") }
                  footer: { Text("This sends meeting context into your existing conversation. It does not make a reservation or add a calendar event.") }
            }
            .ntScreenBackground()
            .navigationTitle("Propose coffee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let time = date.formatted(date: .abbreviated, time: .shortened)
                        let place = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.planMeetup(detail: "\(time) · \(place.isEmpty ? area.rawValue : place)")
                        store.sendMessage("Would \(time) work for coffee? \(place.isEmpty ? area.rawValue : place).")
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ReportMemberView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let person: ProfessionalProfile
    @State private var category: ReportCategory?
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your report is private. \(person.name) will not be told who submitted it.")
                        .foregroundStyle(NTColor.textSecondary)
                }
                Section("What happened?") {
                    ForEach(ReportCategory.allCases) { item in
                        Button {
                            category = item
                        } label: {
                            HStack {
                                Text(item.rawValue).foregroundStyle(NTColor.textPrimary)
                                Spacer()
                                if category == item { Image(systemName: "checkmark").foregroundStyle(NTColor.accent) }
                            }
                        }
                    }
                }
                Section("Details (optional)") {
                    TextField("Add context for the safety team", text: $note, axis: .vertical).lineLimit(3...7)
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(NTColor.destructive) }
                }
            }
            .ntScreenBackground()
            .navigationTitle("Report member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        guard let category else { return }
                        isSubmitting = true
                        Task {
                            do {
                                try await store.submitReport(category: category, note: note)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                isSubmitting = false
                            }
                        }
                    }
                    .disabled(category == nil || isSubmitting)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
