import Foundation

enum MembershipState: String, Codable, Equatable, Sendable {
    case notStarted = "not_started"
    case trial
    case subscribed
    case expired
}

struct MembershipStatus: Equatable, Sendable {
    let state: MembershipState
    let trialStartedAt: Date?
    let trialEndsAt: Date?
    let accessEndsAt: Date?
    let autoRenews: Bool

    var hasAccess: Bool {
        switch state {
        case .trial, .subscribed: true
        case .notStarted, .expired: false
        }
    }

    var renewalOrEndDate: Date? {
        state == .subscribed ? accessEndsAt : trialEndsAt
    }

    static let notStarted = MembershipStatus(
        state: .notStarted,
        trialStartedAt: nil,
        trialEndsAt: nil,
        accessEndsAt: nil,
        autoRenews: false
    )

    static func trial(now: Date = Date()) -> MembershipStatus {
        MembershipStatus(
            state: .trial,
            trialStartedAt: now,
            trialEndsAt: Calendar.current.date(byAdding: .month, value: 1, to: now),
            accessEndsAt: nil,
            autoRenews: false
        )
    }

    static let expired = MembershipStatus(
        state: .expired,
        trialStartedAt: nil,
        trialEndsAt: Date.distantPast,
        accessEndsAt: nil,
        autoRenews: false
    )

    static func subscribed(until date: Date? = nil) -> MembershipStatus {
        MembershipStatus(
            state: .subscribed,
            trialStartedAt: nil,
            trialEndsAt: nil,
            accessEndsAt: date,
            autoRenews: true
        )
    }
}

/// Reference to a verified company's mark as served by the product backend. Keyed by the
/// company, never by an email domain; the path is versioned so a refreshed mark is new content.
struct CompanyMarkReference: Codable, Hashable, Sendable {
    let key: String
    let version: Int
    let path: String
}

/// The company monogram shown wherever a company mark cannot be: at most two uppercase
/// characters taken from the first letter or digit of the first two words of the company name.
/// Words without a letter or digit and the joining words "and", "of", and "the" are skipped
/// unless they are the only word.
enum CompanyMonogram {
    private static let joiningWords: Set<String> = ["and", "of", "the"]

    static func characters(for companyName: String) -> String {
        let words = companyName.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let initials: [(word: String, initial: Character)] = words.compactMap { word in
            guard let initial = word.first(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return (word, initial)
        }
        let significant = initials.filter { !joiningWords.contains($0.word.lowercased().filter(\.isLetter)) }
        let chosen = significant.isEmpty ? initials : significant
        return chosen.prefix(2).map { String($0.initial).uppercased() }.joined()
    }
}

struct ProfessionalProfile: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var role: String
    var company: String
    var city: String
    var topics: [String]
    var bio: String
    var roleScope: String
    var currentFocus: String
    var yearsExperience: String
    var growthAreas: [String]
    var professionalAmbition: String
    var growthInterest: String
    var contributionAreas: [String]
    var helpFormats: [String]
    var contribution: String
    var contributionBoundaries: String
    var isWorkEmailVerified: Bool
    var professionalHistory: [ProfessionalExperience] = []
    var education: String = ""
    var resumeStatus: ResumeEnrichmentStatus = .notAdded
    var companyMark: CompanyMarkReference? = nil

    /// The mark a surface may show: only while the affiliation is verified (FR-028).
    var displayedCompanyMark: CompanyMarkReference? {
        isWorkEmailVerified ? companyMark : nil
    }

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

struct Introduction: Identifiable, Equatable, Sendable {
    let id: UUID
    let person: ProfessionalProfile
    let reasonForYou: String
    let reasonForThem: String
    let meetingContext: String
    let createdAt: Date
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Author: Equatable, Sendable { case member, introduction }

    let id: UUID
    let author: Author
    let body: String
    let sentAt: Date
    var failed: Bool = false
    var delivery: MessageDelivery = .delivered
}

struct Conversation: Identifiable, Equatable, Sendable {
    let id: UUID
    let person: ProfessionalProfile
    let introductionReason: String
    var messages: [ChatMessage]
    var isUnread: Bool
    var meetupStatus: MeetupStatus
    var isEnded: Bool = false
    var isBlocked: Bool = false
}

enum MeetupStatus: Equatable, Sendable {
    case coordinating
    case planned(String)
    case feedbackDue
    case completed
}

struct Connection: Identifiable, Equatable, Sendable {
    let id: UUID
    let person: ProfessionalProfile
    let connectedAt: Date
    let origin: String
    var meetingHistory: [MeetupRecord] = []
}

struct ProfessionalExperience: Identifiable, Equatable, Sendable {
    let id: UUID
    var role: String
    var company: String
    var period: String
}

struct MeetupRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let summary: String
}

