import StoreKit
import SwiftUI

@MainActor
final class SubscriptionStore: ObservableObject {
    static let monthlyProductID = "com.mesbahtanvir.networkto.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isEntitled = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var latestSignedTransaction: String?
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                self?.latestSignedTransaction = update.jwsRepresentation
                await self?.refreshEntitlement()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var displayPrice: String { product?.displayPrice ?? "$9.99" }

    func prepare() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            product = try await Product.products(for: [Self.monthlyProductID]).first
            await refreshEntitlement()
        } catch {
            errorMessage = "The App Store is unavailable right now. Please try again later."
        }
    }

    func purchase(appAccountToken: UUID) async -> String? {
        guard let product else {
            errorMessage = "This membership is not available in the App Store yet."
            return nil
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "Apple could not verify this purchase. No charge was applied by network.to."
                    return nil
                }
                await transaction.finish()
                await refreshEntitlement()
                latestSignedTransaction = verification.jwsRepresentation
                return verification.jwsRepresentation
            case .pending:
                errorMessage = "This purchase is awaiting approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase could not be completed."
            }
        } catch {
            errorMessage = "The purchase could not be completed. Please try again."
        }
        return nil
    }

    func restore() async -> String? {
        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlement()
            if !isEntitled {
                errorMessage = "No active membership was found for this Apple Account."
            }
        } catch {
            errorMessage = "Purchases could not be restored right now."
        }
        return latestSignedTransaction
    }

    func refreshEntitlement() async {
        var foundActiveMembership = false
        var signedTransaction: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.monthlyProductID,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            foundActiveMembership = true
            signedTransaction = result.jwsRepresentation
            break
        }
        isEntitled = foundActiveMembership
        latestSignedTransaction = signedTransaction
    }
}
