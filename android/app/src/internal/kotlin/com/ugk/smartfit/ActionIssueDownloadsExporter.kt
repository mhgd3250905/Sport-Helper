package com.ugk.smartfit

import android.annotation.TargetApi
import android.app.Activity
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** Internal-only, direct Downloads export. No picker, sharing, or storage permission. */
internal class ActionIssueDownloadsExporter(activity: Activity, messenger: BinaryMessenger) {
    private class Request(val result: MethodChannel.Result)
    private class InvalidReport : Exception()
    private class ExportClosed : Exception()

    private val activityRef = WeakReference(activity)
    private val resolver = activity.applicationContext.contentResolver
    private val lock = Any()
    private var pending: Request? = null // guarded by lock
    @Volatile private var closed = false
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "smartfit-action-issue-export")
    }
    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(::onMethodCall)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveToDownloads") {
            result.notImplemented()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "action_issue_export_unsupported",
                "当前 Android 版本不支持直接保存到下载，需要 Android 10 或更新版本。",
                null
            )
            return
        }
        val arguments = call.arguments as? Map<*, *>
        val filename = arguments?.get("filename") as? String
        val contents = arguments?.get("contents") as? String
        if (filename == null || contents == null || filename.length > 96 ||
            !FILENAME.matches(filename) || contents.length > MAX_BYTES ||
            arguments?.get("mimeType") != "application/json"
        ) {
            result.error("invalid_action_issue_export", "动作标记 JSON 无效，未保存到下载。", null)
            return
        }
        val request = Request(result)
        synchronized(lock) {
            if (isActivityClosed()) {
                result.error("action_issue_export_activity_closed", CLOSED_MESSAGE, null)
                return
            }
            if (pending != null) {
                result.error("action_issue_export_busy", "正在保存动作标记到下载，请稍候。", null)
                return
            }
            pending = request
        }
        try {
            worker.execute { writeReport(request, filename, contents) }
        } catch (_: RejectedExecutionException) {
            finishError(request, "action_issue_export_activity_closed", CLOSED_MESSAGE)
        }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun writeReport(request: Request, filename: String, contents: String) {
        var inserted: Uri? = null
        var accepted = false
        try {
            ensureActive(request)
            // UTF-8 byte size, JSON parsing, and every provider operation stay
            // off the Flutter platform thread. Character count is only an early bound.
            val bytes = contents.toByteArray(Charsets.UTF_8)
            if (bytes.size > MAX_BYTES) throw InvalidReport()
            val report = try {
                JSONObject(contents)
            } catch (_: Exception) {
                throw InvalidReport()
            }
            if (report.opt("schemaVersion") != 1) throw InvalidReport()
            val issues = report.optJSONArray("issues") ?: throw InvalidReport()
            for (index in 0 until issues.length()) {
                if (issues.optJSONObject(index) == null) throw InvalidReport()
            }
            ensureActive(request)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/SmartFit"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Downloads insertion failed")
            inserted = uri
            check(uri.scheme == "content")
            ensureActive(request)
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IllegalStateException("Downloads stream unavailable")
            output.use {
                it.write(bytes)
                it.flush()
            }
            ensureActive(request)
            val published = resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null
            )
            check(published == 1) { "Downloads publication failed" }
            // MediaStore may disambiguate a duplicate filename. Return its
            // actual saved name, rather than guessing what the user will see.
            val displayName = resolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                check(cursor.moveToFirst()) { "Saved download unavailable" }
                cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME))
            } ?: throw IllegalStateException("Saved download name unavailable")
            check(displayName.isNotEmpty()) { "Saved download name unavailable" }
            ensureActive(request)
            accepted = finishSuccess(request, uri, displayName)
            if (!accepted) {
                finishError(request, "action_issue_export_activity_closed", CLOSED_MESSAGE)
            }
        } catch (_: InvalidReport) {
            finishError(request, "invalid_action_issue_export", "动作标记 JSON 无效，未保存到下载。")
        } catch (_: ExportClosed) {
            finishError(request, "action_issue_export_activity_closed", CLOSED_MESSAGE)
        } catch (_: Exception) {
            finishError(request, "action_issue_export_write_failed", "保存到下载失败，本机标记仍保留，请重试。")
        } finally {
            if (!accepted) {
                // Only this request's newly inserted row is eligible for cleanup.
                // Never enumerate/delete older exports or other Downloads files.
                inserted?.let { uri -> runCatching { resolver.delete(uri, null, null) } }
            }
        }
    }

    private fun isActivityClosed(): Boolean {
        val activity = activityRef.get()
        return closed || activity == null || activity.isFinishing || activity.isDestroyed
    }

    private fun ensureActive(request: Request) {
        synchronized(lock) {
            if (pending !== request || isActivityClosed() || Thread.currentThread().isInterrupted) {
                throw ExportClosed()
            }
        }
    }

    // MethodChannel.Result supports replies from any thread. Serializing the
    // final reply with close() makes publication/teardown races single-reply.
    private fun finishSuccess(request: Request, uri: Uri, displayName: String): Boolean =
        synchronized(lock) {
            if (pending !== request || isActivityClosed()) return@synchronized false
            pending = null
            request.result.success(mapOf("uri" to uri.toString(), "displayName" to displayName))
            true
        }

    private fun finishError(request: Request, code: String, message: String) {
        synchronized(lock) {
            if (pending !== request) return
            pending = null
            request.result.error(code, message, null)
        }
    }

    /** Called from both engine cleanup and Activity destruction; idempotent. */
    fun close() {
        val request = synchronized(lock) {
            if (closed) return
            closed = true
            pending.also { pending = null }
        }
        // A detached engine may no longer accept a handler/reply. This bridge
        // must still release its worker and let other Activity cleanup proceed.
        runCatching { channel.setMethodCallHandler(null) }
        runCatching {
            request?.result?.error("action_issue_export_activity_closed", CLOSED_MESSAGE, null)
        }
        // An in-progress provider operation may ignore interruption. Its
        // worker still observes closed afterwards and cleans its own row.
        worker.shutdownNow()
    }

    companion object {
        private const val CHANNEL = "smartfit/action_issue_export"
        private const val MAX_BYTES = 8 * 1024 * 1024
        private const val CLOSED_MESSAGE = "页面已关闭，未完成保存到下载。"
        private val FILENAME = Regex("SmartFit-action-issues-[0-9TZ]+\\.json")
    }
}
