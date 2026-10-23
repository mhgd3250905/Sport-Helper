package com.ugk.smartfit

import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A bounded, on-demand startup-log observation for the internal flavor only.
 * No READ_LOGS permission, shell, file, other PID, raw log export, or frame hook.
 * All public methods run on the Android platform thread.
 */
internal class InternalRendererProbe(minEngineEventEpochMs: Long) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "smartfit-renderer-probe")
    }
    private val watchdog = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "smartfit-renderer-probe-timeout")
    }
    private val pending = mutableListOf<(InternalRendererEvidence) -> Unit>()
    private var scanning = false
    private var scanAgain = false
    private var firstFrameDisplayed = false
    private var confirmedAfterFirstFrame = false
    private var cached = InternalRendererEvidence.unverified("not_observed")
    @Volatile private var closed = false
    @Volatile private var activeProcess: java.lang.Process? = null
    private val ownPid = Process.myPid()
    private val processStartedAtEpochMs = maxOf(minEngineEventEpochMs,
        System.currentTimeMillis() -
            (SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()))

    fun onFirstFrameDisplayed() {
        firstFrameDisplayed = true
        refresh()
    }

    /** Coalesces concurrent callers and runs at most one logcat at a time. */
    fun refresh(callback: ((InternalRendererEvidence) -> Unit)? = null): Boolean {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (closed || pending.size >= MAX_PENDING_REQUESTS) return false
        if (callback != null) pending.add(callback)
        if (scanning) {
            // A first-frame notification can arrive during the early startup
            // read. Read again after it so a Vulkan probe cannot hide fallback.
            scanAgain = true
        } else {
            scan()
        }
        return true
    }

    private fun scan() {
        if (closed) return
        scanning = true
        val startedAfterFirstFrame = firstFrameDisplayed
        try {
            worker.execute {
                val observed = readOwnEngineStartup()
                mainHandler.post {
                    if (closed) return@post
                    val missingOrUnreadable = observed.source in setOf(
                        "android_engine_startup_log_not_found",
                        "android_engine_startup_log_read_failed",
                        "android_engine_startup_log_timed_out",
                        "android_engine_startup_log_limit_reached",
                    )
                    if (confirmedAfterFirstFrame && missingOrUnreadable) {
                        // The renderer of this engine is fixed after startup.
                        // Preserve its confirmed observation if the finite ring
                        // has since evicted it, retaining the evidence provenance.
                        cached = cached.copy(source = "android_engine_startup_log_own_pid_cached")
                    } else {
                        cached = observed
                        confirmedAfterFirstFrame =
                            startedAfterFirstFrame && observed.renderer != "unverified"
                    }
                    scanning = false
                    if (scanAgain) {
                        scanAgain = false
                        scan()
                    } else {
                        val callbacks = pending.toList()
                        pending.clear()
                        callbacks.forEach { it(cached) }
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            scanning = false
            finishClosed()
        }
    }

    private fun readOwnEngineStartup(): InternalRendererEvidence {
        if (closed) return InternalRendererEvidence.unverified("activity_closed")
        var process: java.lang.Process? = null
        val timedOut = AtomicBoolean(false)
        var deadline: java.util.concurrent.ScheduledFuture<*>? = null
        try {
            // PID and engine-source filters are applied by logcat itself. Epoch
            // timestamps additionally reject old records after Android PID reuse.
            process = ProcessBuilder(
                "/system/bin/logcat", "-d", "-b", "main",
                "-v", "threadtime", "-v", "epoch", "--pid=$ownPid",
                "-t", MAX_LOG_LINES.toString(), "-e", ENGINE_SOURCE_FILTER,
                "flutter:I", "*:S"
            ).redirectErrorStream(true).start()
            activeProcess = process
            if (closed) return InternalRendererEvidence.unverified("activity_closed")
            val startedProcess = process
            deadline = watchdog.schedule({
                timedOut.set(true)
                startedProcess.destroy()
            }, MAX_READ_MILLIS, TimeUnit.MILLISECONDS)
            val bytes = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            var overLimit = false
            process.inputStream.use { input ->
                while (!closed && !Thread.currentThread().isInterrupted) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (bytes.size() + count > MAX_LOG_BYTES) {
                        overLimit = true
                        break
                    }
                    bytes.write(buffer, 0, count)
                }
            }
            if (overLimit) return InternalRendererEvidence.unverified("limit_reached")
            if (closed) return InternalRendererEvidence.unverified("activity_closed")
            // waitFor() is available on every supported Android API; the
            // independent watchdog bounds it along with the stream read.
            val exitCode = process.waitFor()
            if (timedOut.get()) {
                return InternalRendererEvidence.unverified("timed_out")
            }
            if (exitCode != 0) return InternalRendererEvidence.unverified("read_failed")
            val parser = InternalRendererEvidenceParser(ownPid, processStartedAtEpochMs)
            bytes.toString(Charsets.UTF_8.name()).lineSequence().forEach(parser::accept)
            return parser.result()
        } catch (_: Exception) {
            return InternalRendererEvidence.unverified("read_failed")
        } finally {
            deadline?.cancel(false)
            process?.destroy()
            activeProcess = null
        }
    }

    fun close() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (closed) return
        closed = true
        activeProcess?.destroy()
        worker.shutdownNow()
        watchdog.shutdownNow()
        finishClosed()
    }

    private fun finishClosed() {
        val callbacks = pending.toList()
        pending.clear()
        val unavailable = InternalRendererEvidence.unverified("activity_closed")
        callbacks.forEach { it(unavailable) }
    }

    companion object {
        private const val MAX_PENDING_REQUESTS = 8
        private const val MAX_LOG_LINES = 512
        private const val MAX_LOG_BYTES = 128 * 1024
        private const val MAX_READ_MILLIS = 1500L
        private const val ENGINE_SOURCE_FILTER =
            "flutter/shell/platform/android/android_context_(vk|gl|dynamic)_impeller[.]cc"
    }
}
