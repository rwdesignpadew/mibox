import Combine
import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let proProductID = "pl.miboxscreen.ios.pro"

    @Published private(set) var product: Product?
    @Published private(set) var isPro: Bool
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        isPro = SharedSettings.defaults.bool(forKey: SharedSettings.proKey)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlement()
                }
            }
        }
        Task { await prepare() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        do {
            product = try await Product.products(for: [Self.proProductID]).first
            await refreshEntitlement()
        } catch {
            errorMessage = "Nie udało się pobrać oferty Pro. Spróbuj ponownie później."
        }
    }

    func purchase() async {
        guard let product else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try verified(result)
                await transaction.finish()
                await refreshEntitlement()
            case .pending:
                errorMessage = "Zakup oczekuje na zatwierdzenie."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Zakup nie został ukończony. Spróbuj ponownie."
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            errorMessage = "Nie udało się przywrócić zakupu."
        }
    }

    private func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID, transaction.revocationDate == nil {
                entitled = true
                break
            }
        }
        isPro = entitled
        SharedSettings.defaults.set(entitled, forKey: SharedSettings.proKey)
    }

    nonisolated private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreError.failedVerification
        }
    }

    private enum StoreError: Error {
        case failedVerification
    }
}
