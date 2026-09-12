import SwiftUI
import UniformTypeIdentifiers

struct NetworkingPreferencesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NetworkingPreferences()

    private let goals = [
        "Learn from peers", "Broaden industry perspective", "Navigate a career transition",
        "Explore entrepreneurship", "Develop leadership range", "Meet across companies"
    ]

    var body: some View {
        Form {
            Section {
                Picker("Maximum frequency", selection: $draft.frequency) {
                    ForEach(IntroductionFrequency.allCases) { Text($0.rawValue).tag($0) }
                }
            } header: { Text("Introduction rhythm") }
              footer: { Text("This is a maximum, not a quota. The app may send nothing when no introduction clears the quality threshold.") }

            Section("What relationships would be useful?") {
                ForEach(goals, id: \.self) { goal in
                    selectionRow(goal, selection: $draft.goals)
                }
            }

            Section {
                Picker("Relationship mix", selection: $draft.relationshipMix) {
                    Text("Mostly peers").tag("Mostly peers")
                    Text("Peers and adjacent leaders").tag("Peers and adjacent leaders")
                    Text("Cross-level perspective").tag("Cross-level perspective")
                }
                Toggle("Meet across companies", isOn: $draft.crossCompany)
                Toggle("Include adjacent industries", isOn: $draft.crossIndustry)
            } header: {
                Text("Perspective mix")
            } footer: {
                Text("Connections beyond your usual company or industry can expose you to useful patterns sooner. Quality and reciprocity still come first.")
            }
        }
        .ntScreenBackground()
        .navigationTitle("Introduction preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = store.networkingPreferences }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveNetworkingPreferences(draft)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(draft.goals.isEmpty)
            }
        }
    }
}

struct MeetingPreferencesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MeetingPreferences()
    private let formats = ["Coffee", "Walk", "Lunch"]

    var body: some View {
        Form {
            Section {
                ForEach(TodayAvailability.Area.allCases) { area in
                    selectionRow(area.rawValue, selected: draft.areas.contains(area)) {
                        toggle(area, in: &draft.areas)
                    }
                }
            } header: { Text("Usual work areas") }
              footer: { Text("Only broad overlap is shown inside an introduction. Live location is never tracked.") }

            Section("Meeting formats") {
                ForEach(formats, id: \.self) { format in
                    selectionRow(format, selection: $draft.formats)
                }
            }

            Section("Usually convenient") {
                ForEach(TodayAvailability.Window.allCases) { window in
                    selectionRow(window.rawValue, selected: draft.windows.contains(window)) {
                        toggle(window, in: &draft.windows)
                    }
                }
            }
        }
        .ntScreenBackground()
        .navigationTitle("Meeting preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = store.meetingPreferences }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveMeetingPreferences(draft)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(draft.areas.isEmpty || draft.formats.isEmpty || draft.windows.isEmpty)
            }
        }
    }
}

struct PrivacySafetyView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SafetyPreferences()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: NTSpacing.sm) {
                    Label("Inclusive by design", systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(NTColor.textPrimary)
                    Text("Gender is not collected or used to shape introductions. The professional network is never separated into gender-based pools.")
                        .font(.subheadline)
                        .foregroundStyle(NTColor.textSecondary)
                }
                .padding(.vertical, NTSpacing.xs)
            } header: { Text("Our approach") }
              footer: { Text("Safety is supported through verified membership, professional-only standards, reporting, blocking, and ending conversations.") }

            Section("Professional-only community") {
                rule("briefcase", "Keep introductions professional")
                rule("hand.raised", "No harassment, discrimination, or romantic solicitation")
                rule("eye.slash", "No unsolicited messages or searchable member directory")
            }

            Section("Blocked members") {
                if draft.blockedMembers.isEmpty {
                    Text("No blocked members").foregroundStyle(NTColor.textSecondary)
                } else {
                    ForEach(draft.blockedMembers, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Unblock") {
                                draft.blockedMembers.removeAll { $0 == name }
                                store.unblock(name)
                            }
                        }
                    }
                }
            }
        }
        .ntScreenBackground()
        .navigationTitle("Privacy and safety")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = store.safetyPreferences }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveSafetyPreferences(draft)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(NTColor.textPrimary)
    }
}

