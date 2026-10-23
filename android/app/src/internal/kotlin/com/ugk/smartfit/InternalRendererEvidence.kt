package com.ugk.smartfit

/** Only engine observations are evidence. A manifest flag is merely a request. */
internal data class InternalRendererEvidence(
    val renderer: String,
    val backend: String,
    val source: String,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "renderer" to renderer,
        "rendererBackend" to backend,
        "rendererSource" to source,
        "rendererVerified" to (renderer != "unverified"),
    )

    companion object {
        fun unverified(reason: String) = InternalRendererEvidence(
            "unverified", "unverified", "android_engine_startup_log_$reason"
        )
    }
}

/** Parses only this process's engine lines; neither messages nor PIDs leave the bridge. */
internal class InternalRendererEvidenceParser(
    private val expectedPid: Int,
    private val processStartedAtEpochMs: Long,
) {
    private var evidence = InternalRendererEvidence.unverified("not_found")

    fun accept(line: String) {
        val match = ENGINE_LINE.matchEntire(line) ?: return
        val epochMs = (match.groupValues[1].toDoubleOrNull() ?: return) * 1000.0
        if (match.groupValues[2].toIntOrNull() != expectedPid ||
            epochMs < processStartedAtEpochMs - 5
        ) return

        val severity = match.groupValues[3]
        val file = match.groupValues[4]
        val message = match.groupValues[5]
        val backend = when {
            file == "vk" && (message == VULKAN || message == VULKAN_VALIDATION) -> "vulkan"
            file == "gl" && message == OPEN_GLES -> "opengles"
            else -> null
        }
        if (backend != null && severity == "IMPORTANT") {
            // Vulkan can be probed and then rejected. A later OpenGLES message
            // supersedes it; an unfinished fallback must never claim Vulkan.
            evidence = InternalRendererEvidence(
                "impeller", backend, "android_engine_startup_log_own_pid"
            )
        } else if (message == FALLBACK || severity == "ERROR" || severity == "FATAL") {
            evidence = InternalRendererEvidence.unverified("incomplete_fallback")
        }
    }

    fun result(): InternalRendererEvidence = evidence

    companion object {
        // Confirmed against Flutter 3.44.7 engine 69c8c61792f04cc809dfef0c910414fb9afc06cd:
        // engine/src/flutter/shell/platform/android/android_context_{vk,gl}_impeller.cc.
        // This engine has no equivalent successful Skia startup announcement.
        // Missing Impeller evidence therefore stays unverified; it never means Skia.
        private val ENGINE_LINE = Regex(
            "^\\s*(\\d+\\.\\d+)\\s+(\\d+)\\s+\\d+\\s+[IWEF]\\s+flutter\\s*:\\s+" +
                "\\[(IMPORTANT|INFO|WARNING|ERROR|FATAL):flutter/shell/platform/android/" +
                "android_context_(vk|gl|dynamic)_impeller\\.cc\\(\\d+\\)\\]\\s+(.+?)\\s*$"
        )
        private const val VULKAN = "Using the Impeller rendering backend (Vulkan)."
        private const val VULKAN_VALIDATION =
            "Using the Impeller rendering backend (Vulkan with Validation Layers)."
        private const val OPEN_GLES = "Using the Impeller rendering backend (OpenGLES)."
        private const val FALLBACK =
            "Known bad Vulkan driver encountered, falling back to OpenGLES."
    }
}
