package com.mtltrader.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Freezes MetaTrader 5 on this phone while the journal's soft lock is active.
 *
 * The service never reads screen content: it only looks at which package is in
 * front and, if it is MT5, covers it with an overlay that offers a way back to
 * the journal. Whether the day is over is still decided by the server; this
 * service only carries out the answer written by the app.
 */
class Mt5FreezeService : AccessibilityService() {

    private var overlay: View? = null
    private lateinit var windowManager: WindowManager

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        instance = this
        serviceInfo = serviceInfo?.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOWS_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 50
            flags = flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        // The overlay itself is owned by this package, so a plain package match
        // would hide the cover the instant it was added. Only the journal's
        // activity means the trader is really back in the app.
        if (pkg == packageName) {
            val className = event.className?.toString() ?: ""
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                className.contains("MainActivity")
            ) {
                hideOverlay()
            }
            return
        }
        if (pkg == MT5_PACKAGE && shouldFreeze()) showOverlay() else hideOverlay()
    }

    override fun onInterrupt() {
        hideOverlay()
    }

    override fun onDestroy() {
        hideOverlay()
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** Called by the app when the lock is lifted, so the cover goes at once. */
    fun refresh() {
        if (!shouldFreeze()) hideOverlay()
    }

    private fun shouldFreeze(): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return false
        val until = prefs.getLong("until", 0L)
        // An open-ended value is treated as active; the app rewrites it on the
        // next day-state read anyway, and a reset must never leave MT5 frozen.
        return until <= 0L || System.currentTimeMillis() < until
    }

    private fun message(): String =
        getSharedPreferences(PREFS, MODE_PRIVATE).getString("message", "") ?: ""

    private fun showOverlay() {
        if (overlay != null) return
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F20B0B0B"))
            isClickable = true
            isFocusable = true
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }
        val icon = TextView(this).apply {
            text = "\uD83D\uDD12"
            textSize = 34f
            gravity = Gravity.CENTER
        }
        val title = TextView(this).apply {
            text = "MT5 is covered"
            textSize = 24f
            setTextColor(Color.parseColor("#E8C36A"))
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }
        val body = TextView(this).apply {
            text = message().ifBlank { "Your daily loss limit is reached." } +
                "\n\nMetaTrader 5 stays covered until you lift the stop in MTL Ledger."
            textSize = 15f
            setTextColor(Color.parseColor("#C9C9C9"))
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
            setLineSpacing(0f, 1.25f)
        }
        val unlock = Button(this).apply {
            text = "Open MTL Ledger to lift the stop"
            setOnClickListener { openJournal() }
        }
        root.addView(icon)
        root.addView(title)
        root.addView(body)
        root.addView(
            unlock,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(52)
            ).apply { topMargin = dp(24) }
        )

        // An accessibility overlay is display-only on Android and cannot take
        // the tap on the button. The app overlay type is interactive, which is
        // why the app also asks for "Display over other apps".
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        try {
            windowManager.addView(root, params)
            overlay = root
        } catch (error: Exception) {
            // The window can be refused while the service is shutting down or
            // before "Display over other apps" is granted; the next window
            // event tries again.
            android.util.Log.w("Mt5Freeze", "could not add the MT5 cover", error)
        }
    }

    private fun hideOverlay() {
        overlay?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
                // Already detached.
            }
        }
        overlay = null
    }

    private fun openJournal() {
        android.util.Log.d("Mt5Freeze", "unfreeze button tapped")
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra("mt5_freezer", true)
        } ?: return
        // A direct startActivity from a service is refused as a background
        // launch on recent Android. A PendingIntent carries the app's identity
        // and is the supported way to bring the journal forward from here.
        try {
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            pending.send()
        } catch (error: Exception) {
            android.util.Log.w("Mt5Freeze", "pending launch failed", error)
            try {
                startActivity(intent)
            } catch (_: Exception) {
                // The cover stays; the trader can also open the journal from
                // the launcher, and the cover lifts when it is in front.
            }
        }
        // Not hidden here: the MainActivity window event hides it once the
        // journal is actually in front, so a failed launch cannot open MT5.
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val MT5_PACKAGE = "net.metaquotes.metatrader5"
        const val PREFS = "mt5_freezer"

        @Volatile
        var instance: Mt5FreezeService? = null
            private set
    }
}
