package com.ugk.smartfit

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "smartfit/runtime_log_export"
        ).setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (exportResult != null) {
                result.error("export_busy", "A file save is already in progress.", null)
                return@setMethodCallHandler
            }
            val filename = call.argument<String>("filename")
            val contents = call.argument<String>("contents")
            if (filename == null || contents == null ||
                !filename.matches(Regex("SmartFit-runtime-[A-Za-z0-9_-]+\\.json")) ||
                filename.length > 96 || contents.length > 4 * 1024 * 1024
            ) {
                result.error("invalid_export", "Invalid log file.", null)
                return@setMethodCallHandler
            }
            exportResult = result
            exportBytes = contents.toByteArray(Charsets.UTF_8)
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, filename)
            }
            try {
                // The system picker grants access to this one document, without
                // any shared-storage permission or fixed device file path.
                startActivityForResult(intent, SAVE_RUNTIME_LOG)
            } catch (_: Exception) {
                finishExport(false, "export_picker_unavailable")
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_RUNTIME_LOG || exportResult == null) return
        if (resultCode != Activity.RESULT_OK) {
            finishExport(false)
            return
        }
        val uri = data?.data
        val bytes = exportBytes
        if (uri == null || bytes == null) {
            finishExport(false, "export_missing_document")
            return
        }
        // Document providers may be backed by slow storage. Keep file I/O off
        // the Flutter platform thread and report success only after close().
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("Document is not writable")
                output.use {
                    it.write(bytes)
                    it.flush()
                }
                runOnUiThread { finishExport(true) }
            } catch (_: Exception) {
                runOnUiThread { finishExport(false, "export_write_failed") }
            }
        }.start()
    }

    private fun finishExport(saved: Boolean, errorCode: String? = null) {
        val result = exportResult
        exportResult = null
        exportBytes = null
        if (errorCode == null) result?.success(saved)
        else result?.error(errorCode, "The log file could not be saved.", null)
    }

    override fun onDestroy() {
        finishExport(false, "export_activity_closed")
        super.onDestroy()
    }

    companion object {
        private const val SAVE_RUNTIME_LOG = 7354
    }
}
