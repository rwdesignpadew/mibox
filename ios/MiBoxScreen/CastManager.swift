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

    func loadStreamIfNeeded(_ url: URL) {
        guard isConnected, loadedURL != url,
              let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient else {
            return
        }

        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString("Ekran iPhone’a", forKey: kGCKMetadataKeyTitle)

        let mediaBuilder = GCKMediaInformationBuilder(contentURL: url)
        mediaBuilder.streamType = .live
        mediaBuilder.contentType = "application/x-mpegURL"
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
