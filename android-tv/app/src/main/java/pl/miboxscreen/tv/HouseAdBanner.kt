package pl.miboxscreen.tv

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

class HouseAdBanner(context: Context, private val repository: HouseAdRepository) : LinearLayout(context) {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private val brandView = label("", 18f, Typeface.BOLD, Color.rgb(112, 225, 200))
    private val messageView = label("", 16f, Typeface.NORMAL, Color.WHITE)

    private val hideRunnable = Runnable { hideAnimated() }
    private val showRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            showAnimated()
            handler.postDelayed(hideRunnable, HouseAdConfig.DISPLAY_MILLIS)
            handler.postDelayed(this, HouseAdConfig.INTERVAL_MILLIS)
        }
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(24), dp(14), dp(24), dp(14))
        elevation = dp(12).toFloat()
        visibility = View.GONE
        alpha = 0f
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(Color.argb(235, 7, 17, 31))
            setStroke(dp(1), Color.rgb(112, 225, 200))
        }

        addView(brandView)
        addView(messageView)
    }

    fun start() {
        if (running) return
        running = true
        handler.postDelayed(showRunnable, HouseAdConfig.INTERVAL_MILLIS)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(showRunnable)
        handler.removeCallbacks(hideRunnable)
        animate().cancel()
        alpha = 0f
        visibility = View.GONE
    }

    private fun showAnimated() {
        val ad = repository.next() ?: return
        brandView.text = ad.brand
        messageView.text = "  |  ${ad.message}"
        contentDescription = "Reklama marki ${ad.brand}: ${ad.message}"
        visibility = View.VISIBLE
        animate().cancel()
        animate().alpha(1f).setDuration(300).start()
    }

    private fun hideAnimated() {
        animate().cancel()
        animate().alpha(0f).setDuration(300).withEndAction { visibility = View.GONE }.start()
    }

    private fun label(value: String, size: Float, style: Int, color: Int) = TextView(context).apply {
        text = value
        textSize = size
        setTextColor(color)
        setTypeface(typeface, style)
        maxLines = 1
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
