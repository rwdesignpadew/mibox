import ReplayKit
import SwiftUI

struct ContentView: View {
    @StateObject private var cast = CastManager()
    @StateObject private var remote = MiBoxRemoteModel()
    @StateObject private var purchases = PurchaseManager()
    @State private var showsPro = ProcessInfo.processInfo.arguments.contains("--show-pro")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Ekran i pilot Mi Box")
                        .font(.largeTitle.bold())

                    HStack(spacing: 14) {
                        CastButton().frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cast.deviceName ?? "Wybierz Mi Box").font(.headline)
                            Text(cast.isConnected ? "Połączono przez Google Cast" : "Naciśnij ikonę Cast i wybierz telewizor")
                                .font(.footnote)
                                .foregroundStyle(cast.isConnected ? Color.green : Color.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

                    if cast.isConnected {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Udostępnianie ekranu").font(.headline)
                            BroadcastControl().frame(height: 54)
                            Text("Po uruchomieniu transmisji pilot poniżej pozostaje aktywny.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Nic nie instalujesz na Mi Boxie — używany jest wbudowany Chromecast.", systemImage: "tv.and.hifispeaker.fill")
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                    Label("Pilot", systemImage: "av.remote.fill")
                        .font(.title2.bold())
                    MiBoxRemoteView(model: remote)
                }
                .padding(24)
            }
            .navigationTitle("MiBox Screen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsPro = true } label: {
                        Label(purchases.isPro ? "Pro aktywne" : "Wersja Pro", systemImage: purchases.isPro ? "checkmark.seal.fill" : "star.fill")
                    }
                }
            }
            .sheet(isPresented: $showsPro) { ProPurchaseView(purchases: purchases) }
            .task {
                cast.start()
                while !Task.isCancelled {
                    if let text = SharedSettings.defaults.string(forKey: SharedSettings.streamURLKey),
                       let url = URL(string: text) {
                        cast.loadStreamIfNeeded(url)
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            .onDisappear { cast.stop() }
        }
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
                    Button("Przywróć zakup") { Task { await purchases.restore() } }
                        .disabled(purchases.isBusy)
                }
            }
            .padding(24)
            .navigationTitle("Wersja Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zamknij") { dismiss() } } }
            .alert("MiBox Screen", isPresented: Binding(
                get: { purchases.errorMessage != nil },
                set: { if !$0 { purchases.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { purchases.errorMessage = nil }
            } message: { Text(purchases.errorMessage ?? "") }
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.blue).frame(width: 24)
            Text(text)
        }
    }
}

private struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = "pl.miboxscreen.ios.broadcast"
        picker.showsMicrophoneButton = false
        picker.accessibilityLabel = "Rozpocznij udostępnianie ekranu"
        if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
            button.setImage(nil, for: .normal)
            button.setTitle(nil, for: .normal)
            button.backgroundColor = .clear
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

private struct BroadcastControl: View {
    var body: some View {
        BroadcastButton()
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue)
                    .overlay {
                        Label("Rozpocznij udostępnianie", systemImage: "rectangle.on.rectangle")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
    }
}
