import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    Text("For making plans, not collecting chats.")
                        .font(.body)
                        .foregroundStyle(NTColor.textSecondary)

                if let conversation = store.conversation, store.canMessage {
                        conversationCard(conversation)
                } else {
                        emptyState
                    }
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.bottom, NTSpacing.xxxl)
            }
            .ntScreenBackground()
            .navigationTitle("Messages")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            VStack(alignment: .leading, spacing: NTSpacing.md) {
                ZStack {
                    Circle()
                        .fill(NTColor.accent.opacity(0.09))
                        .frame(width: 58, height: 58)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title2)
                        .foregroundStyle(NTColor.accent)
                }
                .accessibilityHidden(true)
                Text("Conversations start together")
                    .font(.title2.weight(.semibold))
                Text("There’s nothing to answer yet. A conversation appears here only when an introduction is reciprocal.")
                    .font(.body)
                    .foregroundStyle(NTColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                NTJourneyStep(
                    symbol: "sparkles",
                    title: "A considered introduction",
                    detail: "You each receive the same professional context."
                )
                NTJourneyStep(
                    symbol: "hand.thumbsup.fill",
                    title: "Interest is mutual",
                    detail: "Neither response is revealed unless you both choose Interested."
                )
                NTJourneyStep(
                    symbol: "cup.and.saucer.fill",
                    title: "A conversation opens",
                    detail: "Use it to say hello and arrange a short 1:1 meeting.",
                    isLast: true
                )
            }
            .padding(NTSpacing.lg)
            .ntSurface()

            NTPrivacyNote(text: "No cold messages, message requests, or searchable inbox. Passing never creates a conversation.")
        }
        .padding(.top, NTSpacing.xs)
    }

    private func conversationCard(_ conversation: Conversation) -> some View {
        NavigationLink {
            ConversationView()
        } label: {
            VStack(alignment: .leading, spacing: NTSpacing.md) {
                HStack(alignment: .top, spacing: NTSpacing.md) {
                    NTMonogram(initials: conversation.person.initials, size: 52)
                    VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                        Text(conversation.person.name)
                            .font(.title3.weight(.semibold))
                        Text("\(conversation.person.role) at \(conversation.person.company)")
                            .font(.subheadline)
                            .foregroundStyle(NTColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(NTColor.textSecondary)
                        .accessibilityHidden(true)
                }

                Text(conversation.messages.last?.body ?? "Start the conversation")
                    .font(.body.weight(conversation.isUnread ? .medium : .regular))
                    .foregroundStyle(NTColor.textPrimary)
                    .lineLimit(3)
                    .padding(NTSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NTColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))

                HStack {
                    meetupStatus(conversation.meetupStatus)
                    if conversation.isUnread {
                        Text("NEW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(NTColor.background)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NTColor.accentStrong)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(conversation.messages.last?.sentAt.formatted(date: .omitted, time: .shortened) ?? "")
                        .font(.caption)
                        .foregroundStyle(NTColor.textSecondary)
                }

                Divider()
                Label(conversation.introductionReason, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(NTColor.textSecondary)
                    .lineLimit(2)
            }
            .padding(NTSpacing.lg)
            .ntSurface()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the conversation with \(conversation.person.name)")
    }

    @ViewBuilder
    private func meetupStatus(_ status: MeetupStatus) -> some View {
        switch status {
        case .coordinating:
            NTStatusPill(text: "Finding a time", symbol: "cup.and.saucer")
        case .planned:
            NTStatusPill(text: "Coffee planned", symbol: "calendar.badge.checkmark")
        case .feedbackDue:
            NTStatusPill(text: "Feedback due", symbol: "checkmark.bubble", tint: NTColor.warning)
        case .completed:
            NTStatusPill(text: "Met", symbol: "checkmark.circle.fill", tint: NTColor.success)
        }
    }
}

struct ConversationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = ""
    @State private var showingFeedback = false
    @State private var showingMeetupPlanner = false
    @State private var showingReport = false
    @State private var safetyConfirmation: SafetyConfirmation?
    @FocusState private var composerFocused: Bool

    private enum SafetyConfirmation { case end, block }

    var body: some View {
        VStack(spacing: 0) {
            if let conversation = store.conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: NTSpacing.sm) {
                            reasonHeader(conversation)
                            ForEach(conversation.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                            meetupActions(conversation.meetupStatus)
                        }
                        .padding(.horizontal, NTSpacing.md)
                        .padding(.vertical, NTSpacing.md)
                    }
                    .onChange(of: conversation.messages.count) {
                        if let id = store.conversation?.messages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .background(NTColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if store.canMessage {
                composer
            } else {
                Label("This conversation has ended", systemImage: "lock.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NTColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(NTSpacing.md)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(store.conversation?.person.name ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Report", systemImage: "exclamationmark.bubble") { showingReport = true }
                    Button("End conversation", systemImage: "xmark.circle", role: .destructive) { safetyConfirmation = .end }
                    Button("Block member", systemImage: "hand.raised.fill", role: .destructive) { safetyConfirmation = .block }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Conversation options")
            }
        }
        .onAppear { store.openConversation() }
        .sheet(isPresented: $showingFeedback) {
            MeetupFeedbackView()
                .presentationDetents([.large])
                .interactiveDismissDisabled(store.phase == .feedback)
        }
        .sheet(isPresented: $showingMeetupPlanner) { MeetupPlannerView() }
        .sheet(isPresented: $showingReport) {
            if let person = store.conversation?.person { ReportMemberView(person: person) }
        }
        .confirmationDialog(
            safetyConfirmation == .block ? "Block this member?" : "End this conversation?",
            isPresented: Binding(get: { safetyConfirmation != nil }, set: { if !$0 { safetyConfirmation = nil } })
        ) {
            if safetyConfirmation == .block {
                Button("Block member", role: .destructive) { store.blockCurrentPerson() }
            } else {
                Button("End conversation", role: .destructive) { store.endCurrentConversation() }
            }
            Button("Cancel", role: .cancel) { safetyConfirmation = nil }
        } message: {
            Text(safetyConfirmation == .block ? "They won’t be able to contact you or be introduced again." : "Messaging will close. You can still report or block this member.")
        }
    }

    private func reasonHeader(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.xs) {
            Label("Why you were introduced", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(NTColor.accent)
            Text(conversation.introductionReason)
                .font(.subheadline)
                .foregroundStyle(NTColor.textSecondary)
        }
        .padding(NTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NTColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
        .padding(.bottom, NTSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.author == .member { Spacer(minLength: 54) }
            VStack(alignment: message.author == .member ? .trailing : .leading, spacing: NTSpacing.xxs) {
                Text(message.body)
                    .padding(.horizontal, NTSpacing.md)
                    .padding(.vertical, NTSpacing.sm)
                    .foregroundStyle(message.author == .member ? NTColor.background : NTColor.textPrimary)
                    .background(message.author == .member ? NTColor.accentStrong : NTColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if message.author == .introduction {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(NTColor.separator, lineWidth: 0.75)
                        }
                    }
                if message.author == .member {
                    messageDelivery(message)
                }
            }
            if message.author == .introduction { Spacer(minLength: 54) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(message.author == .member ? "You" : store.introduction.person.name): \(message.body)")
    }

    @ViewBuilder
    private func messageDelivery(_ message: ChatMessage) -> some View {
        switch message.delivery {
        case .sending:
            Text("Sending…").font(.caption2).foregroundStyle(NTColor.textSecondary)
        case .delivered:
            Text("Delivered").font(.caption2).foregroundStyle(NTColor.textSecondary)
        case .failed:
            Button("Not sent · Retry") { store.retryMessage(message.id) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NTColor.destructive)
        }
    }

    @ViewBuilder
    private func meetupActions(_ status: MeetupStatus) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            switch status {
            case .coordinating:
                Label("Ready to make a simple plan?", systemImage: "cup.and.saucer")
                    .font(.headline)
                Text("Keep it light: suggest a broad place and a short time.")
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
                Button("Propose a coffee") { showingMeetupPlanner = true }
                .buttonStyle(NTSecondaryButtonStyle())
            case .planned(let detail):
                Label("Coffee planned", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                    .foregroundStyle(NTColor.meeting)
                Text(detail).foregroundStyle(NTColor.textSecondary)
                Button("We met — share private feedback") {
                    store.requestFeedback()
                    showingFeedback = true
                }
                .buttonStyle(NTPrimaryButtonStyle())
            case .feedbackDue:
                Label("Private feedback is due", systemImage: "checkmark.bubble")
                    .font(.headline)
                Button("Share feedback") { showingFeedback = true }
                    .buttonStyle(NTPrimaryButtonStyle())
            case .completed:
                Label("Feedback shared privately", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NTColor.success)
            }
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NTColor.meeting.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .padding(.top, NTSpacing.lg)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: NTSpacing.sm) {
            TextField("Message Sarah", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, NTSpacing.md)
                .padding(.vertical, 13)
                .background(NTColor.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .frame(width: 44, height: 44)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, NTSpacing.md)
        .padding(.vertical, NTSpacing.xs)
        .background(.ultraThinMaterial)
    }

    private func send() {
        store.sendMessage(draft)
        draft = ""
    }
}

private struct MeetupFeedbackView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: MeetupOutcome?
    @State private var stayConnected = true
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    VStack(alignment: .leading, spacing: NTSpacing.sm) {
                        Text("How did it go?").font(.largeTitle.weight(.semibold))
                        Text("This feedback is private. There are no stars, public reviews, or visible scores.")
                            .font(.title3)
                            .foregroundStyle(NTColor.textSecondary)
                    }
                    ForEach(MeetupOutcome.allCases) { item in
                        Button {
                            outcome = item
                            stayConnected = item.createsConnectionByDefault
                        } label: {
                            HStack(alignment: .top, spacing: NTSpacing.md) {
                                Image(systemName: outcome == item ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(outcome == item ? NTColor.accent : NTColor.textSecondary)
                                VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                                    Text(item.rawValue).font(.headline)
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(NTColor.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(NTSpacing.md)
                            .ntSurface(radius: NTRadius.field)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(outcome == item ? "Selected" : "Not selected")
                    }
                    if let outcome, outcome != .didNotMeet {
                        Toggle("Stay connected with Sarah", isOn: $stayConnected)
                            .font(.headline)
                            .padding(NTSpacing.md)
                            .ntSurface(radius: NTRadius.field)
                    }
                    TextField("Optional private note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(NTSpacing.md)
                        .background(NTColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous)
                                .stroke(NTColor.separator, lineWidth: 1)
                        }
                }
                .padding(NTSpacing.lg)
            }
            .ntScreenBackground()
            .navigationTitle("Private feedback")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Submit feedback") {
                    guard let outcome else { return }
                    store.recordFeedback(outcome, stayConnected: stayConnected)
                    dismiss()
                }
                .buttonStyle(NTPrimaryButtonStyle())
                .disabled(outcome == nil)
                .padding(.horizontal, NTSpacing.lg)
                .padding(.vertical, NTSpacing.sm)
                .background(.ultraThinMaterial)
            }
        }
    }
}
