import AndroidTVRemoteControl
import SwiftUI

struct MiBoxRemoteView: View {
    @StateObject private var model = MiBoxRemoteModel()
    @State private var manualHost = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Circle().fill(model.isConnected ? Color.green : Color.orange).frame(width: 10, height: 10)
                    Text(model.status).font(.headline)
                    Spacer()
                    Button { model.startScanning() } label: { Image(systemName: "arrow.clockwise") }
                }

                if !model.isConnected {
                    devicePicker
                } else {
                    remoteControls
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear { if model.devices.isEmpty && !model.isConnected { model.startScanning() } }
        .sheet(isPresented: $model.needsPairingCode) {
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "tv.and.hifispeaker.fill").font(.system(size: 54)).foregroundStyle(.blue)
                    Text("Kod parowania").font(.title.bold())
                    Text("Wpisz 6-znakowy kod wyświetlony teraz na Mi Boxie.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    TextField("Np. A1B2C3", text: $model.pairingCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.title2.monospaced()).multilineTextAlignment(.center).textFieldStyle(.roundedBorder)
                        .onChange(of: model.pairingCode) { model.pairingCode = String($0.uppercased().filter { $0.isHexDigit }.prefix(6)) }
                    Button("Połącz") { model.submitCode() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.pairingCode.count != 6)
                    Spacer()
                }
                .padding(24)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { model.needsPairingCode = false } } }
            }
            .presentationDetents([.medium])
        }
        .alert("Pilot Mi Box", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isScanning { ProgressView("Szukam Mi Boxa w Wi‑Fi…") }
            ForEach(model.devices) { device in
                Button { model.select(device) } label: {
                    HStack { Image(systemName: "tv"); Text(device.name); Spacer(); Image(systemName: "chevron.right") }
                        .padding().background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            DisclosureGroup("Połącz przez adres IP") {
                HStack {
                    TextField("Np. 192.168.1.25", text: $manualHost).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    Button("Połącz") { model.connectManually(manualHost) }.buttonStyle(.borderedProminent)
                }.padding(.top, 8)
            }
        }
    }

    private var remoteControls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 22) {
                remoteButton("power", .KEYCODE_POWER, color: .red)
                remoteButton("house.fill", .KEYCODE_HOME)
                remoteButton("arrow.uturn.backward", .KEYCODE_BACK)
            }
            VStack(spacing: 8) {
                remoteButton("chevron.up", .KEYCODE_DPAD_UP)
                HStack(spacing: 34) {
                    remoteButton("chevron.left", .KEYCODE_DPAD_LEFT)
                    Button("OK") { model.send(.KEYCODE_DPAD_CENTER) }
                        .font(.title3.bold()).frame(width: 76, height: 76).background(Color.blue, in: Circle()).foregroundStyle(.white)
                    remoteButton("chevron.right", .KEYCODE_DPAD_RIGHT)
                }
                remoteButton("chevron.down", .KEYCODE_DPAD_DOWN)
            }
            .padding(20).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
            HStack(spacing: 26) {
                remoteButton("speaker.minus.fill", .KEYCODE_VOLUME_DOWN)
                remoteButton("speaker.slash.fill", .KEYCODE_VOLUME_MUTE)
                remoteButton("speaker.plus.fill", .KEYCODE_VOLUME_UP)
            }
            HStack(spacing: 26) {
                remoteButton("backward.fill", .KEYCODE_MEDIA_REWIND)
                remoteButton("playpause.fill", .KEYCODE_MEDIA_PLAY_PAUSE)
                remoteButton("forward.fill", .KEYCODE_MEDIA_FAST_FORWARD)
            }
        }
    }

    private func remoteButton(_ icon: String, _ key: Key, color: Color = .primary) -> some View {
        Button { model.send(key) } label: {
            Image(systemName: icon).font(.title2).frame(width: 54, height: 54).background(Color.secondary.opacity(0.12), in: Circle()).foregroundStyle(color)
        }
    }
}
