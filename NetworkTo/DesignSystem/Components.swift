import SwiftUI

struct NTMonogram: View {
    let initials: String
    var size: CGFloat = 64

    var body: some View {
        Text(initials)
            .font(.headline.weight(.semibold))
            .foregroundStyle(NTColor.accentStrong)
            .frame(width: size, height: size)
            .background(NTColor.surfaceSecondary)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

struct NTVerifiedCompanyLine: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    let company: String
    var mark: CompanyMarkReference? = nil

    var body: some View {
        Label {
            CompanyMarkTile.text(
                companyName: company,
                reference: mark,
                markData: store.companyMarkData(for: mark),
                textStyle: .caption,
                dynamicTypeSize: dynamicTypeSize,
                displayScale: displayScale
            )
            + Text(" \(company) · Work email verified")
        } icon: {
            Image(systemName: "checkmark.seal.fill")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(NTColor.success)
        .accessibilityLabel("\(company). Verified through access to a company email. This does not imply employer endorsement.")
        .task(id: mark) { await store.ensureCompanyMark(mark) }
    }
}

struct NTTopicPill: View {
    let title: String
    var selected = false

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(NTColor.textPrimary)
            .padding(.horizontal, NTSpacing.sm)
            .padding(.vertical, 7)
            .background(selected ? NTColor.accent.opacity(0.11) : NTColor.surfaceSecondary.opacity(0.82))
            .clipShape(Capsule())
            .overlay {
                if selected {
                    Capsule().stroke(NTColor.accent.opacity(0.7), lineWidth: 0.75)
                }
            }
            .accessibilityValue(selected ? "Selected" : "")
    }
}

struct NTProfessionalIdentity: View {
    let profile: ProfessionalProfile
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: NTSpacing.md) {
            NTMonogram(initials: profile.initials, size: compact ? 48 : 68)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(profile.name)
                    .font(compact ? .headline : .title2.weight(.semibold))
                Text("\(profile.role) · \(profile.city)")
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
                NTVerifiedCompanyLine(company: profile.company, mark: profile.displayedCompanyMark)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NTReasonBlock: View {
    let title: String
    let text: String
    var symbol = "sparkles"

    var body: some View {
        HStack(alignment: .top, spacing: NTSpacing.sm) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(NTColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xs) {
                Text(title).font(.headline)
                Text(text)
                    .font(.body)
                    .foregroundStyle(NTColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NTEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: NTSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(NTColor.accent)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(NTColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NTSpacing.xxxl)
        .padding(.horizontal, NTSpacing.lg)
    }
}

struct NTPrivacyNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(NTColor.textSecondary)
            .padding(NTSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NTColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
    }
}

/// The one explanation that precedes the phone's notification permission dialog. It sits inline
/// at the top of Today, never modal, with no motion; both choices are plain text with equal
/// targets, and nothing about it persuades.
struct NTNotificationInviteCard: View {
    let turnOn: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            Text("When network.to will notify you")
                .font(.headline)
            Text("We’ll notify you only when an introduction is ready, when interest is mutual, when you receive a message, before a meeting, and when private feedback is due. You can change this anytime in iPhone Settings.")
                .font(.subheadline)
                .foregroundStyle(NTColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on notifications", action: turnOn)
                .buttonStyle(NTPrimaryButtonStyle())
                .accessibilityHint("Asks iPhone for permission to notify you")
            Button("Not now", action: notNow)
                .buttonStyle(NTSecondaryButtonStyle())
                .accessibilityHint("Keeps notifications off. You can turn them on later from Profile")
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ntSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notification permission")
    }
}

struct NTJourneyStep: View {
    let symbol: String
    let title: String
    let detail: String
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: NTSpacing.md) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NTColor.accentStrong)
                    .frame(width: 32, height: 32)
                    .background(NTColor.accent.opacity(0.09))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                if !isLast {
                    Rectangle()
                        .fill(NTColor.separator)
                        .frame(width: 1, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NTStatusPill: View {
    let text: String
    let symbol: String
    var tint: Color = NTColor.meeting

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, NTSpacing.sm)
            .padding(.vertical, 5)
            .background(tint.opacity(0.09))
            .clipShape(Capsule())
    }
}

/// The one notice surface. The glyph and tint say what kind of thing happened while the text
/// carries the meaning on its own; only an error stays, and only an error has anything to tap.
/// Each new notice is announced once to VoiceOver.
struct NTInlineNotice: View {
    let notice: AppNotice
    var dismiss: (() -> Void)? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: NTSpacing.sm) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NTColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if notice.persists {
                Spacer(minLength: NTSpacing.xs)
                if notice.canRetry, let retry {
                    Button("Retry", action: retry)
                        .buttonStyle(NTInlineNoticeButtonStyle(tint: NTColor.accentStrong))
                        .accessibilityHint("Runs the action again with the same values")
                }
                if let dismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(NTInlineNoticeButtonStyle(tint: NTColor.textSecondary))
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Clears this notice")
                }
            }
        }
        .padding(.leading, NTSpacing.md)
        .padding(.trailing, notice.persists ? NTSpacing.xs : NTSpacing.md)
        .padding(.vertical, notice.persists ? NTSpacing.xxs : NTSpacing.sm)
        .frame(maxWidth: notice.persists ? CGFloat.infinity : nil, minHeight: 44, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .task(id: notice.id) { AccessibilityNotification.Announcement(notice.text).post() }
    }

    private var symbol: String {
        switch notice.kind {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .success: NTColor.success
        case .information: NTColor.accent
        case .error: NTColor.destructive
        }
    }

    private var shape: AnyShape {
        notice.persists
            ? AnyShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
            : AnyShape(Capsule())
    }
}

/// Text and glyph buttons inside a notice row; every target is at least 44 by 44 points.
private struct NTInlineNoticeButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, NTSpacing.xs)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
