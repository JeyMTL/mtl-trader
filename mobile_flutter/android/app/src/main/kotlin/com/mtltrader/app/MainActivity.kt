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

                    "openSettings" -> {
                        if (!isServiceEnabled()) {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        } else {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(true)
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
