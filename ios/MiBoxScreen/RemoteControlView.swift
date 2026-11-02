import SwiftUI

struct RemoteControlView: View {
    let serverURL: String
    let roomCode: String

    @State private var errorMessage: String?

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
}
