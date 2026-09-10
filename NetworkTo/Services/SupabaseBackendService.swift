import CryptoKit
import Foundation
import PDFKit
import Security
import Supabase
import Vision

actor SupabaseBackendService: BackendService {
    nonisolated let isLive = true

    private let client: SupabaseClient
    private let configuration: SupabaseConfiguration

    init(configuration: SupabaseConfiguration) {
        self.configuration = configuration
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    func hasValidSession() async -> Bool {
        (try? await client.auth.session) != nil
    }

    func bootstrap() async throws -> BackendSnapshot {
        let user = try await client.auth.user()
        async let profileRequest: ProfileRow = client
            .from("profiles")
            .select()
            .eq("id", value: user.id.uuidString)
            .single()
            .execute()
            .value
        async let experiencesRequest: [ExperienceRow] = client
            .from("professional_experiences")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .order("position")
            .execute()
            .value
        async let networkingRequest: NetworkingPreferencesRow = client
            .from("networking_preferences")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .single()
            .execute()
            .value
        async let meetingRequest: MeetingPreferencesRow = client
            .from("meeting_preferences")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .single()
            .execute()
            .value
        async let availabilityRequest: [AvailabilityRow] = client
            .from("availabilities")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .limit(1)
            .execute()
            .value
        async let safetyRequest: SafetyPreferencesRow = client
            .rpc("get_safety_preferences")
            .execute()
            .value
        async let membershipRequest: MembershipStatusRow = client
            .rpc("get_membership_status")
            .execute()
            .value

        let profileRow = try await profileRequest
        let experiences = try await experiencesRequest
        let networking = try await networkingRequest
        let meeting = try await meetingRequest
        let availabilityRows = try await availabilityRequest
        let safety = try await safetyRequest
        let membership = try await membershipRequest
        let introductionState = try await currentIntroduction()
        let conversation = try await activeConversation(currentUserID: user.id)
        let connections = try await currentConnections()

        var profile = profileRow.profile
        profile.professionalHistory = experiences.map(\.experience)

        return BackendSnapshot(
            verifiedWorkEmail: profileRow.email ?? user.email ?? "",
            member: profile,
            introduction: introductionState?.introduction,
            conversation: conversation,
            connections: connections,
            networkingPreferences: networking.preferences,
            meetingPreferences: meeting.preferences,
            safetyPreferences: safety.preferences,
            availability: availabilityRows.first?.availability,
            onboardingComplete: profileRow.onboardingComplete ?? false,
            waitingForReciprocalInterest: introductionState?.isWaiting ?? false,
            membership: membership.membership
        )
    }

    func validateCompany(email: String) async throws -> CompanyDomainDecision {
        let domain = email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
        let response: CompanyDomainResponse = try await client
            .rpc("validate_company_domain", params: DomainParameters(requestedDomain: domain))
            .execute()
            .value
        switch response.decision {
        case "eligible": return .eligible(company: response.companyName ?? domain, domain: response.domain)
        case "review_required": return .reviewRequired(domain: response.domain)
        default: return .ineligible(reason: "Use an approved company email to join network.to.")
        }
    }

    func sendMagicLink(to email: String, shouldCreateUser: Bool) async throws -> MagicLinkRequest {
        let handoff = MagicLinkRequest(
            id: UUID(),
            claimSecret: try makeClaimSecret(),
            email: email,
            isSignUp: shouldCreateUser
        )
        let createResponse = try await callAuthHandoff(
            AuthHandoffRequest(
                action: "create",
                requestID: handoff.id,
                claimSecretHash: sha256Hex(handoff.claimSecret),
                claimSecret: nil
            )
        )
        guard createResponse.statusCode == 201 else { throw SupabaseBackendError.requestFailed }

        var redirect = URLComponents(
            url: configuration.url.appending(path: "functions/v1/auth-handoff"),
            resolvingAgainstBaseURL: false
        )
        redirect?.queryItems = [
            URLQueryItem(name: "request_id", value: handoff.id.uuidString.lowercased())
        ]
        guard let redirectURL = redirect?.url else { throw SupabaseBackendError.invalidResponse }

        try await client.auth.signInWithOTP(
            email: email,
            redirectTo: redirectURL,
            shouldCreateUser: shouldCreateUser
        )
        try persistPendingMagicLink(handoff)
        return handoff
    }

    func pendingMagicLinkRequest() async -> MagicLinkRequest? {
        guard let request = try? loadPendingMagicLink() else { return nil }
        guard request.createdAt.addingTimeInterval(10 * 60) > Date() else {
            clearPendingMagicLink()
            return nil
        }
        return request
    }

    func clearPendingMagicLinkRequest() async {
        clearPendingMagicLink()
    }

    func claimMagicLink(_ request: MagicLinkRequest) async throws -> Bool {
        let response = try await callAuthHandoff(
            AuthHandoffRequest(
                action: "claim",
                requestID: request.id,
                claimSecretHash: nil,
                claimSecret: request.claimSecret
            )
        )
        guard response.statusCode == 200 || response.statusCode == 202 else {
            throw SupabaseBackendError.requestFailed
        }
        let payload = try JSONDecoder().decode(AuthHandoffResponse.self, from: response.data)
        guard let authCode = payload.authCode else { return false }
        _ = try await client.auth.exchangeCodeForSession(authCode: authCode)
        clearPendingMagicLink()
        return true
    }

    func acceptMagicLinkCallback(_ url: URL) async throws {
        guard url.scheme == "networkto", url.host == "auth" else {
            throw SupabaseBackendError.invalidResponse
        }
        if (try? await client.auth.session) == nil {
            try await client.auth.session(from: url)
        }
        clearPendingMagicLink()
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func synchronizeAppStoreTransaction(_ signedTransaction: String) async throws {
        try await client.functions.invoke(
            "sync-subscription",
            options: FunctionInvokeOptions(body: SubscriptionSyncRequest(signedTransaction: signedTransaction))
        )
    }

    func updateStream() async throws -> AsyncStream<Void> {
        let channel = client.channel("network-to-member-updates")
        let events = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "notification_events"
        )
        try await channel.subscribeWithError()

        return AsyncStream { continuation in
            let forwardingTask = Task {
                for await _ in events {
                    guard !Task.isCancelled else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                forwardingTask.cancel()
                Task { await channel.unsubscribe() }
            }
        }
    }

    func saveProfile(_ profile: ProfessionalProfile, onboardingComplete: Bool) async throws {
        try await client
            .rpc(
                "save_professional_profile",
                params: ProfileSaveParameters(profile: profile, onboardingComplete: onboardingComplete)
            )
            .execute()
    }

    func saveNetworkingPreferences(_ preferences: NetworkingPreferences) async throws {
        let user = try await client.auth.user()
        try await client
            .from("networking_preferences")
            .update(NetworkingPreferencesUpdate(preferences: preferences))
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }

    func saveMeetingPreferences(_ preferences: MeetingPreferences) async throws {
        let user = try await client.auth.user()
        try await client
            .from("meeting_preferences")
            .update(MeetingPreferencesUpdate(preferences: preferences))
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }

    func saveAvailability(_ availability: TodayAvailability?) async throws {
        let user = try await client.auth.user()
        if let availability {
            try await client
                .from("availabilities")
                .upsert(AvailabilityUpsert(userID: user.id, availability: availability), onConflict: "user_id")
                .execute()
        } else {
            try await client
                .from("availabilities")
                .delete()
                .eq("user_id", value: user.id.uuidString)
                .execute()
        }
    }

    func respondToIntroduction(_ id: UUID, interested: Bool) async throws -> BackendIntroductionResult {
        let response: IntroductionResponsePayload = try await client
            .rpc(
                "respond_to_introduction",
                params: IntroductionResponseParameters(
                    introductionID: id,
                    decision: interested ? "interested" : "pass"
                )
            )
            .execute()
            .value
        switch response.state {
        case "mutual":
            guard let id = response.conversationID else { throw SupabaseBackendError.invalidResponse }
            return .mutual(conversationID: id)
        case "not_mutual": return .notMutual
        default: return .waiting
        }
    }

    func deliverMessage(_ body: String, conversationID: UUID?, idempotencyKey: UUID) async throws {
        guard let conversationID else { throw SupabaseBackendError.missingConversation }
        try await client
            .rpc(
                "send_message",
                params: SendMessageParameters(
                    messageID: idempotencyKey,
                    conversationID: conversationID,
                    body: body
                )
            )
            .execute()
    }

    func createMeetup(conversationID: UUID, detail: String) async throws {
        let proposedTime = Date().addingTimeInterval(86_400)
        try await client
            .rpc(
                "create_meetup",
                params: MeetupParameters(
                    conversationID: conversationID,
                    startsAt: proposedTime,
                    placeName: detail,
                    area: "In your city"
                )
            )
            .execute()
    }

    func recordMeetupFeedback(conversationID: UUID, outcome: MeetupOutcome, stayConnected: Bool) async throws {
        try await client
            .rpc(
                "submit_latest_meetup_feedback",
                params: MeetupFeedbackParameters(
                    conversationID: conversationID,
                    outcome: outcome.databaseValue,
                    stayConnected: stayConnected,
                    privateNote: ""
                )
            )
            .execute()
    }

    func endConversation(_ id: UUID) async throws {
        try await client
            .rpc("end_conversation", params: ConversationParameters(conversationID: id))
            .execute()
    }

    func blockMember(_ id: UUID) async throws {
        try await client
            .rpc("block_member", params: MemberParameters(memberID: id))
            .execute()
    }

    func unblockMember(named name: String) async throws {
        try await client
            .rpc("unblock_member_by_name", params: MemberNameParameters(memberName: name))
            .execute()
    }

    func removeConnection(_ id: UUID) async throws {
        try await client
            .from("connections")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func processResume(
        fileURL: URL,
        progress: @escaping @Sendable (ResumeImportStage) async -> Void
    ) async throws -> ProfileImportSuggestions? {
        await progress(.readingDocument)
        guard fileURL.pathExtension.lowercased() == "pdf" else {
            throw SupabaseBackendError.invalidResume
        }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw SupabaseBackendError.invalidResume }
        guard (values.fileSize ?? 0) <= 10 * 1_024 * 1_024 else {
            throw SupabaseBackendError.resumeTooLarge
        }

        let extractedText = try ResumeTextExtractor.extractRawText(from: fileURL)
        await progress(.protectingPrivacy)
        let protectedText = try ResumeTextExtractor.protect(extractedText)

        let session = try await client.auth.session
        await progress(.buildingProfile)
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/process-resume"))
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(ResumeProcessingRequest(resumeText: protectedText))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseBackendError.requestFailed }
        if http.statusCode == 501 {
            throw SupabaseBackendError.resumeProcessingUnavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseBackendError.resumeProcessingFailed
        }
        let payload = try JSONDecoder().decode(ResumeProcessingResponse.self, from: data)
        await progress(.readyToReview)
        return payload.suggestions?.profileDraft
    }

    func submitReport(
        category: ReportCategory,
        note: String,
        subjectID: UUID?,
        conversationID: UUID?
    ) async throws {
        guard let subjectID else { throw SupabaseBackendError.invalidReport }
        try await client
            .rpc(
                "submit_member_report",
                params: ReportParameters(
                    subjectID: subjectID,
                    conversationID: conversationID,
                    category: category.databaseValue,
                    note: note
                )
            )
            .execute()
    }

    func deleteAccount() async throws {
        let session = try await client.auth.session
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/delete-account"))
        request.httpMethod = "DELETE"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 204 else {
            throw SupabaseBackendError.requestFailed
        }
        try await client.auth.signOut()
    }

    private func currentIntroduction() async throws -> (introduction: Introduction, isWaiting: Bool)? {
        let envelope: IntroductionEnvelope? = try await client
            .rpc("get_current_introduction")
            .execute()
            .value
        return envelope.map { ($0.introduction, $0.yourResponse == "interested") }
    }

    private func currentConnections() async throws -> [Connection] {
        let response: [ConnectionEnvelope] = try await client
            .rpc("get_connections")
            .execute()
            .value
        return response.map(\.connection)
    }

    private func activeConversation(currentUserID: UUID) async throws -> Conversation? {
        let envelope: ConversationEnvelope? = try await client
            .rpc("get_active_conversation")
            .execute()
            .value
        return envelope?.conversation(currentUserID: currentUserID)
    }

    private func callAuthHandoff(_ payload: AuthHandoffRequest) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/auth-handoff"))
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseBackendError.requestFailed }
        return (data, http.statusCode)
    }

    private func makeClaimSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SupabaseBackendError.secureRandomFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var pendingMagicLinkQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.mesbahtanvir.networkto.auth",
            kSecAttrAccount: "pending-magic-link"
        ]
    }

    private func persistPendingMagicLink(_ request: MagicLinkRequest) throws {
        let data = try JSONEncoder().encode(request)
        SecItemDelete(pendingMagicLinkQuery as CFDictionary)
        var attributes = pendingMagicLinkQuery
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw SupabaseBackendError.secureStorageFailed
        }
    }

    private func loadPendingMagicLink() throws -> MagicLinkRequest? {
        var query = pendingMagicLinkQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SupabaseBackendError.secureStorageFailed
        }
        return try JSONDecoder().decode(MagicLinkRequest.self, from: data)
    }

    private func clearPendingMagicLink() {
        SecItemDelete(pendingMagicLinkQuery as CFDictionary)
    }
}

