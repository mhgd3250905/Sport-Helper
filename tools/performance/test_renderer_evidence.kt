package com.ugk.smartfit

/** Synthetic engine lines only; never opens a device log or needs Android. */
fun main() {
    fun log(
        backend: String,
        file: String = "vk",
        pid: Int = 42,
        epoch: String = "1000.100",
        severity: String = "IMPORTANT",
    ) = "$epoch  $pid  44 I flutter : [$severity:flutter/shell/platform/android/android_context_${file}_impeller.cc(54)] $backend"
    val vk = "Using the Impeller rendering backend (Vulkan)."
    val gl = "Using the Impeller rendering backend (OpenGLES)."
    val fallback = "Known bad Vulkan driver encountered, falling back to OpenGLES."
    var cases = 0
    fun expect(expected: String, vararg lines: String) {
        val parser = InternalRendererEvidenceParser(42, 1_000_000)
        lines.forEach(parser::accept)
        val result = parser.result()
        check(result.backend == expected) { "Case $cases: ${result.backend} != $expected" }
        check((result.toMap()["rendererVerified"] == true) == (expected != "unverified"))
        cases += 1
    }
    expect("unverified")
    expect("vulkan", log(vk))
    expect("vulkan", log("Using the Impeller rendering backend (Vulkan with Validation Layers)."))
    expect("opengles", log(gl, file = "gl"))
    expect("opengles", log(vk), log(fallback, file = "dynamic", severity = "INFO"), log(gl, file = "gl"))
    expect("unverified", log(vk), log(fallback, file = "dynamic", severity = "INFO"))
    expect("unverified", log(vk), log("Could not create context.", severity = "ERROR"))
    expect("unverified", log(vk, pid = 43))
    expect("unverified", log(vk, epoch = "999.900"))
    expect("unverified", "1000.100 42 44 I flutter : $vk")
    expect("unverified", log(gl, file = "vk"))
    expect("unverified", log(vk, file = "gl"))
    expect("unverified", log(vk, severity = "INFO"))
    expect("vulkan", log(vk), log(fallback, pid = 43))
    expect("unverified", log("Using the Skia rendering backend (OpenGLES).", file = "gl"))
    expect("unverified", "1000.100 42 44 I flutter : [IMPORTANT:other/android_context_vk_impeller.cc(54)] $vk")
    println("Renderer parser checks passed: $cases cases")
}
