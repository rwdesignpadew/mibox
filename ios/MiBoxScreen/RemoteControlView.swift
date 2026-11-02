import SwiftUI

struct RemoteControlView: View {
    let serverURL: String
    let roomCode: String

    @State private var errorMessage: String?
    @State private var currentAd: RemoteHouseAd?
    @AppStorage(SharedSettings.proKey, store: SharedSettings.defaults)
    private var isPro = false
    @AppStorage(SharedSettings.remoteLastAdDateKey, store: SharedSettings.defaults)
    private var lastAdDate = 0.0

    var body: some View {
        VStack(spacing: 22) {
            Text("Pilot Mi Box")
                .font(.largeTitle.bold())

            remoteButton("chevron.up", command: "up")
            HStack(spacing: 34) {
                remoteButton("chevron.left", command: "left")
                remoteButton("circle.inset.filled", command: "ok", accessibilityLabel: "OK")
                remoteButton("chevron.right", command: "right")
            }
            remoteButton("chevron.down", command: "down")

            Divider()

            HStack(spacing: 24) {
                remoteButton("house.fill", command: "home", accessibilityLabel: "Ekran główny")
                remoteButton("arrow.uturn.backward", command: "back", accessibilityLabel: "Wstecz")
                remoteButton("playpause.fill", command: "play_pause", accessibilityLabel: "Odtwarzaj lub zatrzymaj")
            }

            HStack(spacing: 30) {
                remoteButton("speaker.minus.fill", command: "volume_down", accessibilityLabel: "Ciszej")
                remoteButton("speaker.plus.fill", command: "volume_up", accessibilityLabel: "Głośniej")
            }

            Text("Przy pierwszym użyciu włącz „MiBox Screen Remote” w Ustawieniach dostępności na telewizorze.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top)
        }
        .padding(24)
        .navigationTitle("Pilot")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let currentAd, !isPro {
                HStack(spacing: 10) {
                    Text(currentAd.brand)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.44, green: 0.88, blue: 0.78))
                    Text(currentAd.message)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(red: 0.03, green: 0.07, blue: 0.12).opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.44, green: 0.88, blue: 0.78)))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("Reklama marki \(currentAd.brand): \(currentAd.message)")
            }
        }
        .task(id: isPro) {
            await runHouseAdRotation()
        }
        .alert("Pilot niedostępny", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func remoteButton(
        _ symbol: String,
        command: String,
        accessibilityLabel: String? = nil
    ) -> some View {
        Button {
            Task { await send(command) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 68, height: 58)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(accessibilityLabel ?? command)
    }

    private func send(_ command: String) async {
        guard let source = URL(string: serverURL), let host = source.host else {
            errorMessage = "Brak prawidłowego adresu telewizora."
            return
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = 8082
        components.path = "/remote"
        components.queryItems = [
            URLQueryItem(name: "room", value: roomCode),
            URLQueryItem(name: "command", value: command)
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Włącz „MiBox Screen Remote” w Ustawienia > Dostępność na telewizorze."
                return
            }
        } catch {
            errorMessage = "Nie można połączyć pilota z telewizorem."
        }
    }

    private func runHouseAdRotation() async {
        currentAd = nil
        guard !isPro else { return }
        let now = Date().timeIntervalSince1970
        if lastAdDate <= 0 { lastAdDate = now }

        while !Task.isCancelled && !isPro {
            let elapsed = Date().timeIntervalSince1970 - lastAdDate
            let waitSeconds = max(1, 20 * 60 - elapsed)
            do {
                try await Task.sleep(for: .seconds(waitSeconds))
            } catch {
                return
            }
            guard !isPro, let ad = await fetchNextHouseAd() else { continue }
            lastAdDate = Date().timeIntervalSince1970
            withAnimation { currentAd = ad }
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            withAnimation { currentAd = nil }
        }
    }

    private func fetchNextHouseAd() async -> RemoteHouseAd? {
        guard let source = URL(string: serverURL), let host = source.host else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = 8081
        components.path = "/api/ads/next"
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(RemoteHouseAd.self, from: data)
            return result.available ? result : nil
        } catch {
            return nil
        }
    }
}

private struct RemoteHouseAd: Decodable {
    let available: Bool
    let id: String?
    let brand: String
    let message: String

    private enum CodingKeys: String, CodingKey {
        case available, id, brand, message
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        available = try values.decode(Bool.self, forKey: .available)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        brand = try values.decodeIfPresent(String.self, forKey: .brand) ?? ""
        message = try values.decodeIfPresent(String.self, forKey: .message) ?? ""
    }
}
