import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @State private var showingAvailability = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    greeting
                    if store.isRefreshing {
                        ProgressView("Refreshing your context…")
                            .font(.subheadline)
                            .foregroundStyle(NTColor.textSecondary)
                    }
                    availabilityBanner
                    phaseContent
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.bottom, NTSpacing.xxxl)
            }
            .ntScreenBackground()
            .navigationTitle("Today")
            .refreshable { await store.refreshFromBackend() }
            .sheet(isPresented: $showingAvailability) {
                AvailableTodaySheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var greetingText: String {
        let firstName = store.member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return firstName.isEmpty ? daypartGreeting : "\(daypartGreeting), \(firstName)"
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xs) {
            Text(greetingText)
                .font(.headline)
            Text("One worthwhile conversation is enough.")
                .font(.subheadline)
                .foregroundStyle(NTColor.textSecondary)
        }
        .padding(.top, NTSpacing.xs)
    }

    @ViewBuilder
    private var availabilityBanner: some View {
        if let availability = store.activeAvailability {
            HStack(alignment: .top, spacing: NTSpacing.sm) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(NTColor.meeting)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                    Text("Available today").font(.headline)
                    Text("\(availability.area.rawValue) · \(availability.window.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(NTColor.textSecondary)
                    Text("Expires at \(availability.expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NTColor.textSecondary)
                }
                Spacer()
                Button("Edit") { showingAvailability = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(NTSpacing.md)
            .background(NTColor.meeting.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .ready:
            introductionReady
        case .waiting:
            NavigationLink {
                IntroductionFlowView()
            } label: {
                statusCard(symbol: "hourglass", title: "Your response is private", detail: "We’ll let you know only if the interest is mutual.")
            }
            .buttonStyle(.plain)
        case .mutual:
            NavigationLink {
                IntroductionFlowView()
            } label: {
                statusCard(symbol: "person.2.fill", title: "You both want to meet", detail: "Say hello and find a simple time for coffee.")
            }
            .buttonStyle(.plain)
        case .conversation:
            if case .planned(let detail) = store.conversation?.meetupStatus {
                upcomingMeetup(detail)
            } else {
                Button { store.selectedTab = .messages } label: {
                    statusCard(symbol: "cup.and.saucer.fill", title: "Keep the momentum human", detail: "Your conversation with \(activePersonName) is open in Messages.")
                }
                .buttonStyle(.plain)
            }
        case .feedback:
            Button { store.selectedTab = .messages } label: {
                statusCard(symbol: "checkmark.bubble", title: "How did the coffee go?", detail: "Share private feedback when you’re ready.")
            }
            .buttonStyle(.plain)
        case .connected:
            statusCard(symbol: "checkmark.circle.fill", title: "A new connection", detail: "\(activePersonName) is now in Connections, along with the context that brought you together.")
        case .passed:
            passedState
        case .searching:
            if store.membership.hasAccess || subscriptions.isEntitled {
                searchingState
            } else {
                MembershipGateView()
            }
        case .notMutual:
            nonMutualState
        }
    }

    private var nonMutualState: some View {
        VStack(spacing: NTSpacing.lg) {
            NTEmptyState(
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                title: "This introduction didn’t work out",
                message: "Responses stay private, so there’s no personal rejection to interpret. We’ll keep looking for someone worthwhile."
            )
            Button("Continue") { store.lookAgain() }
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(NTSpacing.lg)
        .ntSurface(radius: NTRadius.hero)
    }

    private func upcomingMeetup(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            NTStatusPill(text: "UPCOMING COFFEE", symbol: "calendar.badge.checkmark", tint: NTColor.meeting)
            Text("You’re meeting \(activePersonName)").font(.title2.weight(.semibold))
            Label(detail, systemImage: "mappin.and.ellipse")
                .foregroundStyle(NTColor.textSecondary)
            Button("Open conversation") { store.selectedTab = .messages }
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(NTSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ntSurface(radius: NTRadius.hero)
    }

    private var activePersonName: String {
        store.conversation?.person.firstName
            ?? store.connections.first?.person.firstName
            ?? "your connection"
    }

    private var daypartGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var introductionReady: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            VStack(alignment: .leading, spacing: NTSpacing.md) {
                Label("NEW INTRODUCTION", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NTColor.accent)
                Text("We found someone you might want to meet.")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Their experience connects to where you want to go, yours connects to their journey, and you’re both ready to meet in your city.")
                    .font(.body)
                    .foregroundStyle(NTColor.textSecondary)
                NavigationLink {
                    IntroductionFlowView()
                } label: {
                    Text("View introduction")
                }
                .buttonStyle(NTPrimaryButtonStyle())
                .accessibilityHint("Opens one professional introduction")
            }
            .padding(NTSpacing.xl)
            .ntSurface(radius: NTRadius.hero)

            Button {
                showingAvailability = true
            } label: {
                Label("Available for coffee today?", systemImage: "cup.and.saucer")
            }
            .buttonStyle(NTSecondaryButtonStyle())
        }
    }

    private var searchingState: some View {
        VStack(spacing: NTSpacing.lg) {
            NTEmptyState(
                symbol: "sparkle.magnifyingglass",
                title: "Looking beyond your usual circle",
                message: "We’re considering professional direction, reciprocal value, and perspectives across companies and industries. We won’t send an introduction just to fill the space."
            )
            Button("Available for coffee today") { showingAvailability = true }
                .buttonStyle(NTSecondaryButtonStyle())
        }
        .padding(NTSpacing.lg)
        .ntSurface(radius: NTRadius.hero)
    }

    private var passedState: some View {
        VStack(spacing: NTSpacing.lg) {
            NTEmptyState(
                symbol: "hand.thumbsup",
                title: "Thanks for deciding",
                message: "Your pass is private. We’ll keep looking for someone worthwhile."
            )
            Button("Return to Today") { store.lookAgain() }
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(NTSpacing.lg)
        .ntSurface(radius: NTRadius.hero)
    }

    private func statusCard(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(NTColor.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xs) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).foregroundStyle(NTColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(NTColor.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct AvailableTodaySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var area = TodayAvailability.Area.downtown
    @State private var window = TodayAvailability.Window.afterWork

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Area", selection: $area) {
                        ForEach(TodayAvailability.Area.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Time", selection: $window) {
                        ForEach(TodayAvailability.Window.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: {
                    Text("Broad meeting context")
                } footer: {
                    Text("This expires automatically tonight. Your live location is never shared.")
                }

                if store.activeAvailability != nil {
                    Button("Turn off availability", role: .destructive) {
                        store.clearAvailability()
                        dismiss()
                    }
                }
            }
            .ntScreenBackground()
            .navigationTitle("Available today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setAvailability(area: area, window: window)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
