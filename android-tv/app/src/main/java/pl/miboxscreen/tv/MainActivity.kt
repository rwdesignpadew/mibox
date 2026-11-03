package pl.miboxscreen.tv

import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface
import java.security.SecureRandom
import java.util.Collections

class MainActivity : AppCompatActivity(), LocalSignalServer.Listener {
    private lateinit var overlay: LinearLayout
    private lateinit var statusView: TextView
    private lateinit var playerView: PlayerView
    private lateinit var directPlayer: DirectVideoPlayer
    private lateinit var signalServer: LocalSignalServer
    private var serviceAdvertiser: ReceiverServiceAdvertiser? = null
    private var udpDiscoveryResponder: UdpDiscoveryResponder? = null
    private lateinit var roomCode: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        val preferences = getSharedPreferences("receiver", MODE_PRIVATE)
        roomCode = preferences.getString("roomCode", null) ?: SecureRandom()
            .nextInt(1_000_000).toString().padStart(6, '0').also {
                preferences.edit().putString("roomCode", it).apply()
            }

        playerView = PlayerView(this).apply {
            visibility = View.GONE
            setBackgroundColor(Color.BLACK)
            useController = true
        }
        statusView = label(20f, "Gotowy — otwórz MiBox Screen na iPhonie")
        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(0xFF07111F.toInt())
            addView(label(34f, "MiBox Screen"))
            addView(label(22f, "Odbiornik wideo jest uruchomiony"))
            addView(statusView)
            addView(label(20f, "Adres IP: ${localIPv4Address() ?: "brak połączenia Wi-Fi"}"))
            addView(label(16f, "Kod urządzenia: $roomCode"))
        }
        setContentView(FrameLayout(this).apply {
            addView(playerView, FrameLayout.LayoutParams(-1, -1))
            addView(this@MainActivity.overlay, FrameLayout.LayoutParams(-1, -1))
        })

        signalServer = LocalSignalServer(SIGNAL_PORT, roomCode, this)
        directPlayer = DirectVideoPlayer(this, playerView) { state, error ->
            runOnUiThread {
                signalServer.sendPlaybackStatus(state, error)
                updatePlaybackStatus(state, error)
            }
        }
        runCatching { signalServer.start() }
            .onFailure { statusView.text = "Błąd serwera: ${it.localizedMessage}" }

        runCatching {
            ReceiverServiceAdvertiser(this, SIGNAL_PORT, roomCode).also {
                serviceAdvertiser = it
                it.start()
            }
        }
        runCatching {
            UdpDiscoveryResponder(SIGNAL_PORT, roomCode).also {
                udpDiscoveryResponder = it
                it.start()
            }
        }
    }

    private fun label(size: Float, value: String) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(0xFFF2F7FF.toInt())
        gravity = Gravity.CENTER
        setPadding(8, 12, 8, 12)
    }

    private fun localIPv4Address(): String? = runCatching {
        Collections.list(NetworkInterface.getNetworkInterfaces())
            .asSequence()
            .flatMap { Collections.list(it.inetAddresses).asSequence() }
            .filterIsInstance<Inet4Address>()
            .firstOrNull { !it.isLoopbackAddress && it.isSiteLocalAddress }
            ?.hostAddress
    }.getOrNull()

    override fun onSenderJoined(isPro: Boolean) = runOnUiThread {
        statusView.text = "iPhone połączony"
    }

    override fun onSenderLeft() = runOnUiThread {
        statusView.text = "Oczekiwanie na iPhone'a"
    }

    override fun onSignal(message: JSONObject) = Unit

    override fun onPlaybackCommand(message: JSONObject) = runOnUiThread {
        when (message.optString("type")) {
            "play" -> play(message)
            "pause" -> directPlayer.pause()
            "resume" -> directPlayer.resume()
            "stop" -> {
                directPlayer.stop()
                playerView.visibility = View.GONE
                overlay.visibility = View.VISIBLE
            }
            "seek" -> directPlayer.seekTo(message.optLong("positionMs"))
        }
    }

    private fun play(message: JSONObject) {
        val url = message.optString("url")
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            signalServer.sendPlaybackStatus("error", "Nieprawidłowy adres filmu")
            return
        }
        val headersObject = message.optJSONObject("headers")
        val headers = buildMap {
            headersObject?.keys()?.forEach { key -> put(key, headersObject.optString(key)) }
        }
        overlay.visibility = View.GONE
        playerView.visibility = View.VISIBLE
        directPlayer.play(url, message.optString("title").takeIf { it.isNotBlank() }, headers)
    }

    override fun onServerError(message: String) = runOnUiThread {
        statusView.text = "Błąd: $message"
    }

    private fun updatePlaybackStatus(state: String, error: String?) {
        if (state == "error") {
            playerView.visibility = View.GONE
            overlay.visibility = View.VISIBLE
            statusView.text = error ?: "Nie można odtworzyć filmu"
        }
    }

    override fun onDestroy() {
        serviceAdvertiser?.stop()
        udpDiscoveryResponder?.stop()
        if (::signalServer.isInitialized) runCatching { signalServer.stop(1_000) }
        if (::directPlayer.isInitialized) directPlayer.release()
        super.onDestroy()
    }

    companion object {
        private const val SIGNAL_PORT = 8080
    }
}
