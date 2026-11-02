import ReplayKit
import SwiftUI

struct ContentView: View {
    @AppStorage(SharedSettings.serverURLKey, store: SharedSettings.defaults)
    private var serverURL = ""
    @AppStorage(SharedSettings.roomCodeKey, store: SharedSettings.defaults)
    private var roomCode = ""
    @StateObject private var discovery = ReceiverDiscovery()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("Udostępnij ekran iPhone’a na Mi Box")
                    .font(.largeTitle.bold())

                HStack(spacing: 14) {
                    Circle()
                        .fill(discovery.serverURL == nil ? Color.orange : Color.green)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(discovery.receiverName ?? "Szukam Mi Boxa / Android TV")
                            .font(.headline)
                        Text(discovery.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Szukaj") { discovery.restart() }
                }
                .padding()
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

                TextField("6-cyfrowy kod z telewizora", text: $roomCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: roomCode) { value in
                        roomCode = String(value.filter(\.isNumber).prefix(6))
                    }

                if roomCode.count == 6, validServerURL {
                    VStack(spacing: 10) {
                        BroadcastButton()
                            .frame(height: 54)
                        Text("Wybierz „MiBox Screen”, a następnie naciśnij „Rozpocznij transmisję”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Uruchom odbiornik na telewizorze i wpisz wyświetlony kod.")
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Połączenie ręczne") {
                    TextField("ws://adres-telewizora:8080/signal", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                }
                .font(.footnote)

                Spacer()
                Text("iPhone i telewizor muszą być w tej samej sieci Wi‑Fi. Transmisję można zatrzymać z czerwonego wskaźnika u góry ekranu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("MiBox Screen")
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
            .onChange(of: discovery.serverURL) { value in
                if let value { serverURL = value }
            }
        }
    }

    private var validServerURL: Bool {
        guard let url = URL(string: serverURL), let scheme = url.scheme else { return false }
        return (scheme == "ws" || scheme == "wss") && url.host != nil
    }
}

private struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = "pl.miboxscreen.ios.broadcast"
        picker.showsMicrophoneButton = false
        if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
            button.setImage(nil, for: .normal)
            button.setTitle("Rozpocznij udostępnianie", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(red: 0.12, green: 0.42, blue: 0.85, alpha: 1)
            button.layer.cornerRadius = 12
        }
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
