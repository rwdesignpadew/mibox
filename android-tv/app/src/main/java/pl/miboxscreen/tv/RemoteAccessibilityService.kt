package pl.miboxscreen.tv

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class RemoteAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun execute(command: String): Boolean = when (command) {
        "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
        "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
        "up" -> moveFocus(View.FOCUS_UP)
        "down" -> moveFocus(View.FOCUS_DOWN)
        "left" -> moveFocus(View.FOCUS_LEFT)
        "right" -> moveFocus(View.FOCUS_RIGHT)
        "ok" -> clickFocused()
        "volume_up" -> adjustVolume(AudioManager.ADJUST_RAISE)
        "volume_down" -> adjustVolume(AudioManager.ADJUST_LOWER)
        "play_pause" -> mediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        else -> false
    }

    private fun moveFocus(direction: Int): Boolean {
        val root = rootInActiveWindow ?: return false
        val current = root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
            ?: root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: root
        val next = current.focusSearch(direction) ?: return false
        return next.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS) ||
            next.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
    }

    private fun clickFocused(): Boolean {
        val root = rootInActiveWindow ?: return false
        var node = root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
            ?: root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: return false
        while (!node.isClickable && node.parent != null) node = node.parent
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun adjustVolume(direction: Int): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        return true
    }

    private fun mediaKey(keyCode: Int): Boolean = runCatching {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        true
    }.getOrDefault(false)

    companion object {
        @Volatile private var instance: RemoteAccessibilityService? = null

        fun isEnabled(): Boolean = instance != null
        fun execute(command: String): Boolean = instance?.execute(command) ?: false
    }
}