enum MessageDelivery: String, Equatable, Sendable {
    case sending, delivered, failed
}

enum ResumeEnrichmentStatus: Equatable, Sendable {
    case notAdded
    case processing
    case uploaded
    case ready(ProfileImportSuggestions)
    case applied
}

enum ResumeImportStage: Int, CaseIterable, Equatable, Sendable {
    case readingDocument
    case protectingPrivacy
    case buildingProfile
    case readyToReview
}

struct ProfileImportSuggestions: Equatable, Sendable {
    var name: String?
    var role: String?
    var city: String?
    var roleScope: String?
    var yearsExperience: String?
    var currentFocus: String? = nil
    var education: String? = nil
    var topics: [String]
    var professionalHistory: [ProfessionalExperience]
    var contributionAreas: [String] = []
    var experienceSummary: String? = nil

    var summary: String {
        let historyCount = professionalHistory.count
        let historyText = historyCount == 1 ? "1 role" : "\(historyCount) roles"
        return [role, city, historyCount > 0 ? historyText : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

enum IntroductionFrequency: String, CaseIterable, Identifiable, Sendable {
    case weekly = "Weekly"
    case twiceMonthly = "Twice a month"
    case monthly = "Monthly"
    case exceptionalOnly = "Exceptional introductions only"
    case paused = "Paused"

    var id: String { rawValue }
}

struct NetworkingPreferences: Equatable, Sendable {
    var frequency: IntroductionFrequency = .weekly
    var goals: Set<String> = ["Learn from peers", "Broaden industry perspective"]
    var relationshipMix: String = "Peers and adjacent leaders"
    var crossCompany = true
    var crossIndustry = true
}

struct MeetingPreferences: Equatable, Sendable {
    var areas: Set<TodayAvailability.Area> = [.downtown, .flexible]
    var formats: Set<String> = ["Coffee", "Walk"]
    var windows: Set<TodayAvailability.Window> = [.lunch, .afterWork]
}

struct SafetyPreferences: Equatable, Sendable {
    var blockedMembers: [String] = []
}

enum ReportCategory: String, CaseIterable, Identifiable, Sendable {
    case harassment = "Harassment"
    case spam = "Spam"
    case fraud = "Fraud or misrepresentation"
    case inappropriate = "Inappropriate behavior"
    case romantic = "Romantic or sexual behavior"
    case discrimination = "Discrimination"
    case threatening = "Threatening behavior"
    case other = "Other safety concern"

    var id: String { rawValue }
}

enum CompanyDomainDecision: Equatable, Sendable {
    case eligible(company: String, domain: String)
    case reviewRequired(domain: String)
    case ineligible(reason: String)
}

enum MockServiceError: LocalizedError, Equatable, Sendable {
    case offline
    case invalidCode
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .offline: "You appear to be offline. Check your connection and try again."
        case .invalidCode: "That code could not be verified. Check it and try again."
        case .requestFailed: "Something went wrong. Please try again."
        }
    }
}

enum MeetupOutcome: String, CaseIterable, Identifiable, Sendable {
    case great = "Great conversation"
    case good = "Good conversation"
    case weak = "Not quite the right fit"
    case didNotMeet = "We didn’t meet"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .great: "I’d gladly meet again."
        case .good: "Useful and worth staying connected."
        case .weak: "We met, but I don’t need to stay connected."
        case .didNotMeet: "Plans changed or the meeting didn’t happen."
        }
    }

    var createsConnectionByDefault: Bool { self == .great || self == .good }
}

struct TodayAvailability: Equatable, Sendable {
    enum Area: String, CaseIterable, Identifiable, Sendable {
        case downtown = "Downtown / city centre"
        case central = "Central neighborhoods"
        case westSide = "West side"
        case eastSide = "East side"
        case flexible = "Flexible within the city"
        var id: String { rawValue }
    }

    enum Window: String, CaseIterable, Identifiable, Sendable {
        case lunch = "Lunch"
        case afternoon = "Afternoon"
        case afterWork = "After work"
        var id: String { rawValue }
    }

    let area: Area
    let window: Window
    let expiresAt: Date
}

enum IntroductionPhase: Equatable, Sendable {
    case searching, ready, waiting, mutual, conversation, feedback, connected, passed, notMutual
}

