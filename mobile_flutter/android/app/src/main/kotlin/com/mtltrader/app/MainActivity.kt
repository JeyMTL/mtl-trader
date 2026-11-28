package com.mtltrader.app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mtl/freezer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sync" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        // Flutter sends small ints (including the 0 used when the
                        // lock is switched off) as Int32, not Long. Casting
                        // blindly made every "off" sync throw, leaving the last
                        // active flag in place.
                        val until = when (val raw = call.argument<Any>("until")) {
                            is Long -> raw
                            is Int -> raw.toLong()
                            is Number -> raw.toLong()
                            else -> 0L
                        }
                        val message = call.argument<String>("message") ?: ""
                        getSharedPreferences(Mt5FreezeService.PREFS, MODE_PRIVATE)
                            .edit()
                            .putBoolean("active", active)
                            .putLong("until", until)
                            .putString("message", message)
                            .apply()
                        Mt5FreezeService.instance?.refresh()
                        result.success(true)
                    }

                    "isEnabled" -> result.success(
                        isServiceEnabled() && Settings.canDrawOverlays(this)
                    )

                    // Which of the two permissions is still missing. The screen
                    // shows this as one line, so the trader knows whether the
                    // cover would actually work before a stop ever fires.
                    "accessStatus" -> result.success(
                        when {
                            !isServiceEnabled() -> "accessibility"
                            !Settings.canDrawOverlays(this) -> "overlay"
                            else -> "granted"
                        }
                    )

                    // Opens the settings screen for the first missing permission.
                    // Called once when the toggle goes on and again when the app
                    // comes back, so the accessibility step hands over to the
                    // overlay step without the trader hunting for it.
                    "openSettings" -> {
                        val step = when {
                            !isServiceEnabled() -> "accessibility"
                            !Settings.canDrawOverlays(this) -> "overlay"
                            else -> "granted"
                        }
                        when (step) {
                            "accessibility" -> startActivity(
                                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            )
                            "overlay" -> startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            // Nothing left to grant: stay put instead of
                            // reopening a list that already says yes.
                        }
                        result.success(step)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun isServiceEnabled(): Boolean {
        val expected = ComponentName(this, Mt5FreezeService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == expected }
    }
}
