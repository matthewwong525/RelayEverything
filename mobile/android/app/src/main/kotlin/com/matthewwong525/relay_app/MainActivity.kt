package com.matthewwong525.relay_app

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Health Connect asks for its permissions through a fragment activity.
class MainActivity : FlutterFragmentActivity() {
    private var askingMotion: MethodChannel.Result? = null

    // `relay/motion` (lib/sync/motion.dart): `allow` asks for Physical activity, and `watch` starts or stops the
    // ActivityReceiver.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relay/motion").setMethodCallHandler { call, result ->
            when (call.method) {
                "allow" -> allowMotion(result)
                "watch" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on && !motionAllowed()) return@setMethodCallHandler result.success(false)
                    ActivityReceiver.watch(applicationContext, on) { result.success(it) }
                }
                else -> result.notImplemented()
            }
        }
        // `relay/clipboard` (lib/screens/note_editor.dart): `html` gives a note's paste the clipboard's HTML, so pasted
        // words keep their lists and styles; null when the clipboard holds only plain words.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relay/clipboard").setMethodCallHandler { call, result ->
            if (call.method != "html") return@setMethodCallHandler result.notImplemented()
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            result.success(clipboard?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.htmlText)
        }
    }

    // Before Android 10 the permission comes with the install.
    private fun motionAllowed() = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    private fun allowMotion(result: MethodChannel.Result) {
        if (motionAllowed()) return result.success(true)
        if (askingMotion != null) return result.success(false)
        askingMotion = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), motionRequest)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != motionRequest) return
        askingMotion?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        askingMotion = null
    }

    private companion object {
        const val motionRequest = 4711
    }
}