extension ProfessionalProfile {
    static let empty = ProfessionalProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "",
        role: "",
        company: "",
        city: "",
        topics: [],
        bio: "",
        roleScope: "",
        currentFocus: "",
        yearsExperience: "",
        growthAreas: [],
        professionalAmbition: "",
        growthInterest: "",
        contributionAreas: [],
        helpFormats: [],
        contribution: "",
        contributionBoundaries: "",
        isWorkEmailVerified: false
    )

    static let sarah = ProfessionalProfile(
        id: UUID(uuidString: "B697877E-57A3-4A9F-8D01-85770F426128")!,
        name: "Sarah Chen",
        role: "Staff Software Engineer",
        company: "Northstar AI",
        city: "Toronto, ON",
        topics: ["ML infrastructure", "Distributed systems", "AI systems"],
        bio: "Builds large-scale inference systems and thoughtful engineering teams.",
        roleScope: "Technical lead for the inference platform used across Northstar’s applied AI products.",
        currentFocus: "Improving inference reliability while helping the platform team scale its operating model.",
        yearsExperience: "10–15 years",
        growthAreas: ["Platform organizations", "Engineering leadership"],
        professionalAmbition: "Grow into an organization-wide technical leadership role while keeping hands-on influence on production AI systems.",
        growthInterest: "Learning how strong platform organizations scale.",
        contributionAreas: ["ML infrastructure", "Production AI", "Technical leadership"],
        helpFormats: ["Compare approaches", "Share lessons learned"],
        contribution: "Practical experience building AI infrastructure from early stage to production.",
        contributionBoundaries: "Happy to share patterns and tradeoffs, but not confidential architecture or hiring referrals.",
        isWorkEmailVerified: true,
        companyMark: CompanyMarkReference(key: "northstar-ai", version: 1, path: "northstar-ai/1.png")
    )

    static let currentMember = ProfessionalProfile(
        id: UUID(uuidString: "D4BA70E6-867B-4A84-A9F9-B598E4A15550")!,
        name: "Alex Morgan",
        role: "Engineering Director",
        company: "Orbit Systems",
        city: "Toronto, ON",
        topics: ["Distributed systems", "Engineering leadership", "Platform strategy"],
        bio: "Builds teams and systems that make complex products feel simple.",
        roleScope: "Leads a 28-person platform organization across reliability, developer experience, and core services.",
        currentFocus: "Evolving a global distributed platform while giving product teams more autonomy.",
        yearsExperience: "10–15 years",
        growthAreas: ["Applied AI products", "Executive communication", "Platform strategy"],
        professionalAmbition: "Build an engineering organization that can turn emerging AI capabilities into dependable products without losing technical depth.",
        growthInterest: "Connecting with technical leaders building applied AI products.",
        contributionAreas: ["Distributed systems", "Engineering leadership", "Scaling teams"],
        helpFormats: ["Compare approaches", "Review a challenge", "Share lessons learned"],
        contribution: "Experience scaling distributed platforms and engineering organizations.",
        contributionBoundaries: "Best suited to practical peer conversations; not offering recruiting or investment introductions.",
        isWorkEmailVerified: true,
        professionalHistory: [
            ProfessionalExperience(
                id: UUID(uuidString: "F31B58D6-545E-49C7-9136-BDF6B9CE4DC5")!,
                role: "Engineering Director",
                company: "Orbit Systems",
                period: "2022–Present"
            ),
            ProfessionalExperience(
                id: UUID(uuidString: "614C71B4-050E-4802-AE2F-BC83FE26F292")!,
                role: "Senior Engineering Manager",
                company: "Maple Cloud",
                period: "2018–2022"
            )
        ],
        education: "University of Waterloo · Computer Engineering"
    )

    static let maya = ProfessionalProfile(
        id: UUID(uuidString: "17C6EF44-57F3-4A0C-9DAF-138D304B5AE1")!,
        name: "Maya Patel",
        role: "VP Product",
        company: "Harbour Labs",
        city: "Toronto, ON",
        topics: ["Product strategy", "Developer tools", "Scaling teams"],
        bio: "Builds focused product organizations around technical products.",
        roleScope: "Leads product, design, and research for a developer platform used by growing software teams.",
        currentFocus: "Moving a developer tool from founder-led discovery to a repeatable product operating model.",
        yearsExperience: "10–15 years",
        growthAreas: ["AI product strategy", "Executive leadership"],
        professionalAmbition: "Help build a durable product company and mentor the next generation of technical product leaders.",
        growthInterest: "Comparing how product leaders build conviction around new AI capabilities.",
        contributionAreas: ["Product strategy", "Developer tools", "Scaling teams"],
        helpFormats: ["Compare approaches", "Review a challenge"],
        contribution: "Lessons from building product teams and developer platforms from early stage through scale.",
        contributionBoundaries: "Happy to discuss patterns, not confidential roadmap details.",
        isWorkEmailVerified: true
    )
}
