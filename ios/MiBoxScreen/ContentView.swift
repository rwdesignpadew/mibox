import SwiftUI

struct ContentView: View {
    @StateObject private var receiver = NativeReceiverManager()
    @StateObject private var remote = MiBoxRemoteModel()
    @StateObject private var purchases = PurchaseManager()
    @State private var showsPro = ProcessInfo.processInfo.arguments.contains("--show-pro")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Wideo i pilot Mi Box")
                        .font(.largeTitle.bold())

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Połączenie z Mi Boxem", systemImage: "tv.and.mediabox")
                            .font(.headline)
                        Text(receiver.status)
                            .font(.footnote)
                            .foregroundStyle(receiver.isConnected ? Color.green : Color.secondary)
                        if let error = receiver.errorMessage {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        if !receiver.isConnected {
                            Button("Szukaj ponownie") { receiver.reconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

                    VideoCastView(receiver: receiver)

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
                receiver.start()
            }
            .onDisappear {
                receiver.stop()
            }
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
                    benefit("rectangle.slash", "Bez reklam podczas oglądania")
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
