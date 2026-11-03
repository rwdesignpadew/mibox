import Combine
import GoogleCast
import Foundation

@MainActor
final class CastManager: NSObject, ObservableObject, GCKRequestDelegate {
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackMessage: String?

    private var timer: Timer?
    private var loadedURL: URL?

    func start() {
        guard timer == nil else { return }
        refreshState()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func castVideo(_ url: URL, title: String? = nil) {
        guard isConnected,
              let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient else {
            errorMessage = "Najpierw wybierz Mi Box przyciskiem Cast."
            playbackMessage = nil
            return
        }

        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString(title ?? "Wideo z iPhone’a", forKey: kGCKMetadataKeyTitle)

        let mediaBuilder = GCKMediaInformationBuilder(contentURL: url)
        let path = url.path.lowercased()
        let isLivePlaylist = path.hasSuffix(".m3u8") || path.hasSuffix(".mpd")
        mediaBuilder.streamType = isLivePlaylist ? .live : .buffered
        if path.hasSuffix(".m3u8") {
            mediaBuilder.contentType = "application/x-mpegURL"
        } else if path.hasSuffix(".mpd") {
            mediaBuilder.contentType = "application/dash+xml"
        } else if path.hasSuffix(".webm") {
            mediaBuilder.contentType = "video/webm"
        } else {
            mediaBuilder.contentType = "video/mp4"
        }
        mediaBuilder.metadata = metadata

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = mediaBuilder.build()
        requestBuilder.autoplay = true
        let request = client.loadMedia(with: requestBuilder.build())
        request.delegate = self
        loadedURL = url
        errorMessage = nil
        playbackMessage = "Wysyłam film do \(deviceName ?? "Mi Boxa")…"
    }

    func requestDidComplete(_ request: GCKRequest) {
        errorMessage = nil
        playbackMessage = "Film został wysłany. Odtwarzanie powinno rozpocząć się na telewizorze."
    }

    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        playbackMessage = nil
        errorMessage = Self.readableMessage(for: error)
    }

    func request(_ request: GCKRequest, didAbortWithReason abortReason: GCKRequestAbortReason) {
        playbackMessage = nil
        errorMessage = "Mi Box przerwał wysyłanie filmu (kod: \(abortReason.rawValue)). Spróbuj ponownie."
    }

    private static func readableMessage(for error: GCKError) -> String {
        switch error.code {
        case GCKErrorCode.mediaLoadFailed.rawValue:
            return "Mi Box nie może otworzyć tego filmu. Adres może wymagać logowania, ciasteczek albo format nie jest obsługiwany."
        case GCKErrorCode.mediaError.rawValue:
            return "Mi Box odebrał adres, ale nie potrafi odtworzyć tego materiału."
        case GCKErrorCode.networkError.rawValue, GCKErrorCode.timeout.rawValue:
            return "Utracono połączenie z Mi Boxem. Sprawdź, czy oba urządzenia są w tej samej sieci Wi‑Fi."
        default:
            return "Nie udało się uruchomić filmu na Mi Boxie: \(error.localizedDescription) (kod: \(error.code))."
        }
    }

    private func refreshState() {
        let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession
        let connected = session != nil && GCKCastContext.sharedInstance().castState == .connected
        if !connected {
            loadedURL = nil
            if isConnected {
                playbackMessage = nil
                errorMessage = "Połączenie z Mi Boxem zostało przerwane."
            }
        }
        isConnected = connected
        deviceName = session?.device.friendlyName
    }
}
