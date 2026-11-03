import Combine
import SwiftUI
import WebKit

struct VideoCastView: View {
    @ObservedObject var cast: CastManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var address = ""
    @State private var browserDestination: BrowserDestination?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Oglądaj wideo na telewizorze", systemImage: "play.tv.fill")
                .font(.title2.bold())

            Text("Wklej adres filmu albo strony z filmem. Mi Box odtworzy wideo bezpośrednio — telefon będzie pilotem.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Adres strony, filmu lub transmisji", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Otwórz stronę") { openAddress() }
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedURL == nil)

                if let url = normalizedURL, Self.isDirectMediaURL(url) {
                    Button("Odtwórz na TV") { cast.castVideo(url) }
                        .buttonStyle(.bordered)
                    .disabled(!cast.isConnected)
                }
            }

            Button {
                cast.castVideo(
                    URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
                    title: "Test MiBox Screen"
                )
            } label: {
                Label("Sprawdź odtwarzanie filmem testowym", systemImage: "checkmark.tv")
            }
            .buttonStyle(.bordered)
            .disabled(!cast.isConnected)

            if let playbackMessage = cast.playbackMessage {
                Label(playbackMessage, systemImage: "arrow.up.forward.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let errorMessage = cast.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !cast.isConnected {
                Text("Najpierw wybierz Mi Box ikoną Cast powyżej.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .sheet(item: $browserDestination) { destination in
            VideoBrowserSheet(initialURL: destination.url, cast: cast)
        }
        .onAppear { consumeSharedURL() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { consumeSharedURL() }
        }
        .alert("MiBox Screen", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var normalizedURL: URL? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let text = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func openAddress() {
        guard let url = normalizedURL else {
            message = "Wpisz poprawny adres internetowy."
            return
        }
        if Self.isDirectMediaURL(url) {
            cast.castVideo(url)
        } else {
            browserDestination = BrowserDestination(url: url)
        }
    }

    private func consumeSharedURL() {
        guard let text = SharedSettings.defaults.string(forKey: SharedSettings.pendingVideoURLKey) else { return }
        SharedSettings.defaults.removeObject(forKey: SharedSettings.pendingVideoURLKey)
        address = text
        if let url = normalizedURL, !Self.isDirectMediaURL(url) {
            browserDestination = BrowserDestination(url: url)
        }
    }

    fileprivate static func isDirectMediaURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".m3u8", ".mpd", ".mp4", ".mov", ".m4v", ".webm"]
            .contains(where: path.hasSuffix)
    }
}

private struct BrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct VideoBrowserSheet: View {
    let initialURL: URL
    @ObservedObject var cast: CastManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = VideoBrowserModel()
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VideoWebView(initialURL: initialURL, model: browser)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(browser.title.isEmpty ? "Wideo" : browser.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Zamknij") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            browser.findPlayableVideo { result in
                                switch result {
                                case .success(let url):
                                    cast.castVideo(url, title: browser.title)
                                case .failure:
                                    message = "Nie znaleziono bezpośredniego filmu na tej stronie. Uruchom film na stronie i spróbuj ponownie. Materiałów zabezpieczonych DRM nie można przejąć z innej aplikacji."
                                }
                            }
                        } label: {
                            Label("Odtwórz na TV", systemImage: "play.tv.fill")
                        }
                        .disabled(!cast.isConnected || browser.isLoading)
                    }
                }
        }
        .alert("MiBox Screen", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}

@MainActor
private final class VideoBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var title = ""
    @Published var isLoading = true
    weak var webView: WKWebView?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        title = webView.title ?? "Wideo"
        isLoading = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func findPlayableVideo(completion: @escaping (Result<URL, Error>) -> Void) {
        let script = """
        (() => {
          const found = [];
          const add = value => {
            if (typeof value === 'string' && /^https?:/i.test(value) && !found.includes(value)) found.push(value);
          };
          document.querySelectorAll('video').forEach(video => {
            add(video.currentSrc); add(video.src);
            video.querySelectorAll('source').forEach(source => add(source.src));
          });
          performance.getEntriesByType('resource').forEach(entry => {
            if (/\\.(m3u8|mpd|mp4|m4v|mov|webm)(\\?|$)/i.test(entry.name)) add(entry.name);
          });
          return found;
        })();
        """
        webView?.evaluateJavaScript(script) { value, error in
            if let error { completion(.failure(error)); return }
            let urls = (value as? [String] ?? []).compactMap(URL.init(string:))
            let preferred = urls.first(where: { ["m3u8", "mpd"].contains($0.pathExtension.lowercased()) })
                ?? urls.first
            if let preferred {
                completion(.success(preferred))
            } else {
                completion(.failure(NSError(domain: "MiBoxScreen.Video", code: 1)))
            }
        }
    }
}

private struct VideoWebView: UIViewRepresentable {
    let initialURL: URL
    @ObservedObject var model: VideoBrowserModel

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = model
        model.webView = webView
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
