import AndroidTVRemoteControl
import Combine
import Foundation
import Network
import Security

struct RemoteDevice: Identifiable, Hashable {
    let name: String
    let host: String
    var id: String { host }
}

@MainActor
final class MiBoxRemoteModel: NSObject, ObservableObject {
    @Published private(set) var devices: [RemoteDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var selectedDevice: RemoteDevice?
    @Published var needsPairingCode = false
    @Published var pairingCode = ""
    @Published var status = "Wybierz Mi Box"
    @Published var errorMessage: String?

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private let pairingManager: PairingManager
    private let remoteManager: RemoteManager
    private let defaults = UserDefaults.standard

    override init() {
        let crypto = CryptoManager()
        let tls = TLSManager {
            do {
                let material = try RemoteClientIdentity.loadOrCreate()
                return .Result([[kSecImportItemIdentity as String: material.identity]] as CFArray)
            } catch {
                return .Error(.loadCertFromURLError(error))
            }
        }
        crypto.clientPublicCertificate = {
            do {
                let certificate = try RemoteClientIdentity.loadOrCreate().certificate
                guard let key = SecCertificateCopyKey(certificate) else { return .Error(.secTrustCopyKeyError) }
                return .Result(key)
            } catch { return .Error(.loadCertFromURLError(error)) }
        }
        tls.secTrustClosure = { trust in
            crypto.serverPublicCertificate = {
                guard let key = SecTrustCopyKey(trust) else { return .Error(.secTrustCopyKeyError) }
                return .Result(key)
            }
        }
        pairingManager = PairingManager(tls, crypto)
        remoteManager = RemoteManager(tls, CommandNetwork.DeviceInfo("MiBox Screen", "iPhone", "1.0", "pl.miboxscreen.ios", "1"))
        super.init()
        browser.delegate = self
        pairingManager.stateChanged = { [weak self] state in DispatchQueue.main.async { self?.handlePairing(state) } }
        remoteManager.stateChanged = { [weak self] state in DispatchQueue.main.async { self?.handleRemote(state) } }
    }

    func startScanning() {
        stopScanning()
        devices = []
        isScanning = true
        status = "Szukam urządzeń Android TV…"
        browser.searchForServices(ofType: "_androidtvremote2._tcp.", inDomain: "local.")
    }

    func stopScanning() { browser.stop(); isScanning = false }

    func select(_ device: RemoteDevice) {
        selectedDevice = device
        stopScanning()
        status = "Łączenie z \(device.name)…"
        if defaults.bool(forKey: "remote.paired.\(device.host)") {
            remoteManager.connect(device.host)
        } else {
            pairingManager.connect(device.host, "MiBox Screen", "iPhone")
        }
    }

    func connectManually(_ host: String) {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        select(RemoteDevice(name: "Mi Box", host: clean))
    }

    func submitCode() {
        let code = pairingCode.uppercased().filter { $0.isHexDigit }
        guard code.count == 6 else { errorMessage = "Kod musi mieć 6 znaków: 0–9 lub A–F."; return }
        pairingCode = code
        status = "Sprawdzam kod…"
        pairingManager.sendSecret(code)
    }

    func send(_ key: Key) {
        guard isConnected else { errorMessage = "Pilot nie jest połączony z Mi Boxem."; return }
        remoteManager.send(KeyPress(key))
    }

    private func handlePairing(_ state: PairingManager.PairingState) {
        switch state {
        case .waitingCode:
            needsPairingCode = true
            status = "Wpisz kod pokazany na telewizorze"
        case .successPaired:
            needsPairingCode = false
            pairingCode = ""
            if let device = selectedDevice {
                defaults.set(true, forKey: "remote.paired.\(device.host)")
                status = "Połączono. Uruchamiam pilot…"
                remoteManager.connect(device.host)
            }
        case .error(let error):
            status = "Błąd parowania"
            errorMessage = error.localizedDescription
        default: break
        }
    }

    private func handleRemote(_ state: RemoteManager.RemoteState) {
        switch state {
        case .paired:
            isConnected = true
            status = "Pilot połączony"
        case .error(let error):
            isConnected = false
            if let device = selectedDevice {
                defaults.set(false, forKey: "remote.paired.\(device.host)")
                status = "Wymagane parowanie"
                pairingManager.connect(device.host, "MiBox Screen", "iPhone")
            } else { errorMessage = error.localizedDescription }
        default: break
        }
    }
}

extension MiBoxRemoteModel: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            services.append(service)
            service.delegate = self
            service.resolve(withTimeout: 5)
            if !moreComing { isScanning = false }
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty else { return }
            let device = RemoteDevice(name: sender.name, host: host)
            if !devices.contains(where: { $0.host == host }) { devices.append(device) }
            status = devices.isEmpty ? "Nie znaleziono urządzeń" : "Wybierz Mi Box"
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in isScanning = false; status = "Nie udało się przeszukać sieci" }
    }
}
