import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.openURL) private var openURL
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    profileHero
                    contextCard
                    introductionCard
                    backgroundCard
                    membershipCard
                    accountCard
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.bottom, NTSpacing.xxxl)
            }
            .ntScreenBackground()
            .navigationTitle("Profile")
            .confirmationDialog("Restart the product demo?", isPresented: $showingResetConfirmation) {
                Button("Restart from Today") { store.resetDemo() }
                Button("Restart from onboarding", role: .destructive) { store.resetDemo(includeOnboarding: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears local demo progress on this device.")
            }
        }
    }

    private var profileHero: some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            NTProfessionalIdentity(profile: store.member)
            Text(store.member.roleScope)
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
            NTPillFlow(spacing: NTSpacing.xs) {
                ForEach(store.member.topics, id: \.self) { NTTopicPill(title: $0) }
            }
        }
        .padding(NTSpacing.lg)
        .ntSurface(radius: NTRadius.hero)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: NTSpacing.lg) {
            sectionHeading("Professional direction", "Where you are headed and the experience that could help you move forward.")
            contextPreview("briefcase", "Working on now", store.member.currentFocus)
            Divider()
            contextPreview("scope", "Working toward", store.member.professionalAmbition)
            Divider()
            contextPreview("arrow.up.right", "Looking to grow", store.member.growthInterest)
            Divider()
            contextPreview("lightbulb", "Can meaningfully share", store.member.contribution)
            NavigationLink {
                ProfessionalContextDetailView()
            } label: {
                HStack {
                    Text("Review and edit context").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NTColor.accentStrong)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            sectionHeading("How you want to connect", "Control your pace and meeting context without browsing people.")
            NavigationLink {
                NetworkingPreferencesView()
            } label: {
                settingsRow("slider.horizontal.3", "Introduction preferences", store.networkingPreferences.frequency.rawValue, showChevron: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            NavigationLink {
                MeetingPreferencesView()
            } label: {
                settingsRow("mappin.and.ellipse", "Meeting preferences", meetingSummary, showChevron: true)
            }
            .buttonStyle(.plain)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("Background enrichment", "Optional context can improve introductions while staying under your control.")
                .padding(.bottom, NTSpacing.sm)
            NavigationLink {
                ResumeEnhancementView()
            } label: {
                settingsRow("doc.text", "Résumé and experience", resumeSummary, showChevron: true)
            }
            .buttonStyle(.plain)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("Membership", "One free month, then a simple monthly membership.")
                .padding(.bottom, NTSpacing.sm)
            NavigationLink {
                MembershipView()
            } label: {
                settingsRow(
                    "leaf",
                    "network.to membership",
                    membershipSummary,
                    tint: store.membership.hasAccess || subscriptions.isEntitled ? NTColor.success : NTColor.accent,
                    showChevron: true
                )
            }
            .buttonStyle(.plain)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    /// Delivery preferences live in iPhone Settings. The row reflects the phone's status,
    /// presents the phone's dialog while it has never been asked, and otherwise opens Settings.
    private var notificationSubtitle: String {
        switch store.notificationAuthorization {
        case .unknown: "Managed in iPhone Settings"
        case .notDetermined: "Not set up yet"
        case .denied: "Off · Turn on in iPhone Settings"
        case .authorized: "On · Managed in iPhone Settings"
        }
    }

    private func handleNotificationsRow() {
        Task {
            await store.refreshNotificationAuthorization()
            if store.notificationAuthorization.canPrompt {
                await store.requestNotificationAuthorization()
            } else {
                openNotificationSettings()
            }
        }
    }

    private func openNotificationSettings() {
        let appStore = store
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            appStore.transientMessage = AppStore.notificationSettingsFallbackNotice
            return
        }
        openURL(url) { accepted in
            guard !accepted else { return }
            Task { @MainActor in appStore.transientMessage = AppStore.notificationSettingsFallbackNotice }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("Account and privacy", "Trust controls stay understandable and close at hand.")
                .padding(.bottom, NTSpacing.sm)
            NavigationLink {
                WorkVerificationView()
            } label: {
                settingsRow("checkmark.seal.fill", "Work email verified", "\(store.member.company) affiliation", tint: NTColor.success, showChevron: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            NavigationLink {
                PrivacySafetyView()
            } label: {
                settingsRow("lock.shield", "Privacy and safety", "Inclusive introductions, blocks, and community rules", showChevron: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            Button {
                handleNotificationsRow()
            } label: {
                settingsRow("bell", "Notifications", notificationSubtitle, showChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                store.notificationAuthorization.canPrompt
                    ? "Asks iPhone for permission to notify you"
                    : "Opens the native iPhone notification settings for network.to"
            )
            Divider().padding(.leading, 44)
            NavigationLink {
                AccountSettingsView()
            } label: {
                settingsRow("person.crop.circle", "Account", "Sign out or delete account", showChevron: true)
            }
            .buttonStyle(.plain)
            if !store.isUsingLiveBackend {
                Divider().padding(.leading, 44)
                Button(role: .destructive) { showingResetConfirmation = true } label: {
                    settingsRow("arrow.counterclockwise", "Restart product demo", "Clear local progress", tint: NTColor.destructive)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private var meetingSummary: String {
        let area = store.meetingPreferences.areas.first?.rawValue ?? "Add an area"
        let format = store.meetingPreferences.formats.sorted().first ?? "Add a format"
        return "\(area) · \(format)"
    }

    private var resumeSummary: String {
        switch store.member.resumeStatus {
        case .notAdded: "Optional and private"
        case .processing: "Processing privately"
        case .uploaded: "Uploaded privately"
        case .ready: "Suggestions ready to review"
        case .applied: "Draft applied—review context"
        }
    }

    private var membershipSummary: String {
        if subscriptions.isEntitled { return "Active · \(subscriptions.displayPrice) monthly through Apple" }
        return switch store.membership.state {
        case .notStarted: "Free month starts after setup"
        case .trial:
            store.membership.trialEndsAt.map { "Free through \($0.formatted(date: .abbreviated, time: .omitted))" }
                ?? "First month free"
        case .subscribed: "Active · renews monthly through Apple"
        case .expired: "New introductions paused"
        }
    }

    private func sectionHeading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.xxs) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(NTColor.textSecondary)
        }
    }

    private func contextPreview(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(NTColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(NTColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func settingsRow(
        _ symbol: String,
        _ title: String,
        _ detail: String,
        tint: Color = NTColor.accent,
        showChevron: Bool = false
    ) -> some View {
        HStack(spacing: NTSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(NTColor.textSecondary)
            }
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(NTColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct ProfessionalContextDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NTSpacing.xl) {
                contextSection("briefcase", "Your work now") {
                    labeledValue("Role scope", store.member.roleScope)
                    labeledValue("Current focus", store.member.currentFocus)
                    labeledValue("Experience", store.member.yearsExperience)
                }
                if !store.member.professionalHistory.isEmpty {
                    contextSection("clock.arrow.circlepath", "Professional background") {
                        ForEach(store.member.professionalHistory) { experience in
                            labeledValue(experience.period, "\(experience.role) · \(experience.company)")
                        }
                        if !store.member.education.isEmpty {
                            labeledValue("Education", store.member.education)
                        }
                    }
                }
                contextSection("arrow.up.right", "Where you’re growing") {
                    labeledValue("Professional direction", store.member.professionalAmbition)
                    topicFlow(store.member.growthAreas)
                    labeledValue("Perspective that would help now", store.member.growthInterest)
                }
                contextSection("lightbulb", "What you can share") {
                    topicFlow(store.member.contributionAreas)
                    labeledValue("Useful experience", store.member.contribution)
                    labeledValue("How you like to help", store.member.helpFormats.joined(separator: " · "))
                    labeledValue("Boundaries", store.member.contributionBoundaries)
                }
                NTPrivacyNote(text: "These professional details guide introductions. Your work email is never shown to another member.")
            }
            .padding(NTSpacing.lg)
        }
        .ntScreenBackground()
        .navigationTitle("Professional context")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            EditProfessionalContextView(profile: store.member)
        }
    }

    private func contextSection<Content: View>(
        _ symbol: String,
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            Label(title, systemImage: symbol).font(.title3.weight(.semibold))
            content()
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ntSurface()
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.xxs) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(NTColor.accent)
            Text(value).foregroundStyle(NTColor.textSecondary)
        }
    }

    private func topicFlow(_ topics: [String]) -> some View {
        NTPillFlow(spacing: NTSpacing.xs) {
            ForEach(topics, id: \.self) { NTTopicPill(title: $0) }
        }
    }
}

private struct EditProfessionalContextView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var role: String
    @State private var city: String
    @State private var roleScope: String
    @State private var currentFocus: String
    @State private var yearsExperience: String
    @State private var growthAreas: Set<String>
    @State private var professionalAmbition: String
    @State private var growthInterest: String
    @State private var contributionAreas: Set<String>
    @State private var helpFormats: Set<String>
    @State private var contribution: String
    @State private var boundaries: String

    private let experienceOptions = ["1–3 years", "4–6 years", "7–9 years", "10–15 years", "15+ years"]
    private let growthOptions = ["Applied AI products", "Executive communication", "Engineering leadership", "Platform strategy", "Product thinking", "Founder perspective", "Career transition", "Local tech ecosystem"]
    private let contributionOptions = ["Distributed systems", "AI infrastructure", "Developer tools", "Product strategy", "Engineering leadership", "Scaling teams", "Fundraising", "Go-to-market"]
    private let helpOptions = ["Compare approaches", "Review a challenge", "Share lessons learned", "Make a relevant introduction"]

    init(profile: ProfessionalProfile) {
        _name = State(initialValue: profile.name)
        _role = State(initialValue: profile.role)
        _city = State(initialValue: profile.city)
        _roleScope = State(initialValue: profile.roleScope)
        _currentFocus = State(initialValue: profile.currentFocus)
        _yearsExperience = State(initialValue: profile.yearsExperience)
        _growthAreas = State(initialValue: Set(profile.growthAreas))
        _professionalAmbition = State(initialValue: profile.professionalAmbition)
        _growthInterest = State(initialValue: profile.growthInterest)
        _contributionAreas = State(initialValue: Set(profile.contributionAreas))
        _helpFormats = State(initialValue: Set(profile.helpFormats))
        _contribution = State(initialValue: profile.contribution)
        _boundaries = State(initialValue: profile.contributionBoundaries)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Professional identity") {
                    TextField("Full name", text: $name)
                    TextField("Current role", text: $role)
                    TextField("City and region", text: $city)
                        .textContentType(.addressCity)
                    LabeledContent("Company", value: store.member.company)
                }
                Section("Your work") {
                    TextField("Role scope", text: $roleScope, axis: .vertical).lineLimit(3...6)
                    TextField("Current focus", text: $currentFocus, axis: .vertical).lineLimit(3...6)
                    Picker("Experience", selection: $yearsExperience) {
                        ForEach(experienceOptions, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Where you’re growing") {
                    ForEach(growthOptions, id: \.self) { option in
                        selectionButton(option, selection: $growthAreas, maximum: 4)
                    }
                    TextField("What do you want to achieve?", text: $professionalAmbition, axis: .vertical).lineLimit(3...6)
                    TextField("What perspective would help right now?", text: $growthInterest, axis: .vertical).lineLimit(3...6)
                }
                Section("What you can share") {
                    ForEach(contributionOptions, id: \.self) { option in
                        selectionButton(option, selection: $contributionAreas, maximum: 4)
                    }
                    TextField("Useful experience", text: $contribution, axis: .vertical).lineLimit(3...6)
                }
                Section("How you like to help") {
                    ForEach(helpOptions, id: \.self) { option in
                        selectionButton(option, selection: $helpFormats)
                    }
                    TextField("Helpful boundaries", text: $boundaries, axis: .vertical).lineLimit(2...5)
                }
            }
            .ntScreenBackground()
            .navigationTitle("Edit context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateMemberContext(
                            name: name,
                            role: role,
                            city: city,
                            roleScope: roleScope,
                            currentFocus: currentFocus,
                            yearsExperience: yearsExperience,
                            growthAreas: growthAreas.sorted(),
                            professionalAmbition: professionalAmbition,
                            growthInterest: growthInterest,
                            contributionAreas: contributionAreas.sorted(),
                            helpFormats: helpFormats.sorted(),
                            contribution: contribution,
                            contributionBoundaries: boundaries
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roleScope.count < 20 || currentFocus.count < 20 || growthAreas.isEmpty || professionalAmbition.count < 20 || growthInterest.count < 20 || contributionAreas.isEmpty || helpFormats.isEmpty || contribution.count < 20)
                }
            }
        }
    }

    private func selectionButton(
        _ option: String,
        selection: Binding<Set<String>>,
        maximum: Int? = nil
    ) -> some View {
        let selected = selection.wrappedValue.contains(option)
        return Button {
            if selected {
                selection.wrappedValue.remove(option)
            } else if maximum.map({ selection.wrappedValue.count < $0 }) ?? true {
                selection.wrappedValue.insert(option)
            }
        } label: {
            HStack {
                Text(option).foregroundStyle(NTColor.textPrimary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? NTColor.accent : NTColor.textSecondary)
            }
        }
        .disabled(!selected && maximum.map({ selection.wrappedValue.count >= $0 }) == true)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}
