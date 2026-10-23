package com.ugk.smartfit

import android.content.ClipData
import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** The production flavor compiles neither this bridge nor the report provider. */
class InternalMainActivity : MainActivity() {
    private var performanceChannel: MethodChannel? = null
    private var pendingShare: MethodChannel.Result? = null
    private val exportExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "smartfit-performance-export")
    }
    @Volatile private var closing = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        performanceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "smartfit/performance"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceInfo" -> {
                        try {
                            result.success(deviceInfo())
                        } catch (_: Exception) {
                            result.error("device_info_unavailable", "Device information is unavailable.", null)
                        }
                    }
                    "share" -> shareReport(call, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun deviceInfo(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        }
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "osVersion" to Build.VERSION.RELEASE,
            "apiLevel" to Build.VERSION.SDK_INT,
            "appVersion" to (info.versionName ?: "unknown"),
            "appBuildNumber" to versionCode,
            "refreshRateHz" to (currentDisplay?.refreshRate?.toDouble() ?: 60.0),
            "isEmulator" to (
                Build.FINGERPRINT.startsWith("generic") ||
                    Build.FINGERPRINT.contains("emulator") ||
                    Build.MODEL.contains("google_sdk") ||
                    Build.MODEL.contains("Emulator") ||
                    Build.MODEL.contains("Android SDK built for") ||
                    Build.PRODUCT.startsWith("sdk") ||
                    Build.HARDWARE == "goldfish" || Build.HARDWARE == "ranchu"
                )
        )
    }

    private fun shareReport(call: MethodCall, result: MethodChannel.Result) {
        if (closing || isFinishing || isDestroyed) {
            result.error("share_activity_closed", "The activity has closed.", null)
            return
        }
        if (pendingShare != null) {
            result.error("share_busy", "A report is already being prepared.", null)
            return
        }
        val filename = call.argument<String>("filename")
        val contents = call.argument<String>("contents")
        if (filename == null || contents == null ||
            filename.length > 96 ||
            !filename.matches(Regex("SmartFit-performance-[A-Za-z0-9_-]+\\.json")) ||
            contents.length > MAX_REPORT_BYTES
        ) {
            result.error("invalid_report", "Invalid performance report.", null)
            return
        }
        pendingShare = result
        try {
            exportExecutor.execute {
                var report: File? = null
                try {
                    val bytes = contents.toByteArray(Charsets.UTF_8)
                    require(bytes.size <= MAX_REPORT_BYTES) { "Report exceeds size limit" }
                    val directory = File(cacheDir, "performance_reports/${UUID.randomUUID()}")
                    check(directory.mkdirs()) { "Could not create report directory" }
                    val preparedReport = File(directory, filename)
                    report = preparedReport
                    preparedReport.outputStream().use { it.write(bytes) }
                    if (closing || Thread.currentThread().isInterrupted) {
                        report.delete()
                        directory.delete()
                        return@execute
                    }
                    // FileProvider resolves canonical paths and reads XML configuration.
                    // Keep that setup on the export worker along with the file write.
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.performance_reports",
                        preparedReport
                    )
                    runOnUiThread {
                        if (pendingShare !== result || closing) return@runOnUiThread
                        if (isFinishing || isDestroyed) {
                            finishShare("share_activity_closed")
                            return@runOnUiThread
                        }
                        try {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/json"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData = ClipData.newRawUri("SmartFit performance report", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(sendIntent, "Share performance report"))
                            // True means that the system chooser opened, not that a user sent a file.
                            finishShare()
                        } catch (_: Exception) {
                            finishShare("share_unavailable")
                        }
                    }
                } catch (_: Exception) {
                    report?.delete()
                    report?.parentFile?.delete()
                    runOnUiThread {
                        if (pendingShare === result) finishShare("share_write_failed")
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            finishShare("share_activity_closed")
        }
    }

    private fun finishShare(errorCode: String? = null) {
        val result = pendingShare
        pendingShare = null
        if (errorCode == null) result?.success(true)
        else result?.error(errorCode, "The performance report could not be shared.", null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        performanceChannel?.setMethodCallHandler(null)
        performanceChannel = null
        finishShare("share_activity_closed")
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        closing = true
        finishShare("share_activity_closed")
        exportExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val MAX_REPORT_BYTES = 8 * 1024 * 1024
    }
}
