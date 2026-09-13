import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var name = ProfessionalProfile.currentMember.name
    @State private var role = ProfessionalProfile.currentMember.role
    @State private var city = ProfessionalProfile.currentMember.city
    @State private var roleScope = ProfessionalProfile.currentMember.roleScope
    @State private var currentFocus = ProfessionalProfile.currentMember.currentFocus
    @State private var yearsExperience = ProfessionalProfile.currentMember.yearsExperience
    @State private var growthAreas = Set(ProfessionalProfile.currentMember.growthAreas)
    @State private var professionalAmbition = ProfessionalProfile.currentMember.professionalAmbition
    @State private var growthInterest = ProfessionalProfile.currentMember.growthInterest
    @State private var contributionAreas = Set(ProfessionalProfile.currentMember.contributionAreas)
    @State private var helpFormats = Set(ProfessionalProfile.currentMember.helpFormats)
    @State private var contribution = ProfessionalProfile.currentMember.contribution
    @State private var contributionBoundaries = ProfessionalProfile.currentMember.contributionBoundaries
    @State private var selectedArea = TodayAvailability.Area.downtown
    @State private var selectedWindow = TodayAvailability.Window.afterWork
    @State private var introductionFrequency = IntroductionFrequency.weekly
    @State private var networkingGoals: Set<String> = ["Learn from peers", "Broaden industry perspective"]
    @State private var meetAcrossCompanies = true
    @State private var includeAdjacentIndustries = true
    @State private var hydratedMemberID: UUID?
    @State private var isChoosingResume = false
    @State private var showResumeImportFlow = false
    @State private var didUseResumeDraft = false

    private let totalSteps = 7
    private let experienceOptions = ["1–3 years", "4–6 years", "7–9 years", "10–15 years", "15+ years"]
    private let growthOptions = [
        "Applied AI products", "Executive communication", "Engineering leadership",
        "Platform strategy", "Product thinking", "Founder perspective",
        "Career transition", "Local tech ecosystem"
    ]
    private let contributionOptions = [
        "Distributed systems", "AI infrastructure", "Developer tools", "Product strategy",
        "Engineering leadership", "Scaling teams", "Fundraising", "Go-to-market"
    ]
    private let helpOptions = [
        "Compare approaches", "Review a challenge", "Share lessons learned", "Make a relevant introduction"
    ]
    private let networkingGoalOptions = [
        "Learn from peers", "Broaden industry perspective", "Navigate a career transition",
        "Explore entrepreneurship", "Develop leadership range", "Meet across companies"
    ]

    init() {
        #if DEBUG
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--onboarding-step=") }
        let value = argument?.split(separator: "=").last.flatMap { Int($0) } ?? 0
        _step = State(initialValue: min(max(value, 0), 7))
        _showResumeImportFlow = State(initialValue: ProcessInfo.processInfo.arguments.contains("--resume-review-preview"))
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            ScrollView {
                currentStep
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NTSpacing.lg)
                    .padding(.vertical, NTSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomAction
        }
        .background(NTColor.background.ignoresSafeArea())
        .foregroundStyle(NTColor.textPrimary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: step)
        .task(id: store.member.id) { hydrateDraftFromStore() }
        .fileImporter(isPresented: $isChoosingResume, allowedContentTypes: [.pdf]) { result in
            guard case .success(let fileURL) = result else { return }
            Task {
                let hasAccess = fileURL.startAccessingSecurityScopedResource()
                defer { if hasAccess { fileURL.stopAccessingSecurityScopedResource() } }
                showResumeImportFlow = true
                await store.processResume(fileURL: fileURL)
            }
        }
        .fullScreenCover(isPresented: $showResumeImportFlow) {
            ResumeImportFlowView(
                onApply: { suggestions in
                    useResumeDraft(suggestions)
                    showResumeImportFlow = false
                },
                onContinueManually: { showResumeImportFlow = false },
                onChooseAnother: {
                    showResumeImportFlow = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        isChoosingResume = true
                    }
                }
            )
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0: setupIntroduction
        case 1: identity
        case 2: workContext
        case 3: growthContext
        case 4: contributionContext
        case 5: meetingContext
        case 6: networkingBehavior
        default: review
        }
    }

    private var progressHeader: some View {
        VStack(spacing: NTSpacing.sm) {
            HStack {
                if step > 0 {
                    Button { step -= 1 } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                Text(step == 0 ? "Account context" : "Step \(step) of \(totalSteps)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            ProgressView(value: Double(step), total: Double(totalSteps))
                .tint(NTColor.accent)
                .accessibilityLabel("Account setup progress")
                .accessibilityValue(step == 0 ? "Account context introduction" : "Step \(step) of \(totalSteps)")
        }
        .padding(.horizontal, NTSpacing.sm)
        .padding(.bottom, NTSpacing.xs)
        .background(NTColor.background)
    }

    private var setupIntroduction: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            Label("Work email verified", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NTColor.success)
            onboardingTitle(
                "Build the context for connections that move you forward.",
                "Tell us where you are, where you want to go, and what you can share. We’ll find ambitious people in your city whose experience and energy complement yours."
            )
            resumeFastStart
            VStack(alignment: .leading, spacing: NTSpacing.md) {
                welcomePoint("briefcase", "Your professional context", "Share the scope and current focus behind your role.")
                welcomePoint("scope", "Where you want to go", "Describe the impact, craft, role, or transition you are working toward.")
                welcomePoint("lightbulb", "What you can meaningfully share", "Be concrete about lived experience and helpful boundaries.")
            }
            .padding(NTSpacing.lg)
            .ntSurface(radius: NTRadius.hero)
            NTPrivacyNote(text: "You can review every field before finishing and edit your context later.")
        }
    }

    @ViewBuilder
    private var resumeFastStart: some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            Label("Prefill from your résumé", systemImage: "wand.and.stars")
                .font(.headline)
                .foregroundStyle(NTColor.accentStrong)
            Text("AI drafts the factual details. You review everything and write your own goals.")
                .font(.subheadline)
                .foregroundStyle(NTColor.textSecondary)

            switch store.member.resumeStatus {
            case .notAdded:
                Button("Upload PDF résumé") { isChoosingResume = true }
                    .buttonStyle(NTSecondaryButtonStyle())
                Text("Optional · 10 MB maximum · Text is read on this iPhone; the PDF is never uploaded")
                    .font(.footnote)
                    .foregroundStyle(NTColor.textSecondary)
                if let error = store.resumeImportError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(NTColor.destructive)
                        .accessibilityLabel("Résumé import error: \(error)")
                }
            case .processing:
                HStack(spacing: NTSpacing.sm) {
                    ProgressView()
                    Text("Building your private draft…").font(.subheadline.weight(.medium))
                }
            case .uploaded:
                Label("Your résumé is ready to process when AI drafting is available.", systemImage: "lock.doc")
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
            case .ready(let suggestions):
                Label("Draft ready", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NTColor.success)
                if !suggestions.summary.isEmpty {
                    Text(suggestions.summary).font(.subheadline).foregroundStyle(NTColor.textSecondary)
                }
                Button("Review résumé draft") { showResumeImportFlow = true }
                    .buttonStyle(NTPrimaryButtonStyle())
            case .applied:
                Label("Draft added—continue to review it", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NTColor.success)
            }
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private func welcomePoint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(NTColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(NTColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("Set your professional foundation", "Use the identity you’d naturally give when meeting a peer for coffee.")
            if didUseResumeDraft {
                NTPrivacyNote(text: "Prefilled from your résumé. Only correct anything that does not look right.")
            }
            NTFormField(title: "Full name", prompt: "Your real name", text: $name, contentType: .name)
            NTFormField(title: "Current role", prompt: "e.g. Engineering Director", text: $role, contentType: .jobTitle)
            VStack(alignment: .leading, spacing: NTSpacing.xs) {
                Text("Verified company").font(.headline)
                HStack {
                    Text(store.member.company)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(NTColor.success)
                }
                .padding(NTSpacing.md)
                .background(NTColor.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
                Text("Company comes from work-email verification.")
                    .font(.footnote)
                    .foregroundStyle(NTColor.textSecondary)
            }
            NTFormField(
                title: "City",
                prompt: "e.g. Toronto, ON or Austin, TX",
                text: $city,
                detail: "Use city plus state, province, or region. Introductions stay within your city so meeting in person is realistic.",
                contentType: .addressCity
            )
        }
    }

    private var workContext: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("Describe the work behind your title", "A title alone rarely explains why two people should meet. Give enough context to understand your scope—without sharing confidential details.")
            if didUseResumeDraft {
                NTPrivacyNote(text: "Résumé details are a draft. Review them for accuracy and remove confidential context.")
            }
            NTGuidanceCard(
                title: "Useful context sounds like",
                text: "Leads a 28-person platform organization across reliability, developer experience, and core services."
            )
            NTFormField(
                title: "Role scope",
                prompt: "What do you own, lead, or influence?",
                text: $roleScope,
                detail: "Include team, product, function, or scale when relevant.",
                multiline: true,
                limit: 220
            )
            NTFormField(
                title: "What are you focused on now?",
                prompt: "A current problem, transition, or priority",
                text: $currentFocus,
                detail: "This creates timely reasons to talk. Avoid confidential project names.",
                multiline: true,
                limit: 220
            )
            VStack(alignment: .leading, spacing: NTSpacing.xs) {
                Text("Professional experience").font(.headline)
                Picker("Professional experience", selection: $yearsExperience) {
                    ForEach(experienceOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, NTSpacing.md)
                .background(NTColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: NTRadius.field).stroke(NTColor.separator) }
                Text("Used for professional relevance, never as a public seniority score.")
                    .font(.footnote)
                    .foregroundStyle(NTColor.textSecondary)
            }
        }
    }

    private var growthContext: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("Where are you headed?", "Share the professional direction you care about—not just the next title. This helps us find people whose experience or journey is genuinely relevant.")
            Text("Optional themes")
                .font(.headline)
            selectionGrid(options: growthOptions, selection: $growthAreas, maximum: 4)
            NTFormField(
                title: "What do you want to achieve?",
                prompt: "A role, impact, craft, or change you’re working toward",
                text: $professionalAmbition,
                detail: "Think two to three years ahead. Focus on the work or impact you want, not prestige.",
                multiline: true,
                limit: 240
            )
            NTFormField(
                title: "What perspective would help right now? · Optional",
                prompt: "Describe the perspective or decision you’re seeking",
                text: $growthInterest,
                detail: "Be specific enough to guide an introduction, but broad enough for a natural conversation.",
                multiline: true,
                limit: 240
            )
            NTGuidanceCard(
                title: "Better than “grow my network”",
                text: "I want to compare how technical leaders introduce AI capabilities without distracting from a platform roadmap."
            )
        }
    }

    private var contributionContext: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("What can you meaningfully share?", "Good introductions are reciprocal. Describe experience you’re comfortable discussing—not status, access, or a vague promise to help.")
            VStack(alignment: .leading, spacing: NTSpacing.sm) {
                Text("Experience you can speak from").font(.headline)
                Text("Choose up to four").font(.footnote).foregroundStyle(NTColor.textSecondary)
                selectionGrid(options: contributionOptions, selection: $contributionAreas, maximum: 4)
            }
            VStack(alignment: .leading, spacing: NTSpacing.sm) {
                Text("How you like to help").font(.headline)
                selectionRows(options: helpOptions, selection: $helpFormats)
            }
            NTFormField(
                title: "What could another person learn from you?",
                prompt: "A concrete experience, pattern, or lesson",
                text: $contribution,
                detail: "Example: scaling a distributed platform while changing team ownership boundaries.",
                multiline: true,
                limit: 240
            )
            NTFormField(
                title: "Helpful boundaries",
                prompt: "What are you not offering?",
                text: $contributionBoundaries,
                detail: "Optional. Clarify things like referrals, recruiting, investment, or confidential advice.",
                multiline: true,
                limit: 180
            )
        }
    }

    private var meetingContext: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("Make meeting easy", "Share broad preferences so an introduction in your city can become a practical coffee chat—not an endless conversation in the app.")
            choiceSection("Usual work area") {
                Picker("Usual work area", selection: $selectedArea) {
                    ForEach(TodayAvailability.Area.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            choiceSection("Best time") {
                Picker("Best time", selection: $selectedWindow) {
                    ForEach(TodayAvailability.Window.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Label("Only your city and broad area overlap are shared, and only inside an introduction.", systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(NTColor.textSecondary)
        }
    }

    private var networkingBehavior: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("Open up your professional world", "Choose the relationships and perspectives that could help you learn faster. You will still receive only selective, high-quality introductions.")
            VStack(alignment: .leading, spacing: NTSpacing.sm) {
                Text("Maximum introduction frequency").font(.headline)
                Picker("Maximum introduction frequency", selection: $introductionFrequency) {
                    ForEach(IntroductionFrequency.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Text("This is a ceiling, not a quota. No introduction is better than a weak one.")
                    .font(.footnote)
                    .foregroundStyle(NTColor.textSecondary)
            }
            .padding(NTSpacing.lg)
            .ntSurface()

            VStack(alignment: .leading, spacing: NTSpacing.sm) {
                Text("What would make meeting worthwhile?").font(.headline)
                selectionGrid(options: networkingGoalOptions, selection: $networkingGoals, maximum: 4)
            }

            VStack(alignment: .leading, spacing: NTSpacing.md) {
                Text("Perspective reach").font(.headline)
                Toggle("Meet across companies", isOn: $meetAcrossCompanies)
                Toggle("Include adjacent industries", isOn: $includeAdjacentIndustries)
                Text("Different environments can surface useful patterns earlier. These settings broaden perspective; they never create a directory to browse.")
                    .font(.footnote)
                    .foregroundStyle(NTColor.textSecondary)
            }
            .tint(NTColor.accent)
            .padding(NTSpacing.lg)
            .ntSurface()
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            onboardingTitle("Review the context behind your introductions", "This is the professional picture the product will use. You stay in control of every field.")
            reviewRow("person.text.rectangle", "Identity", "\(role) at \(store.member.company) · \(city)", "Shown in introductions")
            reviewRow("briefcase", "Your work", "\(roleScope)\n\nCurrent focus: \(currentFocus)", "Shown selectively")
            reviewRow("scope", "Professional direction", professionalAmbition, "Used for relevance")
            reviewRow("arrow.up.right", "Where you’re growing", growthAreas.sorted().joined(separator: " · ") + "\n\n" + growthInterest, "Used for relevance")
            reviewRow("lightbulb", "What you can share", contributionAreas.sorted().joined(separator: " · ") + "\n\n" + contribution, "Used for reciprocity")
            reviewRow("hand.raised", "Contribution boundaries", contributionBoundaries.isEmpty ? "None added" : contributionBoundaries, "Shown when relevant")
            reviewRow("cup.and.saucer", "Meeting context", "\(selectedArea.rawValue) · \(selectedWindow.rawValue)", "Coarse only")
            reviewRow(
                "slider.horizontal.3",
                "Introduction approach",
                introductionFrequency.rawValue + "\n\n" + networkingGoals.sorted().joined(separator: " · ") + "\n\n" + perspectiveReachSummary,
                "Used for relevance"
            )
        }
    }

    private func selectionGrid(options: [String], selection: Binding<Set<String>>, maximum: Int) -> some View {
        NTPillFlow(spacing: NTSpacing.xs) {
            ForEach(options, id: \.self) { option in
                let selected = selection.wrappedValue.contains(option)
                Button {
                    if selected {
                        selection.wrappedValue.remove(option)
                    } else if selection.wrappedValue.count < maximum {
                        selection.wrappedValue.insert(option)
                    }
                } label: {
                    NTTopicPill(title: option, selected: selected)
                }
                .buttonStyle(.plain)
                .disabled(!selected && selection.wrappedValue.count >= maximum)
                .accessibilityLabel(option)
            }
        }
    }

    private func selectionRows(options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(spacing: NTSpacing.xs) {
            ForEach(options, id: \.self) { option in
                let selected = selection.wrappedValue.contains(option)
                Button {
                    if selected { selection.wrappedValue.remove(option) }
                    else { selection.wrappedValue.insert(option) }
                } label: {
                    HStack {
                        Text(option).font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? NTColor.accent : NTColor.textSecondary)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, NTSpacing.md)
                    .background(selected ? NTColor.accent.opacity(0.1) : NTColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.control, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: NTRadius.control).stroke(selected ? NTColor.accent : NTColor.separator) }
                }
                .buttonStyle(.plain)
                .accessibilityValue(selected ? "Selected" : "Not selected")
            }
        }
    }

    private func onboardingTitle(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.sm) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(detail)
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
                .lineSpacing(2)
        }
    }

    private func choiceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.sm) {
            Text(title).font(.headline)
            content().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .padding(NTSpacing.lg)
        .ntSurface()
    }

    private func reviewRow(_ symbol: String, _ title: String, _ value: String, _ visibility: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.sm) {
            Label(title, systemImage: symbol).font(.headline)
            Text(value).foregroundStyle(NTColor.textSecondary)
            Label(visibility, systemImage: visibility == "Only you" ? "lock" : "eye")
                .font(.caption.weight(.medium))
                .foregroundStyle(NTColor.accent)
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ntSurface()
    }

    private var bottomAction: some View {
        Button(step == totalSteps ? "Finish setup" : (step == 0 ? "Set up my context" : "Continue")) {
            advance()
        }
        .buttonStyle(NTPrimaryButtonStyle())
        .disabled(!canContinue || store.isCompletingOnboarding)
        .overlay {
            if store.isCompletingOnboarding {
                ProgressView().tint(NTColor.background)
            }
        }
        .padding(.horizontal, NTSpacing.lg)
        .padding(.vertical, NTSpacing.md)
        .background(.ultraThinMaterial)
    }

    private var canContinue: Bool {
        switch step {
        case 1: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: roleScope.count >= 20 && currentFocus.count >= 20
        case 3: professionalAmbition.count >= 20
        case 4: !contributionAreas.isEmpty && !helpFormats.isEmpty && contribution.count >= 20
        case 6: !networkingGoals.isEmpty
        default: true
        }
    }

    private func advance() {
        if step < totalSteps {
            step += 1
        } else {
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
                contributionBoundaries: contributionBoundaries
            )
            store.saveNetworkingPreferences(NetworkingPreferences(
                frequency: introductionFrequency,
                goals: networkingGoals,
                relationshipMix: "Peers and adjacent leaders",
                crossCompany: meetAcrossCompanies,
                crossIndustry: includeAdjacentIndustries
            ))
            store.saveMeetingPreferences(MeetingPreferences(
                areas: [selectedArea],
                formats: ["Coffee", "Walk"],
                windows: [selectedWindow]
            ))
            store.completeOnboarding()
        }
    }

    private func useResumeDraft(_ suggestions: ProfileImportSuggestions) {
        store.applyResumeSuggestions(suggestions)
        if let value = suggestions.name?.trimmedForImport { name = value }
        if let value = suggestions.role?.trimmedForImport { role = value }
        if let value = suggestions.city?.trimmedForImport { city = value }
        if let value = suggestions.roleScope?.trimmedForImport { roleScope = value }
        if let value = suggestions.yearsExperience?.trimmedForImport { yearsExperience = value }
        if let value = suggestions.currentFocus?.trimmedForImport { currentFocus = value }
        contributionAreas.formUnion(suggestions.contributionAreas)
        if let value = suggestions.experienceSummary?.trimmedForImport { contribution = value }
        didUseResumeDraft = true

        if name.trimmedForImport == nil || role.trimmedForImport == nil || city.trimmedForImport == nil {
            step = 1
        } else if roleScope.count < 20 || currentFocus.count < 20 {
            step = 2
        } else {
            step = 3
        }
    }

    private func hydrateDraftFromStore() {
        guard hydratedMemberID != store.member.id else { return }
        hydratedMemberID = store.member.id
        let profile = store.member
        name = profile.name
        role = profile.role
        city = profile.city
        roleScope = profile.roleScope
        currentFocus = profile.currentFocus
        yearsExperience = profile.yearsExperience
        growthAreas = Set(profile.growthAreas)
        professionalAmbition = profile.professionalAmbition
        growthInterest = profile.growthInterest
        contributionAreas = Set(profile.contributionAreas)
        helpFormats = Set(profile.helpFormats)
        contribution = profile.contribution
        contributionBoundaries = profile.contributionBoundaries

        introductionFrequency = store.networkingPreferences.frequency
        networkingGoals = store.networkingPreferences.goals
        meetAcrossCompanies = store.networkingPreferences.crossCompany
        includeAdjacentIndustries = store.networkingPreferences.crossIndustry
        selectedArea = store.meetingPreferences.areas.first ?? .downtown
        selectedWindow = store.meetingPreferences.windows.first ?? .afterWork
    }

    private var perspectiveReachSummary: String {
        var values: [String] = []
        if meetAcrossCompanies { values.append("Across companies") }
        if includeAdjacentIndustries { values.append("Adjacent industries") }
        return values.isEmpty ? "Within your current professional context" : values.joined(separator: " · ")
    }
}

