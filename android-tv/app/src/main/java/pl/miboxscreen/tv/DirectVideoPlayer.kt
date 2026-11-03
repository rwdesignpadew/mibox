package pl.miboxscreen.tv

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

class DirectVideoPlayer(
    context: Context,
    val view: PlayerView,
    private val status: (String, String?) -> Unit
) : Player.Listener {
    private val http = DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setConnectTimeoutMs(15_000)
        .setReadTimeoutMs(30_000)

    private val player = ExoPlayer.Builder(context)
        .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(http))
        .build()

    init {
        view.player = player
        view.useController = true
        view.keepScreenOn = true
        player.addListener(this)
    }

    fun play(url: String, title: String?, headers: Map<String, String>) {
        http.setDefaultRequestProperties(headers)
        val media = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaId(url)
            .setMediaMetadata(
                androidx.media3.common.MediaMetadata.Builder()
                    .setTitle(title ?: "Wideo z iPhone'a")
                    .build()
            )
            .apply {
                when {
                    url.substringBefore('?').endsWith(".m3u8", true) -> setMimeType(MimeTypes.APPLICATION_M3U8)
                    url.substringBefore('?').endsWith(".mpd", true) -> setMimeType(MimeTypes.APPLICATION_MPD)
                }
            }
            .build()
        player.setMediaItem(media)
        player.prepare()
        player.playWhenReady = true
        status("loading", null)
    }

    fun pause() = player.pause()
    fun resume() = player.play()
    fun stop() = player.stop()
    fun seekTo(positionMs: Long) = player.seekTo(positionMs.coerceAtLeast(0))

    override fun onPlaybackStateChanged(state: Int) {
        when (state) {
            Player.STATE_BUFFERING -> status("buffering", null)
            Player.STATE_READY -> status(if (player.isPlaying) "playing" else "ready", null)
            Player.STATE_ENDED -> status("ended", null)
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (player.playbackState == Player.STATE_READY) status(if (isPlaying) "playing" else "paused", null)
    }

    override fun onPlayerError(error: PlaybackException) {
        status("error", error.message ?: "Nie można odtworzyć tego filmu")
    }

    fun release() {
        view.player = null
        player.release()
    }
}
