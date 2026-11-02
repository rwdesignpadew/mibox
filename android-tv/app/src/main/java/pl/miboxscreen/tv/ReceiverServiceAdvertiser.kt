package pl.miboxscreen.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo

class ReceiverServiceAdvertiser(context: Context, private val port: Int, roomCode: String) {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registered = false

    private val serviceInfo = NsdServiceInfo().apply {
        serviceName = "MiBox Screen"
        serviceType = SERVICE_TYPE
        setPort(port)
        setAttribute("version", "1")
        setAttribute("room", roomCode)
    }

    private val listener = object : NsdManager.RegistrationListener {
        override fun onServiceRegistered(info: NsdServiceInfo) { registered = true }
        override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) { registered = false }
        override fun onServiceUnregistered(info: NsdServiceInfo) { registered = false }
        override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) { registered = false }
    }

    fun start() {
        manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stop() {
        if (registered) runCatching { manager.unregisterService(listener) }
        registered = false
    }

    companion object {
        const val SERVICE_TYPE = "_miboxscreen._tcp."
    }
}