struct WorkVerificationView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                LabeledContent("Company", value: store.member.company)
                LabeledContent("Work email", value: store.verifiedWorkEmail)
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(NTColor.success)
            } footer: {
                Text("Verification confirms control of a company email. It does not imply employer endorsement or verify your self-provided title.")
            }

            Section("Changing companies") {
                Text("Your account, conversations, and connections remain yours. A new company must be verified before its badge appears.")
                    .foregroundStyle(NTColor.textSecondary)
                Button("Verify a new work email") {
                    store.presentInformation("Company reverification flow is ready for backend connection")
                }
            }
        }
        .ntScreenBackground()
        .navigationTitle("Work verification")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ResumeEnhancementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isChoosingResume = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NTSpacing.xl) {
                VStack(alignment: .leading, spacing: NTSpacing.sm) {
                    Text("Build a profile draft").font(.title2.weight(.semibold))
                    Text("Upload a résumé and AI will prefill factual professional context. You review every suggestion before it becomes part of your profile.")
                        .foregroundStyle(NTColor.textSecondary)
                }

                switch store.member.resumeStatus {
                case .notAdded:
                    NTPrivacyNote(text: "Your résumé is processed only to create your draft, then the file is deleted. Career goals and what you offer others are never invented for you.")
                    Button("Upload résumé") {
                        isChoosingResume = true
                    }
                    .buttonStyle(NTPrimaryButtonStyle())
                    Text("PDF only · 10 MB maximum")
                        .font(.footnote)
                        .foregroundStyle(NTColor.textSecondary)
                case .processing:
                    VStack(spacing: NTSpacing.md) {
                        ProgressView()
                        Text("Building your profile draft…").font(.headline)
                        Text("Your current profile remains unchanged.").font(.subheadline).foregroundStyle(NTColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(NTSpacing.xxl)
                    .ntSurface()
                case .uploaded:
                    VStack(alignment: .leading, spacing: NTSpacing.sm) {
                        Label("Uploaded privately", systemImage: "lock.doc.fill")
                            .font(.headline)
                            .foregroundStyle(NTColor.success)
                        Text("Your résumé is stored in your private account space. AI drafting will begin when the extraction service is configured.")
                            .foregroundStyle(NTColor.textSecondary)
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()
                case .ready(let suggestions):
                    VStack(alignment: .leading, spacing: NTSpacing.md) {
                        Label("Draft ready to review", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(NTColor.success)
                        if !suggestions.summary.isEmpty {
                            Text(suggestions.summary).foregroundStyle(NTColor.textSecondary)
                        }
                        if let roleScope = suggestions.roleScope {
                            Text(roleScope).font(.subheadline).foregroundStyle(NTColor.textSecondary)
                        }
                        NTPillFlow {
                            ForEach(suggestions.topics, id: \.self) { NTTopicPill(title: $0, selected: true) }
                        }
                        Text("AI can misread a résumé. Apply this draft, then verify it in Professional context.")
                            .font(.footnote)
                            .foregroundStyle(NTColor.textSecondary)
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()
                    Button("Use draft, then review") { store.applyResumeSuggestions(suggestions) }
                        .buttonStyle(NTPrimaryButtonStyle())
                case .applied:
                    VStack(alignment: .leading, spacing: NTSpacing.sm) {
                        Label("Draft added", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(NTColor.success)
                        Text("Review Professional context to confirm the imported details and add the goals only you can define.")
                            .foregroundStyle(NTColor.textSecondary)
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()
                }

                if !store.member.professionalHistory.isEmpty {
                    VStack(alignment: .leading, spacing: NTSpacing.md) {
                        Text("Professional history").font(.title3.weight(.semibold))
                        ForEach(store.member.professionalHistory) { item in
                            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                                Text(item.role).font(.headline)
                                Text("\(item.company) · \(item.period)").font(.subheadline).foregroundStyle(NTColor.textSecondary)
                            }
                            if item.id != store.member.professionalHistory.last?.id { Divider() }
                        }
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()
                }
            }
            .padding(NTSpacing.lg)
        }
        .ntScreenBackground()
        .navigationTitle("Résumé and experience")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isChoosingResume, allowedContentTypes: [.pdf]) { result in
            guard case .success(let fileURL) = result else { return }
            Task {
                let hasAccess = fileURL.startAccessingSecurityScopedResource()
                defer { if hasAccess { fileURL.stopAccessingSecurityScopedResource() } }
                await store.processResume(fileURL: fileURL)
            }
        }
    }
}

struct AccountSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmation: Confirmation?
    private enum Confirmation { case signOut, delete }

    var body: some View {
        List {
            Section {
                LabeledContent("Member", value: store.member.name)
                LabeledContent("Work email", value: store.verifiedWorkEmail)
            }
            Section {
                Button("Sign out") { confirmation = .signOut }
                Button("Delete account", role: .destructive) { confirmation = .delete }
            } footer: {
                Text("Deleting your account permanently removes your profile, conversations, connections, and private résumé records. This cannot be undone.")
            }
        }
        .ntScreenBackground()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            confirmation == .delete ? "Delete this account?" : "Sign out?",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
        ) {
            if confirmation == .delete {
                Button("Delete account", role: .destructive) { store.deleteAccount() }
            } else {
                Button("Sign out", role: .destructive) { store.signOut() }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        }
    }
}

private func selectionRow(_ title: String, selection: Binding<Set<String>>) -> some View {
    let selected = selection.wrappedValue.contains(title)
    return selectionRow(title, selected: selected) {
        if selected { selection.wrappedValue.remove(title) } else { selection.wrappedValue.insert(title) }
    }
}

private func selectionRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            Text(title).foregroundStyle(NTColor.textPrimary)
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? NTColor.accent : NTColor.textSecondary)
        }
    }
}

private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
    if set.contains(value) { set.remove(value) } else { set.insert(value) }
}
