package pl.miboxscreen.tv

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.UUID

data class HouseAd(
    val id: String,
    val brand: String,
    val message: String,
    val enabled: Boolean = true,
)

class HouseAdRepository(context: Context) {
    private val preferences = context.getSharedPreferences("house_ads", Context.MODE_PRIVATE)
    private val random = SecureRandom()
    private var rotation = mutableListOf<String>()
    private var lastShownId: String? = null

    val adminPin: String
        get() {
            preferences.getString(KEY_ADMIN_PIN, null)?.let { return it }
            val pin = random.nextInt(1_000_000).toString().padStart(6, '0')
            preferences.edit().putString(KEY_ADMIN_PIN, pin).commit()
            return pin
        }

    @Synchronized
    fun all(): List<HouseAd> = readAds()

    @Synchronized
    fun add(brand: String, message: String) {
        val cleanBrand = brand.trim().take(40)
        val cleanMessage = message.trim().take(100)
        if (cleanBrand.isEmpty() || cleanMessage.isEmpty()) return
        writeAds(readAds() + HouseAd(UUID.randomUUID().toString(), cleanBrand, cleanMessage))
        rotation.clear()
    }

    @Synchronized
    fun toggle(id: String) {
        writeAds(readAds().map { if (it.id == id) it.copy(enabled = !it.enabled) else it })
        rotation.clear()
    }

    @Synchronized
    fun delete(id: String) {
        writeAds(readAds().filterNot { it.id == id })
        rotation.remove(id)
        if (lastShownId == id) lastShownId = null
    }

    @Synchronized
    fun next(): HouseAd? {
        val enabled = readAds().filter { it.enabled }
        if (enabled.isEmpty()) return null
        rotation.retainAll(enabled.map { it.id }.toSet())
        if (rotation.isEmpty()) {
            rotation = enabled.map { it.id }.shuffled(random).toMutableList()
            if (rotation.size > 1 && rotation.first() == lastShownId) {
                rotation.add(rotation.removeAt(0))
            }
        }
        val selectedId = rotation.removeAt(0)
        lastShownId = selectedId
        return enabled.firstOrNull { it.id == selectedId }
    }

    private fun readAds(): List<HouseAd> {
        val stored = preferences.getString(KEY_ADS, null)
        if (stored == null) {
            return listOf(HouseAd("default", HouseAdConfig.DEFAULT_BRAND, HouseAdConfig.DEFAULT_MESSAGE))
        }
        return runCatching {
            val array = JSONArray(stored)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    add(HouseAd(item.getString("id"), item.getString("brand"), item.getString("message"), item.optBoolean("enabled", true)))
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun writeAds(ads: List<HouseAd>) {
        val array = JSONArray()
        ads.forEach { ad ->
            array.put(JSONObject().put("id", ad.id).put("brand", ad.brand).put("message", ad.message).put("enabled", ad.enabled))
        }
        preferences.edit().putString(KEY_ADS, array.toString()).apply()
    }

    companion object {
        private const val KEY_ADS = "ads"
        private const val KEY_ADMIN_PIN = "admin_pin"
    }
}
