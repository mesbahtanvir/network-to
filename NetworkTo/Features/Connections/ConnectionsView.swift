import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    Text("The people you’ve met—not a list of profiles.")
                        .font(.body)
                        .foregroundStyle(NTColor.textSecondary)

                    if store.connections.isEmpty {
                        emptyState
                    } else {
                        connectedSummary
                        ForEach(store.connections) { connection in
                            connectionCard(connection)
                        }
                    }
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.bottom, NTSpacing.xxxl)
            }
            .ntScreenBackground()
            .navigationTitle("Connections")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            VStack(alignment: .leading, spacing: NTSpacing.md) {
                ZStack {
                    Circle()
                        .fill(NTColor.meeting.opacity(0.09))
                        .frame(width: 60, height: 60)
                    Image(systemName: "person.2.fill")
                        .font(.title)
                        .foregroundStyle(NTColor.meeting)
                }
                .accessibilityHidden(true)
                Text("Connections begin after you meet")
                    .font(.title2.weight(.semibold))
                Text("A recommendation alone isn’t a relationship. When a mutual introduction becomes a real conversation, you can choose to keep that person in your network.")
                    .foregroundStyle(NTColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                NTJourneyStep(
                    symbol: "person.crop.circle.badge.plus",
                    title: "Introduced for a reason",
                    detail: "Both people receive reciprocal professional context."
                )
                NTJourneyStep(
                    symbol: "cup.and.saucer.fill",
                    title: "Meet 1:1",
                    detail: "The conversation is designed to become coffee, a walk, or another in-person chat."
                )
                NTJourneyStep(
                    symbol: "person.2.fill",
                    title: "Choose to stay connected",
                    detail: "After private feedback, the relationship and its origin are preserved here.",
                    isLast: true
                )
            }
            .padding(NTSpacing.lg)
            .ntSurface()

            HStack(alignment: .top, spacing: NTSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(NTColor.accent)
                    .accessibilityHidden(true)
                Text("Your first connection will appear naturally through the Introduction flow. There’s no directory to browse or invitation count to grow.")
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
            }
            .padding(NTSpacing.md)
        }
        .padding(.top, NTSpacing.xs)
    }

    private var connectedSummary: some View {
        HStack(alignment: .center, spacing: NTSpacing.md) {
            ZStack {
                Circle().fill(NTColor.success.opacity(0.13)).frame(width: 54, height: 54)
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(NTColor.success)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text("\(store.connections.count) meaningful \(store.connections.count == 1 ? "connection" : "connections")")
                    .font(.title3.weight(.semibold))
                Text("Built one real conversation at a time.")
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
            }
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NTColor.success.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
    }

    private func connectionCard(_ connection: Connection) -> some View {
        NavigationLink {
            ConnectionDetailView(connection: connection)
        } label: {
            VStack(alignment: .leading, spacing: NTSpacing.md) {
                HStack(spacing: NTSpacing.md) {
                    NTMonogram(initials: connection.person.initials, size: 54)
                    VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                        Text(connection.person.name).font(.title3.weight(.semibold))
                        NTRoleAndCompanyLine(
                            role: connection.person.role,
                            company: connection.person.company,
                            mark: connection.person.displayedCompanyMark
                        )
                        .foregroundStyle(NTColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        NTStatusPill(text: "Met in person", symbol: "cup.and.saucer.fill", tint: NTColor.success)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(NTColor.textSecondary)
                        .accessibilityHidden(true)
                }

                Divider()

                VStack(alignment: .leading, spacing: NTSpacing.xs) {
                    Text("HOW YOU CONNECTED")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NTColor.accent)
                    Text(connection.origin)
                        .font(.subheadline)
                        .foregroundStyle(NTColor.textSecondary)
                    Text("Connected \(connection.connectedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(NTColor.textSecondary)
                }

                NTPillFlow(spacing: NTSpacing.xs) {
                    ForEach(connection.person.topics.prefix(3), id: \.self) {
                        NTTopicPill(title: $0)
                    }
                }
            }
            .padding(NTSpacing.lg)
            .ntSurface()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens connection details for \(connection.person.name)")
    }
}

private struct ConnectionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let connection: Connection
    @State private var showingReport = false
    @State private var confirmation: Confirmation?
    private enum Confirmation { case remove, block }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NTSpacing.xl) {
                VStack(alignment: .leading, spacing: NTSpacing.md) {
                    NTProfessionalIdentity(profile: connection.person)
                    NTPillFlow(spacing: NTSpacing.xs) {
                        ForEach(connection.person.topics, id: \.self) { NTTopicPill(title: $0) }
                    }
                }
                .padding(NTSpacing.lg)
                .ntSurface(radius: NTRadius.hero)

                VStack(alignment: .leading, spacing: NTSpacing.sm) {
                    Label("How you connected", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NTColor.accent)
                    Text(connection.origin).foregroundStyle(NTColor.textSecondary)
                    Label(
                        "Met and connected \(connection.connectedAt.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "cup.and.saucer.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NTColor.meeting)
                }
                .padding(NTSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ntSurface()

                detailSection("briefcase", "\(connection.person.firstName)’s work now", connection.person.currentFocus)
                detailSection("lightbulb", "What \(connection.person.firstName) can share", connection.person.contribution)
                detailSection("scope", "What \(connection.person.firstName) is working toward", connection.person.professionalAmbition)
                detailSection("arrow.up.right", "Where \(connection.person.firstName) is growing", connection.person.growthInterest)

                if !connection.meetingHistory.isEmpty {
                    VStack(alignment: .leading, spacing: NTSpacing.md) {
                        Label("Meeting history", systemImage: "clock")
                            .font(.headline)
                        ForEach(connection.meetingHistory) { meeting in
                            HStack {
                                VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                                    Text(meeting.summary).font(.subheadline.weight(.medium))
                                    Text(meeting.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(NTColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(NTColor.success)
                            }
                        }
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()
                }

                if store.canMessage {
                    NavigationLink {
                        ConversationView()
                    } label: {
                        Label("Continue conversation", systemImage: "message.fill")
                    }
                    .buttonStyle(NTPrimaryButtonStyle())
                }

                Text("Connection context is private to you. There are no public counts, endorsements, or relationship scores.")
                    .font(.footnote)
                    .foregroundStyle(NTColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(NTSpacing.lg)
        }
        .ntScreenBackground()
        .navigationTitle(connection.person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Report", systemImage: "exclamationmark.bubble") { showingReport = true }
                    Button("Remove connection", systemImage: "person.crop.circle.badge.minus", role: .destructive) { confirmation = .remove }
                    Button("Block member", systemImage: "hand.raised.fill", role: .destructive) { confirmation = .block }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Connection options")
            }
        }
        .sheet(isPresented: $showingReport) { ReportMemberView(person: connection.person) }
        .confirmationDialog(
            confirmation == .block ? "Block this member?" : "Remove this connection?",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
        ) {
            if confirmation == .block {
                Button("Block member", role: .destructive) {
                    store.block(connection.person)
                    dismiss()
                }
            } else {
                Button("Remove connection", role: .destructive) {
                    store.removeConnection(connection.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        }
    }

    private func detailSection(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(NTColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xs) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(NTColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
        .accessibilityElement(children: .combine)
    }
}
