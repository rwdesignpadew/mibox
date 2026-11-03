import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Przygotowuję link do MiBox Screen…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        importSharedURL()
    }

    private func importSharedURL() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
            finish(with: "Udostępniony element nie zawiera adresu filmu ani strony.")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let url = item as? URL ?? (item as? String).flatMap(URL.init(string:))
                guard error == nil, let url else {
                    self.finish(with: "Nie udało się odczytać udostępnionego adresu.")
                    return
                }
                SharedSettings.defaults.set(url.absoluteString, forKey: SharedSettings.pendingVideoURLKey)
                self.finish(with: "Link zapisany. Otwórz MiBox Screen i wybierz „Odtwórz na TV”.")
            }
        }
    }

    private func finish(with text: String) {
        statusLabel.text = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
