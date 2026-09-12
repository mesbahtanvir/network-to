import StoreKit
import SwiftUI

struct MembershipView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @State private var showingTerms = false
    @State private var showingPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NTSpacing.xl) {
                hero
                includedCard
                billingCard
                actions
            }
            .padding(.horizontal, NTSpacing.lg)
            .padding(.bottom, NTSpacing.xxxl)
        }
        .ntScreenBackground()
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Membership", isPresented: errorPresented) {
            Button("OK") { subscriptions.errorMessage = nil }
        } message: {
            Text(subscriptions.errorMessage ?? "")
        }
        .sheet(isPresented: $showingTerms) { MembershipLegalView(kind: .terms) }
        .sheet(isPresented: $showingPrivacy) { MembershipLegalView(kind: .privacy) }
        .task { await subscriptions.prepare() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            Image(systemName: statusSymbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(NTColor.accentStrong)
                .accessibilityHidden(true)
            Text(statusTitle)
                .font(.largeTitle.weight(.semibold))
            Text(statusDetail)
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let date = store.membership.renewalOrEndDate {
                NTStatusPill(
                    text: statusDateLabel(date).uppercased(),
                    symbol: "calendar",
                    tint: store.membership.hasAccess ? NTColor.success : NTColor.textSecondary
                )
            }
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ntSurface(radius: NTRadius.hero)
    }

    private var includedCard: some View {
        VStack(alignment: .leading, spacing: NTSpacing.lg) {
            Text("A small membership for better professional connections")
                .font(.title3.weight(.semibold))
            benefit("person.2", "Thoughtful introductions", "Matches shaped by professional direction and useful experience.")
            benefit("building.2", "Beyond your usual circle", "Cross-company and cross-industry perspective without a people marketplace.")
            benefit("cup.and.saucer", "Designed to become a real conversation", "Private interest, messaging, and simple coffee coordination.")
            benefit("lock", "Your relationships remain yours", "Existing conversations and connections stay available if membership ends.")
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private var billingCard: some View {
        VStack(alignment: .leading, spacing: NTSpacing.sm) {
            Text("Monthly membership").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(subscriptions.displayPrice).font(.title.weight(.semibold))
                Text("per month").foregroundStyle(NTColor.textSecondary)
            }
            Text("Billed monthly through Apple and renews automatically until cancelled. Cancel anytime in iPhone Settings.")
                .font(.subheadline)
                .foregroundStyle(NTColor.textSecondary)
            if store.membership.state == .trial {
                Text("Your first month is already free—no payment method was required to begin.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NTColor.accentStrong)
            }
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private var actions: some View {
        VStack(spacing: NTSpacing.sm) {
            if !subscriptions.isEntitled {
                Button {
                    Task {
                        if let signedTransaction = await subscriptions.purchase(appAccountToken: store.member.id) {
                            await store.synchronizeAppStoreTransaction(signedTransaction)
                        }
                    }
                } label: {
                    if subscriptions.isPurchasing {
                        ProgressView().tint(NTColor.background)
                    } else {
                        Text("Subscribe — \(subscriptions.displayPrice)/month")
                    }
                }
                .buttonStyle(NTPrimaryButtonStyle())
                .disabled(subscriptions.isPurchasing || subscriptions.isLoading)
            } else {
                Label("Active through Apple", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NTColor.success)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(NTColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
            }

            Button("Restore purchases") {
                Task {
                    if let signedTransaction = await subscriptions.restore() {
                        await store.synchronizeAppStoreTransaction(signedTransaction)
                    }
                }
            }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)

            HStack(spacing: NTSpacing.md) {
                Button("Terms of Use") { showingTerms = true }
                Button("Privacy Policy") { showingPrivacy = true }
            }
            .font(.footnote)
            .foregroundStyle(NTColor.textSecondary)
        }
    }

    private var statusTitle: String {
        if subscriptions.isEntitled { return "Your membership is active" }
        return switch store.membership.state {
        case .notStarted: "Your free month begins after setup"
        case .trial: "Your first month is free"
        case .subscribed: "Your membership is active"
        case .expired: "Continue meeting thoughtful peers"
        }
    }

    private var statusDetail: String {
        if subscriptions.isEntitled { return "You can keep receiving new introductions at the pace you choose." }
        return switch store.membership.state {
        case .notStarted: "Finish your professional context first. Your trial starts only when you are ready for matching."
        case .trial: "Use the full experience before deciding whether it belongs in your professional life."
        case .subscribed: "You can keep receiving new introductions at the pace you choose."
        case .expired: "New matching is paused. Subscribe to receive introductions again; your existing conversations and connections remain available."
        }
    }

    private var statusSymbol: String {
        (store.membership.hasAccess || subscriptions.isEntitled) ? "leaf.fill" : "cup.and.saucer.fill"
    }

    private func statusDateLabel(_ date: Date) -> String {
        switch store.membership.state {
        case .trial: "Free through \(date.formatted(date: .abbreviated, time: .omitted))"
        case .subscribed: "Renews \(date.formatted(date: .abbreviated, time: .omitted))"
        case .notStarted, .expired: "Ended \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(NTColor.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(NTColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { subscriptions.errorMessage != nil },
            set: { if !$0 { subscriptions.errorMessage = nil } }
        )
    }
}

struct MembershipGateView: View {
    @EnvironmentObject private var subscriptions: SubscriptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: NTSpacing.lg) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(NTColor.accentStrong)
            Text("Ready for your next connection?")
                .font(.title2.weight(.semibold))
            Text("Your free month has ended. Membership keeps thoughtful introductions moving while your existing conversations and connections stay available.")
                .foregroundStyle(NTColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                MembershipView()
            } label: {
                Text("Continue for \(subscriptions.displayPrice)/month")
            }
            .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(NTSpacing.lg)
        .ntSurface(radius: NTRadius.hero)
    }
}

private struct MembershipLegalView: View {
    enum Kind { case terms, privacy }
    let kind: Kind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(copy)
                    .font(.body)
                    .foregroundStyle(NTColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NTSpacing.lg)
            }
            .ntScreenBackground()
            .navigationTitle(kind == .terms ? "Terms of Use" : "Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var copy: String {
        switch kind {
        case .terms:
            "Membership renews monthly through your Apple Account unless cancelled at least 24 hours before the end of the current billing period. You can manage or cancel it in iPhone Settings. Community conduct and account eligibility rules continue to apply."
        case .privacy:
            "Your membership status is associated with your network.to account so access works consistently across devices. Apple handles payment details; network.to does not receive your card information. Professional context is used to shape introductions as described in the app’s privacy controls."
        }
    }
}