private struct ResumeImportFlowView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onApply: (ProfileImportSuggestions) -> Void
    let onContinueManually: () -> Void
    let onChooseAnother: () -> Void

    @State private var draft: ProfileImportSuggestions?

    var body: some View {
        Group {
            switch store.member.resumeStatus {
            case .processing:
                processingView
            case .ready(let suggestions):
                reviewView(fallback: suggestions)
            case .notAdded where store.resumeImportError != nil:
                errorView
            case .uploaded:
                unavailableView
            case .applied:
                appliedView
            case .notAdded:
                errorView
            }
        }
        .background(NTColor.background.ignoresSafeArea())
        .foregroundStyle(NTColor.textPrimary)
        .interactiveDismissDisabled(store.member.resumeStatus == .processing)
        .onAppear { synchronizeDraft(with: store.member.resumeStatus) }
        .onChange(of: store.member.resumeStatus) { _, status in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                synchronizeDraft(with: status)
            }
        }
    }

    private var processingView: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xxl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(NTColor.accent.opacity(0.1))
                    .frame(width: 112, height: 112)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(NTColor.accent)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: NTSpacing.sm) {
                Text("Turning your résumé into a draft")
                    .font(.largeTitle.weight(.semibold))
                Text("We’re extracting only the professional facts that can save you setup time.")
                    .foregroundStyle(NTColor.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(ResumeImportStage.allCases, id: \.rawValue) { stage in
                    processingRow(stage)
                    if stage != .readyToReview { Divider().padding(.leading, 44) }
                }
            }
            .padding(.horizontal, NTSpacing.md)
            .ntSurface()

            NTPrivacyNote(text: "The PDF stays on this iPhone. Contact details are removed before protected résumé text is sent for drafting.")
            Spacer()
        }
        .padding(NTSpacing.lg)
    }

    private func processingRow(_ stage: ResumeImportStage) -> some View {
        let current = store.resumeImportStage.rawValue
        let completed = stage.rawValue < current
        let active = stage == store.resumeImportStage
        return HStack(spacing: NTSpacing.md) {
            Image(systemName: completed ? "checkmark.circle.fill" : active ? "circle.dotted" : "circle")
                .foregroundStyle(completed ? NTColor.success : active ? NTColor.accent : NTColor.separator)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(stage.title).font(.body.weight(active ? .semibold : .regular))
                if active { Text(stage.detail).font(.caption).foregroundStyle(NTColor.textSecondary) }
            }
            Spacer()
            if active { ProgressView().controlSize(.small) }
        }
        .frame(minHeight: active ? 64 : 52)
        .accessibilityElement(children: .combine)
    }

    private func reviewView(fallback: ProfileImportSuggestions) -> some View {
        let value = draft ?? fallback
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    VStack(alignment: .leading, spacing: NTSpacing.sm) {
                        Label("RÉSUMÉ DRAFT", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(NTColor.success)
                        Text("Keep what feels right")
                            .font(.largeTitle.weight(.semibold))
                        Text("We found these details in your résumé. Remove anything you don’t want in your profile; you can edit the rest next.")
                            .foregroundStyle(NTColor.textSecondary)
                    }

                    NTPrivacyNote(text: "Nothing is added to your profile until you choose Use selected details.")

                    importSection("Professional foundation", systemImage: "person.text.rectangle") {
                        removableField("Name", value: value.name) { draft?.name = nil }
                        removableField("Current role", value: value.role) { draft?.role = nil }
                        removableField("City", value: value.city) { draft?.city = nil }
                        removableField("Experience", value: value.yearsExperience) { draft?.yearsExperience = nil }
                    }

                    importSection("Work context", systemImage: "briefcase") {
                        removableField("Role scope", value: value.roleScope) { draft?.roleScope = nil }
                        removableField("Current focus", value: value.currentFocus) { draft?.currentFocus = nil }
                    }

                    if !value.topics.isEmpty {
                        importSection("Expertise", systemImage: "sparkles") {
                            removablePills(value.topics, remove: { item in draft?.topics.removeAll { $0 == item } })
                        }
                    }

                    if !value.professionalHistory.isEmpty {
                        importSection("Professional history", systemImage: "clock.arrow.circlepath") {
                            ForEach(value.professionalHistory) { experience in
                                removableExperience(experience) {
                                    draft?.professionalHistory.removeAll { $0.id == experience.id }
                                }
                            }
                        }
                    }

                    if value.education?.trimmedForImport != nil {
                        importSection("Education", systemImage: "graduationcap") {
                            removableField("Résumé detail", value: value.education) { draft?.education = nil }
                        }
                    }

                    if !value.contributionAreas.isEmpty || value.experienceSummary?.trimmedForImport != nil {
                        importSection("Experience you can speak from", systemImage: "lightbulb") {
                            if !value.contributionAreas.isEmpty {
                                removablePills(value.contributionAreas) { item in
                                    draft?.contributionAreas.removeAll { $0 == item }
                                }
                            }
                            removableField("Demonstrated experience", value: value.experienceSummary) {
                                draft?.experienceSummary = nil
                            }
                        }
                    }
                }
                .padding(NTSpacing.lg)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Start over", action: onChooseAnother)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: NTSpacing.sm) {
                    Button("Use selected details") { onApply(value) }
                        .buttonStyle(NTPrimaryButtonStyle())
                    Button("Continue without résumé", action: onContinueManually)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NTColor.textSecondary)
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.vertical, NTSpacing.md)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func importSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.md) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(NTColor.accentStrong)
            content()
        }
        .padding(NTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ntSurface()
    }

    @ViewBuilder
    private func removableField(_ label: String, value: String?, remove: @escaping () -> Void) -> some View {
        if let value = value?.trimmedForImport {
            HStack(alignment: .top, spacing: NTSpacing.sm) {
                VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                    Text(label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NTColor.textSecondary)
                    Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NTSpacing.sm)
                removeButton(label: label, action: remove)
            }
            .padding(.vertical, NTSpacing.xs)
        }
    }

    private func removablePills(_ values: [String], remove: @escaping (String) -> Void) -> some View {
        NTPillFlow(spacing: NTSpacing.xs) {
            ForEach(values, id: \.self) { value in
                Button { remove(value) } label: {
                    HStack(spacing: NTSpacing.xxs) {
                        Text(value)
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, NTSpacing.sm)
                    .padding(.vertical, NTSpacing.xs)
                    .background(NTColor.accent.opacity(0.1))
                    .foregroundStyle(NTColor.accentStrong)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(value)")
            }
        }
    }

    private func removableExperience(_ experience: ProfessionalExperience, remove: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.sm) {
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(experience.role).font(.subheadline.weight(.semibold))
                Text([experience.company, experience.period].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(NTColor.textSecondary)
            }
            Spacer()
            removeButton(label: "\(experience.role) at \(experience.company)", action: remove)
        }
        .padding(.vertical, NTSpacing.xs)
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(NTColor.textSecondary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(label)")
    }

    private var errorView: some View {
        VStack(spacing: NTSpacing.xl) {
            Spacer()
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(NTColor.accent)
            VStack(spacing: NTSpacing.sm) {
                Text("We couldn’t read that résumé")
                    .font(.title.weight(.semibold))
                Text(store.resumeImportError ?? "Try another PDF, or continue and add only the details that matter.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NTColor.textSecondary)
            }
            Spacer()
            Button("Choose another PDF", action: onChooseAnother)
                .buttonStyle(NTPrimaryButtonStyle())
            Button("Continue manually", action: onContinueManually)
                .buttonStyle(NTSecondaryButtonStyle())
        }
        .padding(NTSpacing.lg)
    }

    private var unavailableView: some View {
        VStack(spacing: NTSpacing.xl) {
            Spacer()
            ContentUnavailableView(
                "Drafting is temporarily unavailable",
                systemImage: "wand.and.stars.inverse",
                description: Text("Your profile has not changed. You can continue manually and return later.")
            )
            Spacer()
            Button("Continue manually", action: onContinueManually)
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(NTSpacing.lg)
    }

    private var appliedView: some View {
        VStack(spacing: NTSpacing.xl) {
            Spacer()
            ContentUnavailableView("Draft added", systemImage: "checkmark.circle.fill")
            Spacer()
            Button("Continue", action: onContinueManually)
                .buttonStyle(NTPrimaryButtonStyle())
        }
        .padding(NTSpacing.lg)
    }

    private func synchronizeDraft(with status: ResumeEnrichmentStatus) {
        if case .ready(let suggestions) = status, draft == nil {
            draft = suggestions
        }
    }
}

private extension ResumeImportStage {
    var title: String {
        switch self {
        case .readingDocument: "Reading your résumé"
        case .protectingPrivacy: "Removing contact details"
        case .buildingProfile: "Building professional context"
        case .readyToReview: "Ready for your review"
        }
    }

    var detail: String {
        switch self {
        case .readingDocument: "Extracting text securely on this iPhone"
        case .protectingPrivacy: "Email, phone, and links stay out of the draft"
        case .buildingProfile: "Finding roles, scope, expertise, and education"
        case .readyToReview: "Preparing the details you control"
        }
    }
}

private extension String {
    var trimmedForImport: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct NTFormField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var detail: String? = nil
    var contentType: UITextContentType? = nil
    var multiline = false
    var limit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let limit {
                    Text("\(text.count)/\(limit)")
                        .font(.caption)
                        .foregroundStyle(text.count > limit ? NTColor.destructive : NTColor.textSecondary)
                }
            }
            TextField(prompt, text: limitedText, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...6 : 1...1)
                .textContentType(contentType)
                .ntField()
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(NTColor.textSecondary)
            }
        }
    }

    private var limitedText: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                if let limit {
                    text = String(newValue.prefix(limit))
                } else {
                    text = newValue
                }
            }
        )
    }
}

private struct NTGuidanceCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xs) {
            Label(title, systemImage: "quote.opening")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NTColor.accent)
            Text(text).font(.subheadline).foregroundStyle(NTColor.textSecondary)
        }
        .padding(NTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NTColor.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
    }
}

private extension View {
    func ntField() -> some View {
        padding(NTSpacing.md)
            .background(NTColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: NTRadius.field).stroke(NTColor.separator) }
    }
}
