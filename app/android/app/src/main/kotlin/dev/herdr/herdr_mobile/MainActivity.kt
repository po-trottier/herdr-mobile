package dev.herdr.herdr_mobile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `docs/90-implementation-plan.md` `WP-13-b`. This activity's one extra job beyond the Flutter
 * template default is R-31-04-02: `FLAG_SECURE` MUST be set while the app is locked, so the
 * Android task switcher snapshot and any screen recording stay blank instead of showing pane
 * content, an agent name or a Host name.
 *
 * The flag is set synchronously in [onCreate], before the Flutter engine attaches and before
 * the first frame draws, because the app starts locked by default
 * (`app/lib/services/biometric_gate.dart`'s `BiometricGate._locked` starts `true`, per
 * R-31-04-01 and R-13-064) and a flag set only after Dart's first `setLocked` call would leave
 * a real, if brief, gap where an unprotected snapshot could be taken. [biometricGateChannel]
 * then tracks every later lock-state change. Losing focus or pausing secures the window
 * synchronously, before the system can capture the last Flutter frame. A successful unlock
 * can clear the flag only in the focused foreground, after Flutter has replaced any frame
 * that was covered for backgrounding.
 *
 * [appSettingsChannel] is a second, unrelated channel added on request for `WP-15-b`
 * (`docs/31-mockups/02-pair-scan.md`'s `Permission denied` row, `docs/22-platform-integration.md`
 * R-22-073 area): it opens this app's system settings page so a person can grant a denied
 * permission, with no interaction with the lock state above.
 */
class MainActivity : FlutterActivity() {
    private var locked = true
    private var resumed = false
    private var focused = false
    private var awaitingProtectedFrame = false

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        resumed = true
        super.onResume()
        updateFlagSecure()
    }

    override fun onPause() {
        resumed = false
        awaitingProtectedFrame = true
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        focused = hasFocus
        if (!hasFocus) {
            awaitingProtectedFrame = true
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onWindowFocusChanged(hasFocus)
        updateFlagSecure()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CameraZoomChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, biometricGateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLocked" -> {
                        locked = call.argument<Boolean>("locked") ?: true
                        updateFlagSecure()
                        result.success(null)
                    }
                    "frameReady" -> {
                        // A late callback while paused cannot expose a cached task image.
                        // Focus may return after this callback; the flag remains set until then.
                        if (resumed) awaitingProtectedFrame = false
                        updateFlagSecure()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        openAppSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun updateFlagSecure() {
        if (locked || !resumed || !focused || awaitingProtectedFrame) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", applicationContext.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private companion object {
        /** MUST match `_lockChannel` in `app/lib/services/biometric_gate.dart`. */
        const val biometricGateChannel = "dev.herdr.herdr_mobile/biometric_lock"

        /** MUST match the channel `app/lib/screens/qr_scan_screen.dart` (`WP-15-b`) calls. */
        const val appSettingsChannel = "dev.herdr.herdr_mobile/app_settings"
    }
}
