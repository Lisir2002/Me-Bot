package com.minime.botcore

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 继承 FlutterFragmentActivity：local_auth（PR-6 隐私门禁）在 Android 上要求
// foreground activity 是 FragmentActivity，否则直接返回 NOT_FRAGMENT_ACTIVITY。
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "kelivo/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.arguments as? Boolean ?: false
                    setSecure(secure)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // 设置 FLAG_SECURE：阻止凭证页被截屏 / 录屏 / 进近期任务缩略图。
    private fun setSecure(secure: Boolean) {
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
