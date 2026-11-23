package com.horizonlink.horizon_link

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.view.WindowManager
import android.widget.Toast

class MainActivity : FlutterActivity() {
    private var dashboardToast: Toast? = null
    private var pending: MethodChannel.Result? = null
    private var exportText: String? = null
    private val documentRequest = 4102
    private val limit = 64 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "horizon_link/dashboard_display")
            .setMethodCallHandler { call, result ->
                val awake = call.arguments as? Boolean
                when {
                    call.method != "setAwake" -> result.notImplemented()
                    awake == null -> result.error("ARGUMENT", "Expected a Boolean", null)
                    else -> {
                        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        if (awake) window.addFlags(flag) else window.clearFlags(flag)
                        result.success(null)
                    }
                }
            }
        val dashboardChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "horizon_link/dashboard")
        dashboardChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "showFullscreenHint" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrBlank() || text.length > 120) {
                            result.error("TEXT", "Invalid fullscreen hint", null)
                        } else {
                            dashboardToast?.cancel()
                            // Standard system text Toast: Android controls position/style.
                            dashboardToast = Toast.makeText(this, text, Toast.LENGTH_LONG)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                dashboardToast?.addCallback(object : Toast.Callback() {
                                    override fun onToastHidden() {
                                        if (!isFinishing && !isDestroyed) {
                                            dashboardChannel.invokeMethod("fullscreenHintHidden", null)
                                        }
                                    }
                                })
                            }
                            dashboardToast?.show()
                            result.success(null)
                        }
                    }
                    "cancelFullscreenHint" -> {
                        dashboardToast?.cancel()
                        dashboardToast = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "horizon_link/documents")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "version" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
                        result.success("${info.versionName}+$code")
                    }
                    "export", "import" -> {
                        if (pending != null) {
                            result.error("BUSY", "A document operation is already open", null)
                        } else {
                            val text = call.argument<String>("text")
                            if (call.method == "export" && (text == null || text.toByteArray(Charsets.UTF_8).size > limit)) {
                                result.error("SIZE", "Backup is missing or exceeds 64 MiB", null)
                            } else {
                                pending = result
                                exportText = if (call.method == "export") text else null
                                val intent = Intent(if (call.method == "export") Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE)
                                    .setType(if (call.method == "export") "application/json" else "*/*")
                                if (call.method == "export") intent.putExtra(Intent.EXTRA_TITLE, "Horizon-Link-backup.json")
                                try {
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, documentRequest)
                                } catch (_: Exception) {
                                    pending = null
                                    exportText = null
                                    result.error("PICKER", "No document provider available", null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        dashboardToast?.cancel()
        dashboardToast = null
        super.onDestroy()
    }

    @Deprecated("Activity result bridge for Flutter host")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != documentRequest) return
        val callback = pending ?: return
        val text = exportText
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            exportText = null
            callback.success(null)
            return
        }
        Thread {
            try {
                val answer: Any = if (text != null) {
                    val bytes = text.toByteArray(Charsets.UTF_8)
                    (contentResolver.openOutputStream(uri, "wt") ?: error("No output stream")).use {
                        it.write(bytes)
                        it.flush()
                    }
                    // Read back the selected file: don't call a partial write a backup.
                    val verified = (contentResolver.openInputStream(uri) ?: error("Cannot verify backup")).use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > limit) error("Backup too large")
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                    check(bytes.contentEquals(verified)) { "Backup verification failed" }
                    true
                } else {
                    (contentResolver.openInputStream(uri) ?: error("No input stream")).use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > limit) error("Backup too large")
                            output.write(buffer, 0, count)
                        }
                        Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(output.toByteArray())).toString()
                    }
                }
                runOnUiThread {
                    pending = null
                    exportText = null
                    callback.success(answer)
                }
            } catch (_: Exception) {
                runOnUiThread {
                    pending = null
                    exportText = null
                    callback.error("DOCUMENT_IO", "Could not read, write or verify the backup", null)
                }
            }
        }.start()
    }
}
