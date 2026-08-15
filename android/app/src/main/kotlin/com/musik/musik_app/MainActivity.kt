package com.musik.musik_app

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.musik.musik_app/files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "toContentUri" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file,
                        )
                        // Allow SystemUI / media session to read album art.
                        grantUriPermission(
                            "com.android.systemui",
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("uri_fail", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
