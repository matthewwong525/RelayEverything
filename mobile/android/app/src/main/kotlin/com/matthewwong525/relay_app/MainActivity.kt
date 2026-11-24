package com.matthewwong525.relay_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
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
        // `relay/web-keyboard` (lib/editor/web_note/host_native.dart): `show` brings the keyboard up for the note's web
        // view when the editor page puts the cursor in the words itself, such as for a new note. Android shows it only
        // for a tap.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relay/web-keyboard").setMethodCallHandler { call, result ->
            if (call.method != "show") return@setMethodCallHandler result.notImplemented()
            val view = shownWebViews(window.decorView).lastOrNull() ?: return@setMethodCallHandler result.success(false)
            view.requestFocus()
            val keyboard = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            result.success(keyboard?.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT) ?: false)
        }
    }

    /// Each web view on the screen, in the order of the views.
    private fun shownWebViews(view: View): List<WebView> = when {
        view is WebView -> if (view.isShown) listOf(view) else emptyList()
        view is ViewGroup -> (0 until view.childCount).flatMap { shownWebViews(view.getChildAt(it)) }
        else -> emptyList()
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
