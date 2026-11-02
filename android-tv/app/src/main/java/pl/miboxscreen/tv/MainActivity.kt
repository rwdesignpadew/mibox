package pl.miboxscreen.tv

import android.os.Bundle
import android.graphics.Bitmap
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import org.json.JSONObject
import org.webrtc.SurfaceViewRenderer
import java.net.Inet4Address
import java.net.NetworkInterface
import java.security.SecureRandom
import java.util.Collections

class MainActivity : AppCompatActivity(), LocalSignalServer.Listener {
    private lateinit var renderer: SurfaceViewRenderer
    private lateinit var overlay: LinearLayout
    private lateinit var statusView: TextView
    private lateinit var houseAdBanner: HouseAdBanner
    private lateinit var adAdminServer: HouseAdAdminServer
    private lateinit var remoteControlServer: RemoteControlServer
    private lateinit var signalServer: LocalSignalServer
    private lateinit var serviceAdvertiser: ReceiverServiceAdvertiser
    private lateinit var udpDiscoveryResponder: UdpDiscoveryResponder
    private lateinit var receiver: WebRtcReceiver
    private var proSession = false
    private val roomCode = SecureRandom().nextInt(1_000_000).toString().padStart(6, '0')

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        renderer = SurfaceViewRenderer(this)
        statusView = textView(22f, "Oczekiwanie na iPhone'a")
        val adRepository = HouseAdRepository(this)
        houseAdBanner = HouseAdBanner(this, adRepository)
        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(0xDD07111F.toInt())
            addView(textView(28f, "MiBox Screen"))
            addView(textView(20f, "Zeskanuj kod QR aplikacją MiBox Screen na iPhonie"))
            createConnectionQR()?.let { bitmap ->
                addView(ImageView(this@MainActivity).apply {
                    setImageBitmap(bitmap)
                    contentDescription = "Kod QR połączenia z MiBox Screen"
                    adjustViewBounds = true
                }, LinearLayout.LayoutParams(420, 420).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    setMargins(0, 20, 0, 20)
                })
            } ?: addView(textView(18f, "Brak adresu sieci. Sprawdź połączenie Wi-Fi."))
            addView(textView(18f, "Bez aparatu? Wpisz w iPhonie kod: $roomCode"))
            if (!RemoteAccessibilityService.isEnabled()) {
                addView(textView(15f, "Pilot: włącz „MiBox Screen Remote” w Ustawienia > Dostępność"))
            }
            addView(statusView)
            addView(textView(16f, "Panel reklam: ${HouseAdAdminServer.panelUrl()}\nLogin: admin   Kod: ${adRepository.adminPin}"))
        }
        setContentView(FrameLayout(this).apply {
            addView(renderer, FrameLayout.LayoutParams(-1, -1))
            addView(this@MainActivity.overlay, FrameLayout.LayoutParams(-1, -1))
            addView(houseAdBanner, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                setMargins(48, 48, 48, 48)
            })
        })

        signalServer = LocalSignalServer(SIGNAL_PORT, roomCode, this)
        receiver = WebRtcReceiver(this, renderer, signalServer::sendSignal) {
            status -> runOnUiThread { updateStatus(status) }
        }
        signalServer.start()
        adAdminServer = HouseAdAdminServer(adRepository)
        runCatching { adAdminServer.start() }
        remoteControlServer = RemoteControlServer(roomCode)
        runCatching { remoteControlServer.start() }
        serviceAdvertiser = ReceiverServiceAdvertiser(this, SIGNAL_PORT, roomCode)
        serviceAdvertiser.start()
        udpDiscoveryResponder = UdpDiscoveryResponder(SIGNAL_PORT, roomCode)
        udpDiscoveryResponder.start()
    }

    private fun textView(size: Float, value: String) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(0xFFF2F7FF.toInt())
        gravity = Gravity.CENTER
        setPadding(8, 12, 8, 12)
    }

    private fun createConnectionQR(): Bitmap? {
        val host = localIPv4Address() ?: return null
        val payload = "miboxscreen://connect?host=$host&port=$SIGNAL_PORT&room=$roomCode"
        val matrix = QRCodeWriter().encode(
            payload,
            BarcodeFormat.QR_CODE,
            420,
            420,
            mapOf(EncodeHintType.MARGIN to 1)
        )
        return Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.RGB_565).apply {
            for (y in 0 until matrix.height) {
                for (x in 0 until matrix.width) {
                    setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
                }
            }
        }
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
        proSession = isPro
        updateStatus("iPhone połączony — uruchamianie transmisji")
    }

    override fun onSenderLeft() = runOnUiThread {
        proSession = false
        receiver.handle(JSONObject().put("type", "peer-left"))
    }

    override fun onSignal(message: JSONObject) = runOnUiThread { receiver.handle(message) }
    override fun onServerError(message: String) = runOnUiThread { updateStatus("Błąd: $message") }

    private fun updateStatus(value: String) {
        statusView.text = value
        val connected = value.equals("Connected", ignoreCase = true)
        overlay.visibility = if (connected) View.GONE else View.VISIBLE
        if (connected && !proSession) houseAdBanner.start() else houseAdBanner.stop()
    }

    override fun onDestroy() {
        houseAdBanner.stop()
        adAdminServer.stop()
        remoteControlServer.stop()
        serviceAdvertiser.stop()
        udpDiscoveryResponder.stop()
        runCatching { signalServer.stop(1_000) }
        receiver.release()
        super.onDestroy()
    }

    companion object {
        private const val SIGNAL_PORT = 8080
    }
}
