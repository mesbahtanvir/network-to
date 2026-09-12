import SwiftUI

struct IntroductionFlowView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var showPassConfirmation = false
    @State private var showPassFeedback = false

    var body: some View {
        ScrollView {
            Group {
                switch store.phase {
                case .ready: introduction
                case .waiting: waiting
                case .mutual: mutual
                case .passed: passed
                case .notMutual: nonMutual
                default: introduction
                }
            }
            .padding(.horizontal, NTSpacing.lg)
            .padding(.bottom, NTSpacing.xxxl)
        }
        .ntScreenBackground()
        .navigationTitle("Introduction")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if store.phase == .ready {
                responseActions
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            HStack {
                Text("NEW · TODAY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NTColor.accent)
                Spacer()
                Text("One introduction")
                    .font(.caption)
                    .foregroundStyle(NTColor.textSecondary)
            }

            NTProfessionalIdentity(profile: store.introduction.person)

            NTPillFlow(spacing: NTSpacing.xs) {
                ForEach(store.introduction.person.topics, id: \.self) { topic in
                    NTTopicPill(title: topic)
                }
            }

            VStack(alignment: .leading, spacing: NTSpacing.md) {
                Text("\(store.introduction.person.firstName)’s work and direction")
                    .font(.title3.weight(.semibold))
                labeledContext("ROLE SCOPE", store.introduction.person.roleScope)
                Divider()
                labeledContext("CURRENT FOCUS", store.introduction.person.currentFocus)
                Divider()
                labeledContext("WORKING TOWARD", store.introduction.person.professionalAmbition)
                Text(store.introduction.person.yearsExperience + " professional experience")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NTColor.textSecondary)
            }
            .padding(NTSpacing.lg)
            .ntSurface()

            VStack(spacing: NTSpacing.xl) {
                NTReasonBlock(title: "Why you should meet", text: store.introduction.reasonForYou)
                Divider()
                NTReasonBlock(title: "Why \(store.introduction.person.firstName) may want to meet you", text: store.introduction.reasonForThem, symbol: "arrow.left.arrow.right")
            }
            .padding(NTSpacing.lg)
            .ntSurface()

            VStack(alignment: .leading, spacing: NTSpacing.md) {
                Label("What \(store.introduction.person.firstName) can share", systemImage: "lightbulb.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NTColor.accent)
                Text(store.introduction.person.contribution)
                    .foregroundStyle(NTColor.textSecondary)
                NTPillFlow(spacing: NTSpacing.xs) {
                    ForEach(store.introduction.person.helpFormats, id: \.self) {
                        NTTopicPill(title: $0)
                    }
                }
                if !store.introduction.person.contributionBoundaries.isEmpty {
                    Divider()
                    labeledContext("HELPFUL BOUNDARIES", store.introduction.person.contributionBoundaries)
                }
            }
            .padding(NTSpacing.lg)
            .ntSurface()

            HStack(alignment: .top, spacing: NTSpacing.sm) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(NTColor.meeting)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                    Text("Easy to meet this week").font(.headline)
                    Text(store.introduction.meetingContext)
                        .font(.subheadline)
                        .foregroundStyle(NTColor.textSecondary)
                }
            }
            .padding(NTSpacing.lg)
            .background(NTColor.meeting.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
            .accessibilityElement(children: .combine)

            Text("Your response stays private unless you both choose Interested.")
                .font(.footnote)
                .foregroundStyle(NTColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, NTSpacing.md)
    }

    private func labeledContext(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.xxs) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(NTColor.accent)
            Text(value)
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var responseActions: some View {
        VStack(alignment: .leading, spacing: NTSpacing.sm) {
            if showPassConfirmation {
                HStack(alignment: .top, spacing: NTSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NTColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                        Text("Pass on \(store.introduction.person.firstName)?")
                            .font(.headline)
                        Text("Your choice stays private. No rejection notification is sent.")
                            .font(.footnote)
                            .foregroundStyle(NTColor.textSecondary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                HStack(spacing: NTSpacing.sm) {
                    Button("Pass privately") {
                        store.passIntroduction()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(NTColor.textSecondary)
                    .background(NTColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))

                    Button("Keep considering") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            showPassConfirmation = false
                        }
                    }
                    .buttonStyle(NTPrimaryButtonStyle())
                }
            } else {
                HStack(spacing: NTSpacing.sm) {
                    Button("Pass") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            showPassConfirmation = true
                        }
                    }
                    .font(.headline)
                    .frame(width: 92, height: 50)
                    .foregroundStyle(NTColor.textSecondary)
                    .background(NTColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))

                    Button("Interested") { store.respondInterested() }
                        .buttonStyle(NTPrimaryButtonStyle())
                }
            }
        }
        .padding(.horizontal, NTSpacing.lg)
        .padding(.vertical, showPassConfirmation ? NTSpacing.md : NTSpacing.xs)
        .background(.ultraThinMaterial)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showPassConfirmation)
    }

    private var waiting: some View {
        VStack(spacing: NTSpacing.xl) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(NTColor.accent)
                .accessibilityHidden(true)
            Text("Your interest is private")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("If \(store.introduction.person.firstName) is interested too, we’ll open a conversation. Until then, neither of you sees the other person’s choice.")
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
                .multilineTextAlignment(.center)
            Text("Nothing to do here. We’ll let you know only if it becomes mutual.")
                .font(.footnote)
                .foregroundStyle(NTColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, NTSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, NTSpacing.lg)
        .padding(.top, 72)
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 1.3))
            store.confirmMutualInterest()
        }
    }

    private var mutual: some View {
        VStack(spacing: NTSpacing.xl) {
            ZStack {
                Circle().fill(NTColor.success.opacity(0.1)).frame(width: 82, height: 82)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(NTColor.success)
            }
            .accessibilityHidden(true)
            Text("You both want to meet")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("A simple conversation is open now. Say hello and find a time for coffee.")
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
                .multilineTextAlignment(.center)
            NTProfessionalIdentity(profile: store.introduction.person, compact: true)
                .padding(NTSpacing.lg)
                .ntSurface()
            Button("Start the conversation") { store.openConversation() }
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(.top, 52)
    }

    private var passed: some View {
        VStack(spacing: NTSpacing.xl) {
            NTEmptyState(
                symbol: "hand.thumbsup",
                title: "Thanks for deciding",
                message: "Your pass is private. We’ll keep looking for someone worthwhile."
            )
            Button("Return to Today") { dismiss() }
                .buttonStyle(NTPrimaryButtonStyle())
            Button("Share private feedback") { showPassFeedback = true }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.top, NTSpacing.xl)
        .sheet(isPresented: $showPassFeedback) { PassFeedbackView() }
    }

    private var nonMutual: some View {
        VStack(spacing: NTSpacing.xl) {
            NTEmptyState(
                symbol: "lock.circle",
                title: "This introduction didn’t work out",
                message: "Individual responses are never revealed. We’ll keep looking for someone worthwhile."
            )
            Button("Return to Today") { dismiss() }
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(.top, NTSpacing.xl)
    }
}

private struct PassFeedbackView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String?
    private let reasons = ["Professional relevance", "Timing", "Location", "I already know them", "Topic mismatch"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Optional feedback is private and only improves future introductions.")
                        .foregroundStyle(NTColor.textSecondary)
                }
                Section("What influenced your decision?") {
                    ForEach(reasons, id: \.self) { item in
                        Button {
                            reason = item
                        } label: {
                            HStack {
                                Text(item).foregroundStyle(NTColor.textPrimary)
                                Spacer()
                                if reason == item { Image(systemName: "checkmark").foregroundStyle(NTColor.accent) }
                            }
                        }
                    }
                }
            }
            .ntScreenBackground()
            .navigationTitle("Private feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        store.transientMessage = "Feedback saved privately"
                        dismiss()
                    }
                    .disabled(reason == nil)
                }
            }
        }
    }
}
