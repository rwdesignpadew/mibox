import ReplayKit
import SwiftUI

struct ContentView: View {
    @AppStorage(SharedSettings.serverURLKey, store: SharedSettings.defaults)
    private var serverURL = ""
    @AppStorage(SharedSettings.roomCodeKey, store: SharedSettings.defaults)
    private var roomCode = ""
    @StateObject private var discovery = ReceiverDiscovery()
    @StateObject private var purchases = PurchaseManager()
    @State private var showsPro = ProcessInfo.processInfo.arguments.contains("--show-pro")
    @State private var showsQRScanner = false
    @State private var connectionError: String?

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

                Button {
                    showsQRScanner = true
                } label: {
                    Label("Skanuj kod QR z telewizora", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                DisclosureGroup("Połącz bez aparatu") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wpisz sześciocyfrowy kod zapasowy z telewizora. Aplikacja wyszuka odbiornik w sieci lokalnej.")
                            .foregroundStyle(.secondary)
                        TextField("6-cyfrowy kod z telewizora", text: $roomCode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: roomCode) { value in
                                roomCode = String(value.filter(\.isNumber).prefix(6))
                            }
                        Button("Wyszukaj telewizor") { discovery.restart() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }

                if roomCode.count == 6, validServerURL {
                    VStack(spacing: 10) {
                        NavigationLink {
                            RemoteControlView(serverURL: serverURL, roomCode: roomCode)
                        } label: {
                            Label("Otwórz pilot Mi Box", systemImage: "av.remote.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        BroadcastButton()
                            .frame(height: 54)
                        Text("Wybierz „MiBox Screen”, a następnie naciśnij „Rozpocznij transmisję”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Uruchom MiBox Screen na telewizorze, a następnie zeskanuj wyświetlony kod QR.")
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Połączenie ręczne") {
                    VStack(spacing: 10) {
                        TextField("ws://adres-telewizora:8080/signal", text: $serverURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                        TextField("6-cyfrowy kod z telewizora", text: $roomCode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: roomCode) { value in
                                roomCode = String(value.filter(\.isNumber).prefix(6))
                            }
                    }
                    .padding(.top, 8)
                }
                .font(.footnote)

                Spacer()
                Text("iPhone i telewizor muszą być w tej samej sieci Wi-Fi. Transmisję można zatrzymać z czerwonego wskaźnika u góry ekranu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("MiBox Screen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsPro = true
                    } label: {
                        Label(purchases.isPro ? "Pro aktywne" : "Wersja Pro", systemImage: purchases.isPro ? "checkmark.seal.fill" : "star.fill")
                    }
                }
            }
            .sheet(isPresented: $showsPro) {
                ProPurchaseView(purchases: purchases)
            }
            .fullScreenCover(isPresented: $showsQRScanner) {
                ZStack(alignment: .topTrailing) {
                    QRScannerView { payload in
                        handleScannedPayload(payload)
                    } onError: { message in
                        connectionError = message
                        showsQRScanner = false
                    }
                    .ignoresSafeArea()

                    Button("Zamknij") { showsQRScanner = false }
                        .buttonStyle(.borderedProminent)
                        .padding()
                }
            }
            .alert("Nie można połączyć", isPresented: Binding(
                get: { connectionError != nil },
                set: { if !$0 { connectionError = nil } }
            )) {
                Button("OK", role: .cancel) { connectionError = nil }
            } message: {
                Text(connectionError ?? "")
            }
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

    private func handleScannedPayload(_ payload: String) {
        guard let components = URLComponents(string: payload),
              components.scheme == "miboxscreen",
              components.host == "connect" else {
            connectionError = "To nie jest kod QR aplikacji MiBox Screen."
            return
        }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let host = values["host"], !host.isEmpty,
              let port = values["port"], UInt16(port) != nil,
              let room = values["room"], room.count == 6, room.allSatisfy(\.isNumber) else {
            connectionError = "Kod QR nie zawiera prawidłowych danych połączenia."
            return
        }
        serverURL = "ws://\(host):\(port)/signal"
        roomCode = room
        showsQRScanner = false
    }
}

private struct ProPurchaseView: View {
    @ObservedObject var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    private let reviewMode = ProcessInfo.processInfo.arguments.contains("--show-pro")

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: purchases.isPro ? "checkmark.seal.fill" : "star.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text(purchases.isPro ? "MiBox Screen Pro jest aktywne" : "MiBox Screen Pro")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Jednorazowy zakup. Bez abonamentu.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    benefit("rectangle.slash", "Bez reklam podczas udostępniania")
                    benefit("infinity", "Dostęp Pro bez limitu czasu")
                    benefit("arrow.clockwise", "Możliwość przywrócenia zakupu")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                Spacer()

                if purchases.isPro {
                    Button("Gotowe") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        if purchases.isBusy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Kup wersję Pro — \(purchases.product?.displayPrice ?? (reviewMode ? "39,99 zł" : "cena w App Store"))")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(purchases.product == nil || purchases.isBusy)

                    Button("Przywróć zakup") {
                        Task { await purchases.restore() }
                    }
                    .disabled(purchases.isBusy)
                }
            }
            .padding(24)
            .navigationTitle("Wersja Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
            .alert("MiBox Screen", isPresented: Binding(
                get: { purchases.errorMessage != nil },
                set: { if !$0 { purchases.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { purchases.errorMessage = nil }
            } message: {
                Text(purchases.errorMessage ?? "")
            }
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
        }
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