private enum ResumeTextExtractor {
    private static let maximumPages = 12
    private static let maximumCharacters = 40_000
    private static let minimumReadableCharacters = 80

    static func extractRawText(from fileURL: URL) throws -> String {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            throw SupabaseBackendError.invalidResume
        }

        var pageText: [String] = []
        for index in 0..<min(document.pageCount, maximumPages) {
            guard let page = document.page(at: index) else { continue }
            let embeddedText = normalized(page.string ?? "")
            if embeddedText.count >= 40 {
                pageText.append(embeddedText)
            } else if let image = render(page), let recognizedText = try? recognizeText(in: image) {
                let normalizedText = normalized(recognizedText)
                if !normalizedText.isEmpty { pageText.append(normalizedText) }
            }
        }

        let readableText = normalized(pageText.joined(separator: "\n\n"))
        guard readableText.count >= minimumReadableCharacters else {
            throw SupabaseBackendError.resumeHasNoReadableText
        }
        return readableText
    }

    static func protect(_ text: String) throws -> String {
        let protectedText = redactContactDetails(in: text)
        guard protectedText.count >= minimumReadableCharacters else {
            throw SupabaseBackendError.resumeHasNoReadableText
        }
        return String(protectedText.prefix(maximumCharacters))
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        return (request.results ?? [])
            .sorted {
                if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.015 {
                    return $0.boundingBox.maxY > $1.boundingBox.maxY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = min(3, 2_400 / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private static func redactContactDetails(in text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(?:https?://|www\.)\S+"#,
            #"(?<!\w)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\w)"#,
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "[contact detail removed]")
        }
        return result
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .split(whereSeparator: \Character.isNewline)
            .map { $0.split(whereSeparator: \Character.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private enum SupabaseBackendError: LocalizedError {
    case invalidResponse
    case missingConversation
    case invalidReport
    case requestFailed
    case invalidResume
    case resumeTooLarge
    case resumeHasNoReadableText
    case resumeProcessingUnavailable
    case resumeProcessingFailed
    case secureRandomFailed
    case secureStorageFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an unexpected response."
        case .missingConversation: "A mutual conversation is required before sending a message."
        case .invalidReport: "Choose a member to report."
        case .requestFailed: "The request could not be completed."
        case .invalidResume: "Choose a valid PDF résumé."
        case .resumeTooLarge: "Choose a PDF smaller than 10 MB."
        case .resumeHasNoReadableText: "We couldn’t read text from that résumé. Try a clearer PDF or an exported, text-based copy."
        case .resumeProcessingUnavailable: "Résumé prefill is temporarily unavailable. Your PDF stayed on this iPhone and was not uploaded."
        case .resumeProcessingFailed: "We couldn’t build a profile draft from that résumé. Your PDF was not uploaded."
        case .secureRandomFailed: "A secure sign-in request could not be created."
        case .secureStorageFailed: "The secure sign-in request could not be saved on this iPhone."
        }
    }
}

private struct AuthHandoffRequest: Encodable {
    let action: String
    let requestID: UUID
    let claimSecretHash: String?
    let claimSecret: String?

    enum CodingKeys: String, CodingKey {
        case action
        case requestID = "request_id"
        case claimSecretHash = "claim_secret_hash"
        case claimSecret = "claim_secret"
    }
}

private struct AuthHandoffResponse: Decodable {
    let status: String
    let authCode: String?

    enum CodingKeys: String, CodingKey {
        case status
        case authCode = "auth_code"
    }
}

private struct SubscriptionSyncRequest: Encodable {
    let signedTransaction: String
    enum CodingKeys: String, CodingKey { case signedTransaction = "signed_transaction" }
}

private struct DomainParameters: Encodable { let requestedDomain: String
    enum CodingKeys: String, CodingKey { case requestedDomain = "requested_domain" }
}
private struct CompanyDomainResponse: Decodable {
    let decision: String
    let domain: String
    let companyName: String?
    enum CodingKeys: String, CodingKey { case decision, domain; case companyName = "company_name" }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let email: String?
    let companyName: String
    let name: String
    let role: String
    let city: String
    let topics: [String]
    let bio: String
    let roleScope: String
    let currentFocus: String
    let yearsExperience: String
    let growthAreas: [String]
    let professionalAmbition: String
    let growthInterest: String
    let contributionAreas: [String]
    let helpFormats: [String]
    let contribution: String
    let contributionBoundaries: String
    let education: String?
    let onboardingComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email, name, role, city, topics, bio, contribution, education
        case companyName = "company_name"
        case roleScope = "role_scope"
        case currentFocus = "current_focus"
        case yearsExperience = "years_experience"
        case growthAreas = "growth_areas"
        case professionalAmbition = "professional_ambition"
        case growthInterest = "growth_interest"
        case contributionAreas = "contribution_areas"
        case helpFormats = "help_formats"
        case contributionBoundaries = "contribution_boundaries"
        case onboardingComplete = "onboarding_complete"
    }

    var profile: ProfessionalProfile {
        ProfessionalProfile(
            id: id,
            name: name,
            role: role,
            company: companyName,
            city: city,
            topics: topics,
            bio: bio,
            roleScope: roleScope,
            currentFocus: currentFocus,
            yearsExperience: yearsExperience,
            growthAreas: growthAreas,
            professionalAmbition: professionalAmbition,
            growthInterest: growthInterest,
            contributionAreas: contributionAreas,
            helpFormats: helpFormats,
            contribution: contribution,
            contributionBoundaries: contributionBoundaries,
            isWorkEmailVerified: true,
            education: education ?? ""
        )
    }
}

private struct ExperienceRow: Decodable {
    let id: UUID
    let role: String
    let company: String
    let period: String
    var experience: ProfessionalExperience { ProfessionalExperience(id: id, role: role, company: company, period: period) }
}

private struct NetworkingPreferencesRow: Decodable {
    let frequency: String
    let goals: [String]
    let relationshipMix: String
    let crossCompany: Bool
    let crossIndustry: Bool
    enum CodingKeys: String, CodingKey {
        case frequency, goals
        case relationshipMix = "relationship_mix"
        case crossCompany = "cross_company"
        case crossIndustry = "cross_industry"
    }
    var preferences: NetworkingPreferences {
        NetworkingPreferences(
            frequency: IntroductionFrequency(databaseValue: frequency),
            goals: Set(goals),
            relationshipMix: relationshipMix,
            crossCompany: crossCompany,
            crossIndustry: crossIndustry
        )
    }
}

private struct MeetingPreferencesRow: Decodable {
    let areas: [String]
    let formats: [String]
    let windows: [String]
    var preferences: MeetingPreferences {
        MeetingPreferences(
            areas: Set(areas.compactMap(TodayAvailability.Area.init(rawValue:))),
            formats: Set(formats),
            windows: Set(windows.compactMap(TodayAvailability.Window.init(rawValue:)))
        )
    }
}

private struct SafetyPreferencesRow: Decodable {
    let blockedMembers: [String]
    enum CodingKeys: String, CodingKey { case blockedMembers = "blocked_members" }
    var preferences: SafetyPreferences { SafetyPreferences(blockedMembers: blockedMembers) }
}

private struct MembershipStatusRow: Decodable {
    let state: MembershipState
    let trialStartedAt: Date?
    let trialEndsAt: Date?
    let accessEndsAt: Date?
    let autoRenews: Bool?

    enum CodingKeys: String, CodingKey {
        case state
        case trialStartedAt = "trial_started_at"
        case trialEndsAt = "trial_ends_at"
        case accessEndsAt = "access_ends_at"
        case autoRenews = "auto_renews"
    }

    var membership: MembershipStatus {
        MembershipStatus(
            state: state,
            trialStartedAt: trialStartedAt,
            trialEndsAt: trialEndsAt,
            accessEndsAt: accessEndsAt,
            autoRenews: autoRenews ?? false
        )
    }
}

private struct AvailabilityRow: Decodable {
    let area: String
    let timeWindow: String
    let expiresAt: Date
    enum CodingKeys: String, CodingKey { case area; case timeWindow = "time_window"; case expiresAt = "expires_at" }
    var availability: TodayAvailability? {
        guard let area = TodayAvailability.Area(rawValue: area),
              let window = TodayAvailability.Window(rawValue: timeWindow) else { return nil }
        return TodayAvailability(area: area, window: window, expiresAt: expiresAt)
    }
}

private struct IntroductionEnvelope: Decodable {
    let id: UUID
    let person: ProfileRow
    let reasonForYou: String
    let reasonForThem: String
    let meetingContext: String
    let createdAt: Date
    let yourResponse: String?
    enum CodingKeys: String, CodingKey {
        case id, person
        case reasonForYou = "reason_for_you"
        case reasonForThem = "reason_for_them"
        case meetingContext = "meeting_context"
        case createdAt = "created_at"
        case yourResponse = "your_response"
    }
    var introduction: Introduction {
        Introduction(id: id, person: person.profile, reasonForYou: reasonForYou, reasonForThem: reasonForThem, meetingContext: meetingContext, createdAt: createdAt)
    }
}

private struct ConnectionEnvelope: Decodable {
    let id: UUID
    let person: ProfileRow
    let connectedAt: Date
    let origin: String
    let meetingHistory: [MeetingHistoryEnvelope]
    enum CodingKeys: String, CodingKey { case id, person, origin; case connectedAt = "connected_at"; case meetingHistory = "meeting_history" }
    var connection: Connection {
        Connection(id: id, person: person.profile, connectedAt: connectedAt, origin: origin, meetingHistory: meetingHistory.compactMap(\.record))
    }
}

private struct MeetingHistoryEnvelope: Decodable {
    let id: UUID
    let date: Date?
    let summary: String
    var record: MeetupRecord? { date.map { MeetupRecord(id: id, date: $0, summary: summary) } }
}

private struct ConversationEnvelope: Decodable {
    let id: UUID
    let status: String
    let introductionReason: String
    let person: ProfileRow
    let messages: [MessageEnvelope]
    let meetup: MeetupEnvelope?
    enum CodingKeys: String, CodingKey { case id, status, person, messages, meetup; case introductionReason = "introduction_reason" }
    func conversation(currentUserID: UUID) -> Conversation {
        Conversation(
            id: id,
            person: person.profile,
            introductionReason: introductionReason,
            messages: messages.map { $0.message(currentUserID: currentUserID) },
            isUnread: false,
            meetupStatus: meetup?.statusValue ?? .coordinating,
            isEnded: status != "active",
            isBlocked: status == "blocked"
        )
    }
}

private struct MessageEnvelope: Decodable {
    let id: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, body; case senderID = "sender_id"; case createdAt = "created_at" }
    func message(currentUserID: UUID) -> ChatMessage {
        ChatMessage(id: id, author: senderID == currentUserID ? .member : .introduction, body: body, sentAt: createdAt)
    }
}

private struct MeetupEnvelope: Decodable {
    let startsAt: Date?
    let placeName: String?
    let area: String?
    let status: String
    enum CodingKeys: String, CodingKey { case status, area; case startsAt = "starts_at"; case placeName = "place_name" }
    var statusValue: MeetupStatus {
        switch status {
        case "feedback_due": return .feedbackDue
        case "completed": return .completed
        case "proposed", "confirmed": return .planned([startsAt?.formatted(date: .abbreviated, time: .shortened), placeName, area].compactMap { $0 }.joined(separator: " · "))
        default: return .coordinating
        }
    }
}

private struct ProfileUpdate: Encodable {
    let name: String; let role: String; let city: String; let topics: [String]; let bio: String
    let roleScope: String; let currentFocus: String; let yearsExperience: String; let growthAreas: [String]
    let professionalAmbition: String; let growthInterest: String; let contributionAreas: [String]
    let helpFormats: [String]; let contribution: String; let contributionBoundaries: String; let education: String
    let onboardingComplete: Bool
    init(profile: ProfessionalProfile, onboardingComplete: Bool) {
        name = profile.name; role = profile.role; city = profile.city; topics = profile.topics; bio = profile.bio
        roleScope = profile.roleScope; currentFocus = profile.currentFocus; yearsExperience = profile.yearsExperience
        growthAreas = profile.growthAreas; professionalAmbition = profile.professionalAmbition; growthInterest = profile.growthInterest
        contributionAreas = profile.contributionAreas; helpFormats = profile.helpFormats; contribution = profile.contribution
        contributionBoundaries = profile.contributionBoundaries; education = profile.education; self.onboardingComplete = onboardingComplete
    }
    enum CodingKeys: String, CodingKey {
        case name, role, city, topics, bio, contribution, education
        case roleScope = "role_scope"; case currentFocus = "current_focus"; case yearsExperience = "years_experience"
        case growthAreas = "growth_areas"; case professionalAmbition = "professional_ambition"; case growthInterest = "growth_interest"
        case contributionAreas = "contribution_areas"; case helpFormats = "help_formats"; case contributionBoundaries = "contribution_boundaries"
        case onboardingComplete = "onboarding_complete"
    }
}

private struct ProfileSaveParameters: Encodable {
    let profile: ProfileUpdate
    let experiences: [ExperienceUpdate]
    let onboardingComplete: Bool

    init(profile: ProfessionalProfile, onboardingComplete: Bool) {
        self.profile = ProfileUpdate(profile: profile, onboardingComplete: onboardingComplete)
        self.experiences = profile.professionalHistory.map(ExperienceUpdate.init)
        self.onboardingComplete = onboardingComplete
    }

    enum CodingKeys: String, CodingKey {
        case profile = "p_profile"
        case experiences = "p_experiences"
        case onboardingComplete = "p_onboarding_complete"
    }
}

private struct ExperienceUpdate: Encodable {
    let id: UUID
    let role: String
    let company: String
    let period: String

    init(_ experience: ProfessionalExperience) {
        id = experience.id
        role = experience.role
        company = experience.company
        period = experience.period
    }
}

private struct NetworkingPreferencesUpdate: Encodable {
    let frequency: String; let goals: [String]; let relationshipMix: String; let crossCompany: Bool; let crossIndustry: Bool
    init(preferences: NetworkingPreferences) {
        frequency = preferences.frequency.databaseValue; goals = preferences.goals.sorted(); relationshipMix = preferences.relationshipMix
        crossCompany = preferences.crossCompany; crossIndustry = preferences.crossIndustry
    }
    enum CodingKeys: String, CodingKey { case frequency, goals; case relationshipMix = "relationship_mix"; case crossCompany = "cross_company"; case crossIndustry = "cross_industry" }
}

private struct MeetingPreferencesUpdate: Encodable {
    let areas: [String]; let formats: [String]; let windows: [String]
    init(preferences: MeetingPreferences) {
        areas = preferences.areas.map(\.rawValue).sorted(); formats = preferences.formats.sorted(); windows = preferences.windows.map(\.rawValue).sorted()
    }
}
private struct AvailabilityUpsert: Encodable {
    let userID: UUID; let area: String; let timeWindow: String; let expiresAt: Date
    init(userID: UUID, availability: TodayAvailability) {
        self.userID = userID; area = availability.area.rawValue; timeWindow = availability.window.rawValue; expiresAt = availability.expiresAt
    }
    enum CodingKeys: String, CodingKey { case userID = "user_id"; case area; case timeWindow = "time_window"; case expiresAt = "expires_at" }
}
private struct IntroductionResponseParameters: Encodable {
    let introductionID: UUID; let decision: String
    enum CodingKeys: String, CodingKey { case introductionID = "p_introduction_id"; case decision = "p_decision" }
}
private struct IntroductionResponsePayload: Decodable {
    let state: String; let conversationID: UUID?
    enum CodingKeys: String, CodingKey { case state; case conversationID = "conversation_id" }
}
private struct SendMessageParameters: Encodable {
    let messageID: UUID
    let conversationID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case conversationID = "p_conversation_id"
        case body = "p_body"
    }
}
private struct ResumeProcessingRequest: Encodable {
    let resumeText: String
    enum CodingKeys: String, CodingKey { case resumeText = "resume_text" }
}
private struct ResumeProcessingResponse: Decodable {
    let status: String
    let suggestions: ResumeSuggestionsPayload?
}
private struct ResumeSuggestionsPayload: Decodable {
    let name: String
    let role: String
    let city: String
    let roleScope: String
    let currentFocus: String
    let yearsExperience: String
    let education: String
    let topics: [String]
    let professionalHistory: [ResumeExperiencePayload]
    let contributionAreas: [String]
    let experienceSummary: String

    enum CodingKeys: String, CodingKey {
        case name, role, city, topics
        case roleScope = "role_scope"
        case currentFocus = "current_focus"
        case yearsExperience = "years_experience"
        case education
        case professionalHistory = "professional_history"
        case contributionAreas = "contribution_areas"
        case experienceSummary = "experience_summary"
    }

    var profileDraft: ProfileImportSuggestions {
        ProfileImportSuggestions(
            name: name.nilIfEmpty,
            role: role.nilIfEmpty,
            city: city.nilIfEmpty,
            roleScope: roleScope.nilIfEmpty,
            yearsExperience: yearsExperience.nilIfEmpty,
            currentFocus: currentFocus.nilIfEmpty,
            education: education.nilIfEmpty,
            topics: topics,
            professionalHistory: professionalHistory.map {
                ProfessionalExperience(id: UUID(), role: $0.role, company: $0.company, period: $0.period)
            },
            contributionAreas: contributionAreas,
            experienceSummary: experienceSummary.nilIfEmpty
        )
    }
}
private struct ResumeExperiencePayload: Decodable {
    let role: String
    let company: String
    let period: String
}
private struct MeetupParameters: Encodable {
    let conversationID: UUID; let startsAt: Date; let placeName: String; let area: String
    enum CodingKeys: String, CodingKey { case conversationID = "p_conversation_id"; case startsAt = "p_starts_at"; case placeName = "p_place_name"; case area = "p_area" }
}
private struct MeetupFeedbackParameters: Encodable {
    let conversationID: UUID; let outcome: String; let stayConnected: Bool; let privateNote: String
    enum CodingKeys: String, CodingKey {
        case conversationID = "p_conversation_id"; case outcome = "p_outcome"
        case stayConnected = "p_stay_connected"; case privateNote = "p_private_note"
    }
}
private struct ConversationParameters: Encodable {
    let conversationID: UUID
    enum CodingKeys: String, CodingKey { case conversationID = "p_conversation_id" }
}
private struct MemberParameters: Encodable {
    let memberID: UUID
    enum CodingKeys: String, CodingKey { case memberID = "p_member_id" }
}
private struct MemberNameParameters: Encodable {
    let memberName: String
    enum CodingKeys: String, CodingKey { case memberName = "p_member_name" }
}
private struct ReportParameters: Encodable {
    let subjectID: UUID; let conversationID: UUID?; let category: String; let note: String
    enum CodingKeys: String, CodingKey { case subjectID = "p_subject_id"; case conversationID = "p_conversation_id"; case category = "p_category"; case note = "p_note" }
}

private extension IntroductionFrequency {
    init(databaseValue: String) {
        self = switch databaseValue {
        case "twice_monthly": .twiceMonthly
        case "monthly": .monthly
        case "exceptional_only": .exceptionalOnly
        case "paused": .paused
        default: .weekly
        }
    }
    var databaseValue: String {
        switch self {
        case .weekly: "weekly"
        case .twiceMonthly: "twice_monthly"
        case .monthly: "monthly"
        case .exceptionalOnly: "exceptional_only"
        case .paused: "paused"
        }
    }
}

private extension ReportCategory {
    var databaseValue: String {
        switch self {
        case .harassment: "harassment"
        case .spam: "spam"
        case .fraud: "fraud"
        case .inappropriate: "inappropriate"
        case .romantic: "romantic"
        case .discrimination: "discrimination"
        case .threatening: "threatening"
        case .other: "other"
        }
    }
}

private extension MeetupOutcome {
    var databaseValue: String {
        switch self {
        case .great: "good"
        case .good: "okay"
        case .weak: "not_for_me"
        case .didNotMeet: "did_not_meet"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
