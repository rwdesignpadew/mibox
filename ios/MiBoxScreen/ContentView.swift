import ReplayKit
import SwiftUI

struct ContentView: View {
    @AppStorage(SharedSettings.serverURLKey, store: SharedSettings.defaults)
    private var serverURL = "ws://192.168.1.10:8080/signal"
    @AppStorage(SharedSettings.roomCodeKey, store: SharedSettings.defaults)
    private var roomCode = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("Udostępnij ekran iPhone’a na Mi Box")
                    .font(.largeTitle.bold())

                TextField("Adres serwera, np. ws://192.168.1.10:8080/signal", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)

                TextField("6-cyfrowy kod z telewizora", text: $roomCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: roomCode) { value in
                        roomCode = String(value.filter(\.isNumber).prefix(6))
                    }

                if roomCode.count == 6, URL(string: serverURL) != nil {
                    VStack(spacing: 10) {
                        BroadcastButton()
                            .frame(height: 54)
                        Text("Wybierz „MiBox Screen”, a następnie naciśnij „Rozpocznij transmisję”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Wpisz poprawny adres serwera i kod widoczny na telewizorze.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Text("iPhone i Mi Box muszą mieć dostęp do tego samego serwera. Transmisję można zatrzymać z czerwonego wskaźnika u góry ekranu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("MiBox Screen")
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
