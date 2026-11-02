package pl.miboxscreen.tv

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

class UdpDiscoveryResponder(
    private val signalPort: Int,
    private val roomCode: String
) {
    private val running = AtomicBoolean(false)
    private var socket: DatagramSocket? = null
    private var worker: Thread? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        worker = Thread({ listen() }, "mibox-udp-discovery").apply {
            isDaemon = true
            start()
        }
    }

    private fun listen() {
        try {
            val activeSocket = DatagramSocket(null).apply {
                reuseAddress = true
                bind(InetSocketAddress(DISCOVERY_PORT))
                soTimeout = 1_000
            }
            socket = activeSocket
            val buffer = ByteArray(256)

            while (running.get()) {
                try {
                    val request = DatagramPacket(buffer, buffer.size)
                    activeSocket.receive(request)
                    val message = String(request.data, request.offset, request.length, Charsets.UTF_8)
                    if (message != DISCOVERY_REQUEST) continue

                    val responseBytes = "$DISCOVERY_RESPONSE|$signalPort|$roomCode|MiBox Screen"
                        .toByteArray(Charsets.UTF_8)
                    activeSocket.send(DatagramPacket(
                        responseBytes,
                        responseBytes.size,
                        request.address,
                        request.port
                    ))
                } catch (_: SocketTimeoutException) {
                    // Wake up regularly so stop() does not have to wait indefinitely.
                }
            }
        } catch (_: Exception) {
            // Bonjour discovery remains available if UDP cannot bind on a device.
        } finally {
            socket?.close()
            socket = null
            running.set(false)
        }
    }

    fun stop() {
        running.set(false)
        socket?.close()
        worker?.interrupt()
        worker = null
    }

    companion object {
        const val DISCOVERY_PORT = 45_321
        const val DISCOVERY_REQUEST = "MIBOXSCREEN_DISCOVER_V1"
        const val DISCOVERY_RESPONSE = "MIBOXSCREEN_RECEIVER_V1"
    }
}
