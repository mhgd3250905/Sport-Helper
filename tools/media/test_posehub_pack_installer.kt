package com.ugk.smartfit

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Small synthetic archives only; never opens a device or extracts the 600 MB pack. */
fun main(args: Array<String>) {
    fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun spec(path: String, bytes: ByteArray) = PoseHubPackFile(path, bytes.size.toLong(), sha(bytes))
    val media = linkedMapOf(
        "media/action/video.mp4" to "tiny-video".toByteArray(),
        "media/action/cover.webp" to "tiny-cover".toByteArray(),
        "media/action/thumbnail.webp" to "tiny-thumb".toByteArray()
    )
    val rows = JSONObject()
    for ((role, name) in listOf("video" to "video.mp4", "cover" to "cover.webp", "thumbnail" to "thumbnail.webp")) {
        val path = "media/action/$name"
        rows.put(role, JSONObject().put("path", path).put("bytes", media.getValue(path).size).put("sha256", sha(media.getValue(path))))
    }
    val manifest = JSONObject().put("format", "pose-hub-stacked-alpha-delivery@1")
        .put("actions", JSONArray().put(JSONObject().put("id", "action").put("files", rows)))
        .put("readyCount", 1).put("totalCount", 1).put("pendingCount", 0).toString().toByteArray()
    val metadata = linkedMapOf("catalog.json" to "{\"v\":2}".toByteArray(), "catalog/catalog.json" to "{}".toByteArray(), "manifest.json" to manifest)
    val all = metadata + media
    fun zip(files: List<Pair<String, ByteArray>> = all.toList(), deflated: Boolean = false): ByteArray {
        val buffer = ByteArrayOutputStream()
        ZipOutputStream(buffer).use { output ->
            for ((name, bytes) in files) {
                val entry = ZipEntry(name)
                if (!deflated) {
                    entry.method = ZipEntry.STORED
                    entry.size = bytes.size.toLong()
                    entry.compressedSize = bytes.size.toLong()
                    entry.crc = CRC32().apply { update(bytes) }.value
                }
                output.putNextEntry(entry)
                output.write(bytes)
                output.closeEntry()
            }
        }
        return buffer.toByteArray()
    }
    val goodZip = zip()
    fun layout(bytes: ByteArray) = PoseHubPackLayout(
        "fixture.zip", bytes.size.toLong(), sha(bytes), all.size, media.size,
        media.values.sumOf { it.size.toLong() }, metadata.values.sumOf { it.size.toLong() },
        metadata.mapValues { (path, bytes) -> spec(path, bytes) }
    )
    var cases = 0
    fun case(name: String, run: (File) -> Unit) {
        val root = Files.createTempDirectory("smartfit-pack-test-").toFile().canonicalFile
        try { run(root); cases++; println("PASS $name") } finally { root.deleteRecursively() }
    }
    fun fail(run: () -> Unit) { check(runCatching(run).isFailure) { "Expected rejection" } }
    fun archive(bytes: ByteArray, limits: PoseHubPackLayout = layout(bytes), open: (() -> java.io.InputStream)? = null,
                link: (File, File) -> Boolean = { _, _ -> false }) = PoseHubPackArchive(limits, sha("descriptor".toByteArray()),
        open ?: { bytes.inputStream() }, PoseHubPackLayout::mediaFromManifest, link)

    case("atomic install and warm reuse without reopening APK") { root ->
        var opens = 0
        val target = File(root, "v2")
        archive(goodZip, open = { opens++; goodZip.inputStream() }).install(target)
        check(opens == 2)
        for ((path, bytes) in all) check(File(target, path).readBytes().contentEquals(bytes))
        check(File(target, ".posehub-complete").isFile)
        archive(goodZip, open = { error("Warm install reopened archive") }).install(target)
    }
    case("failed hash preserves v1, leaves no publication, and allows retry") { root ->
        val old = File(root, "v1").apply { mkdir() }
        File(old, "keep").writeText("unchanged")
        var corrupt = true
        val installer = archive(goodZip, open = { if (corrupt) "broken".byteInputStream() else goodZip.inputStream() })
        val target = File(root, "v2")
        fail { installer.install(target, listOf(old)) }
        check(!target.exists() && root.listFiles()!!.map { it.name } == listOf("v1"))
        check(File(old, "keep").readText() == "unchanged")
        corrupt = false
        installer.install(target, listOf(old))
    }
    case("matching old bytes can reuse hardlinks") { root ->
        val old = File(root, "v1").apply { mkdir() }
        for ((name, bytes) in media) File(old, name).apply { parentFile!!.mkdirs(); writeBytes(bytes) }
        var links = 0
        val target = File(root, "v2")
        archive(goodZip, link = { source, destination -> Files.createLink(destination.toPath(), source.toPath()); links++; true })
            .install(target, listOf(old))
        check(links == media.size)
        for (name in media.keys) check(Files.isSameFile(File(old, name).toPath(), File(target, name).toPath()))
    }
    case("same-size wrong old bytes never qualify for reuse") { root ->
        val old = File(root, "v1").apply { mkdir() }
        for ((name, bytes) in media) File(old, name).apply { parentFile!!.mkdirs(); writeBytes(ByteArray(bytes.size)) }
        val target = File(root, "v2")
        archive(goodZip, link = { _, _ -> error("Wrong bytes reused") }).install(target, listOf(old))
        for ((name, bytes) in media) check(File(target, name).readBytes().contentEquals(bytes))
    }
    case("conflicting existing version remains untouched") { root ->
        val target = File(root, "v2").apply { mkdir() }
        File(target, "keep").writeText("preserved")
        fail { archive(goodZip).install(target) }
        check(target.list()!!.toList() == listOf("keep"))
    }
    case("retry reclaims only this version's unpublished stages") { root ->
        val stale = File(root, ".v2.install-00000000-0000-0000-0000-000000000000").apply { mkdir() }
        File(stale, "partial").writeText("interrupted")
        val other = File(root, ".v1.install-00000000-0000-0000-0000-000000000000").apply { mkdir() }
        archive(goodZip).install(File(root, "v2"))
        check(!stale.exists() && other.isDirectory)
    }
    for (path in listOf("../escape", "/absolute", "C:/drive", "a\\b", "a//b", "a/./b", "a/../b", "a/name. ")) {
        case("unsafe path $path") { root ->
            val bytes = zip(listOf(path to "bad".toByteArray()) + all.toList())
            fail { archive(bytes).install(File(root, "v2")) }
            check(root.list()!!.isEmpty())
        }
    }
    case("duplicate case-folded ZIP entry rejected") { root ->
        val bytes = zip(all.toList() + ("media/action/COVER.webp" to media.getValue("media/action/cover.webp")))
        fail { archive(bytes).install(File(root, "v2")) }
        check(root.list()!!.isEmpty())
    }
    case("unexpected ZIP entry rejected") { root ->
        val bytes = zip(listOf("extra.txt" to byteArrayOf(1)) + all.toList())
        fail { archive(bytes).install(File(root, "v2")) }
    }
    case("missing ZIP entry rejected") { root ->
        val bytes = zip(all.toList().dropLast(1))
        fail { archive(bytes).install(File(root, "v2")) }
    }
    case("entry bytes bounded before copying") { root ->
        val altered = layout(goodZip).copy(metadata = layout(goodZip).metadata.toMutableMap().apply {
            this["catalog.json"] = getValue("catalog.json").copy(bytes = 1)
        }, metadataBytes = layout(goodZip).metadataBytes - metadata.getValue("catalog.json").size + 1)
        fail { archive(goodZip, altered).install(File(root, "v2")) }
    }
    case("per-file SHA enforced after whole ZIP verification") { root ->
        val altered = layout(goodZip).copy(metadata = layout(goodZip).metadata.toMutableMap().apply {
            this["catalog.json"] = getValue("catalog.json").copy(sha256 = "0".repeat(64))
        })
        fail { archive(goodZip, altered).install(File(root, "v2")) }
    }
    case("compressed entries rejected by stored-pack contract") { root ->
        val bytes = zip(deflated = true)
        fail { archive(bytes).install(File(root, "v2")) }
    }
    case("metadata budget is bounded") { root ->
        val altered = layout(goodZip).copy(metadataBytes = 20L * 1024 * 1024)
        fail { archive(goodZip, altered).install(File(root, "v2")) }
    }
    case("descriptor byte count and SHA are both pinned") { _ ->
        val bytes = "descriptor".toByteArray()
        check(PoseHubPackArchive.readPinned(bytes.inputStream(), bytes.size.toLong(), sha(bytes)).contentEquals(bytes))
        fail { PoseHubPackArchive.readPinned(bytes.inputStream(), bytes.size.toLong() - 1, sha(bytes)) }
        fail { PoseHubPackArchive.readPinned(bytes.inputStream(), bytes.size.toLong(), "0".repeat(64)) }
    }
    if (args.size == 2) {
        case("actual released descriptor and manifest") { _ ->
            val descriptor = File(args[0]).inputStream().use {
                PoseHubPackArchive.readPinned(it, 1377, "a8109dfcc7612797e1462d78677f9110806833248e4dd7ef062c0e1b525682b6")
            }
            val real = PoseHubPackLayout.parse(descriptor)
            val realMedia = PoseHubPackLayout.mediaFromManifest(File(args[1]).readBytes())
            check(realMedia.size == real.mediaFiles)
            check(realMedia.values.sumOf { it.bytes } == real.mediaBytes)
            check(real.entries == realMedia.size + real.metadata.size)
        }
    }
    println("PoseHub installer checks passed: $cases cases")
}
