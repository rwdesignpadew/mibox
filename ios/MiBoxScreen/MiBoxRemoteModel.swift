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
    private var pendingKey: Key?
    private var attemptingWake = false
    private var mayStartPairingAfterFailure = false
    private var isConnecting = false

    private enum StorageKey {
        static let lastHost = "remote.lastHost"
        static let lastName = "remote.lastName"
        static let pairedHosts = "remote.pairedHosts"
        static let pairedNames = "remote.pairedNames"
    }

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
        if let host = defaults.string(forKey: StorageKey.lastHost),
           let name = defaults.string(forKey: StorageKey.lastName) {
            devices.append(RemoteDevice(name: name, host: host))
        }
        isScanning = true
        status = "Szukam urządzeń Android TV…"
        browser.searchForServices(ofType: "_androidtvremote2._tcp.", inDomain: "local.")
    }

    func stopScanning() { browser.stop(); isScanning = false }

    func select(_ device: RemoteDevice) {
        let wasRemembered = defaults.string(forKey: StorageKey.lastHost) == device.host
        mayStartPairingAfterFailure = !isKnownPaired(device) && !wasRemembered
        selectedDevice = device
        defaults.set(device.host, forKey: StorageKey.lastHost)
        defaults.set(device.name, forKey: StorageKey.lastName)
        stopScanning()
        status = "Łączenie z \(device.name)…"
        // Zapamiętane urządzenie nigdy nie przechodzi automatycznie do parowania tylko
        // dlatego, że jest wyłączone. Ponowne parowanie uruchamia wyłącznie użytkownik.
        isConnecting = true
        remoteManager.connect(device.host)
    }

    func connectManually(_ host: String) {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        select(RemoteDevice(name: "Mi Box", host: clean))
    }

    func resumeRememberedConnection() {
        guard !isConnected, !isConnecting, let device = selectedDevice ?? rememberedDevice else {
            if selectedDevice == nil && rememberedDevice == nil { startScanning() }
            return
        }
        selectedDevice = device
        mayStartPairingAfterFailure = false
        status = "Przywracam pilot \(device.name)…"
        isConnecting = true
        remoteManager.connect(device.host)
    }

    func pairAgain() {
        guard let device = selectedDevice ?? rememberedDevice else { return }
        selectedDevice = device
        mayStartPairingAfterFailure = false
        status = "Uruchamiam parowanie z \(device.name)…"
        pairingManager.connect(device.host, "MiBox Screen", "iPhone")
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

    func power() {
        if isConnected {
            status = "Usypiam Mi Box…"
            remoteManager.send(KeyPress(.KEYCODE_POWER))
            return
        }
        guard let device = selectedDevice ?? rememberedDevice else {
            errorMessage = "Najpierw wybierz i sparuj Mi Box."
            return
        }
        selectedDevice = device
        mayStartPairingAfterFailure = false
        pendingKey = .KEYCODE_WAKEUP
        attemptingWake = true
        status = "Wybudzam \(device.name)…"
        isConnecting = true
        remoteManager.connect(device.host)
    }

    private var rememberedDevice: RemoteDevice? {
        guard let host = defaults.string(forKey: StorageKey.lastHost),
              let name = defaults.string(forKey: StorageKey.lastName) else { return nil }
        return RemoteDevice(name: name, host: host)
    }

    var canWakeRememberedDevice: Bool { selectedDevice != nil || rememberedDevice != nil }

    private func isKnownPaired(_ device: RemoteDevice) -> Bool {
        let hosts = Set(defaults.stringArray(forKey: StorageKey.pairedHosts) ?? [])
        let names = Set(defaults.stringArray(forKey: StorageKey.pairedNames) ?? [])
        return hosts.contains(device.host) || names.contains(device.name)
    }

    private func rememberSuccessfulPairing(_ device: RemoteDevice) {
        var hosts = Set(defaults.stringArray(forKey: StorageKey.pairedHosts) ?? [])
        var names = Set(defaults.stringArray(forKey: StorageKey.pairedNames) ?? [])
        hosts.insert(device.host)
        names.insert(device.name)
        defaults.set(Array(hosts), forKey: StorageKey.pairedHosts)
        defaults.set(Array(names), forKey: StorageKey.pairedNames)
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
                rememberSuccessfulPairing(device)
                mayStartPairingAfterFailure = false
                status = "Połączono. Uruchamiam pilot…"
                isConnecting = true
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
            isConnecting = false
            isConnected = true
            attemptingWake = false
            mayStartPairingAfterFailure = false
            if let device = selectedDevice { rememberSuccessfulPairing(device) }
            status = "Pilot połączony"
            if let key = pendingKey {
                pendingKey = nil
                remoteManager.send(KeyPress(key))
            }
        case .error:
            isConnecting = false
            isConnected = false
            if attemptingWake {
                attemptingWake = false
                pendingKey = nil
                status = "Mi Box jest offline"
                errorMessage = "Mi Box nie odpowiedział na wybudzanie przez usługę pilota. Niektóre modele wyłączają Wi‑Fi w głębokim uśpieniu."
                return
            }
            if mayStartPairingAfterFailure, let device = selectedDevice {
                mayStartPairingAfterFailure = false
                status = "Wymagane parowanie"
                pairingManager.connect(device.host, "MiBox Screen", "iPhone")
            } else {
                status = "Mi Box jest wyłączony lub poza siecią"
            }
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
