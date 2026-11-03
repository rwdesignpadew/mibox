import Combine
import GoogleCast
import Foundation

@MainActor
final class CastManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName: String?
    @Published private(set) var errorMessage: String?

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
        client.loadMedia(with: requestBuilder.build())
        loadedURL = url
        errorMessage = nil
    }

    private func refreshState() {
        let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession
        let connected = session != nil && GCKCastContext.sharedInstance().castState == .connected
        if !connected { loadedURL = nil }
        isConnected = connected
        deviceName = session?.device.friendlyName
    }
}
