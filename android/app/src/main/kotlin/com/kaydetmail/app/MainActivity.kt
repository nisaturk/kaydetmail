package com.kaydetmail.app

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Apply the saved preference before the first frame is drawn so the
        // window is never briefly capturable. shared_preferences stores its
        // Dart keys under the "flutter." prefix.
        val prefs = getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        setScreenProtection(prefs.getBoolean(PREFS_KEY, false))
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        setScreenProtection(call.argument<Boolean>("enabled") ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** FLAG_SECURE blocks screenshots/recordings and blanks the recents thumbnail. */
    private fun setScreenProtection(enabled: Boolean) {
        if (enabled) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private companion object {
        const val CHANNEL = "kaydetmail/screen_protection"
        const val PREFS_FILE = "FlutterSharedPreferences"
        const val PREFS_KEY = "flutter.kaydet.security.screenProtectionEnabled"
    }
}
