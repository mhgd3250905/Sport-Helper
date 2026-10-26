package com.ugk.smartfit

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.system.Os
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

/** This source and its channel are compiled only by the internal flavor. */
internal class PoseHubPackInstaller(context: Context, messenger: BinaryMessenger) {
    private val application = context.applicationContext
    @Volatile private var closed = false
    private val channel = MethodChannel(messenger, "smartfit/posehub_pack").also {
        it.setMethodCallHandler { call, result ->
            if (call.method != "ensureInstalled") {
                result.notImplemented()
            } else if (call.arguments != null) {
                result.error("invalid_posehub_request", "The local pack accepts no path or URL.", null)
            } else {
                PoseHubPackWorker.ensureInstalled(application) { uri, error ->
                    if (closed) return@ensureInstalled
                    if (error == null) result.success(uri)
                    else result.error("posehub_install_failed", "本地动作包准备失败，请检查可用空间后重试。", null)
                }
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        // The process-owned installation survives an Activity recreation.
    }
}

private object PoseHubPackWorker {
    private const val ASSETS = "flutter_assets/assets/posehub/"
    private const val VERSION = "app-test-pack-r1-v2"
    private const val DESCRIPTOR_SHA = "a8109dfcc7612797e1462d78677f9110806833248e4dd7ef062c0e1b525682b6"
    private const val DESCRIPTOR_BYTES = 1377L
    private val lock = Any()
    private val executor = Executors.newSingleThreadExecutor { Thread(it, "smartfit-posehub-install") }
    private val main = Handler(Looper.getMainLooper())
    private var waiting: MutableList<(String?, Exception?) -> Unit>? = null
    private var installed: String? = null

    fun ensureInstalled(context: Context, callback: (String?, Exception?) -> Unit) {
        synchronized(lock) {
            installed?.let { uri -> main.post { callback(uri, null) }; return }
            waiting?.let { it.add(callback); return }
            waiting = mutableListOf(callback)
        }
        executor.execute {
            var uri: String? = null
            var failure: Exception? = null
            try {
                val descriptor = context.assets.open(ASSETS + "posehub-app-test-pack-r1-v2.descriptor.json").use {
                    PoseHubPackArchive.readPinned(it, DESCRIPTOR_BYTES, DESCRIPTOR_SHA)
                }
                val layout = PoseHubPackLayout.parse(descriptor)
                val root = File(context.filesDir, "posehub").canonicalFile
                val destination = File(root, VERSION)
                val archive = PoseHubPackArchive(
                    layout,
                    DESCRIPTOR_SHA,
                    { context.assets.open(ASSETS + layout.archiveName) },
                    { metadata -> PoseHubPackLayout.mediaFromManifest(metadata) },
                    { existing, target ->
                        runCatching { Os.link(existing.path, target.path) }.isSuccess
                    }
                )
                val result = archive.install(
                    destination,
                    listOf(File(root, "app-test-pack-r1"), File(root, "app-test-pack-r1-v1"))
                )
                uri = result.toURI().toASCIIString().let { if (it.endsWith('/')) it else "$it/" }
            } catch (error: Exception) {
                failure = error
            }
            val callbacks = synchronized(lock) {
                if (failure == null) installed = uri
                val callers = waiting.orEmpty().toList()
                waiting = null
                callers
            }
            main.post { callbacks.forEach { it(uri, failure) } }
        }
    }
}

internal data class PoseHubPackFile(val path: String, val bytes: Long, val sha256: String)

internal data class PoseHubPackLayout(
    val archiveName: String,
    val archiveBytes: Long,
    val archiveSha256: String,
    val entries: Int,
    val mediaFiles: Int,
    val mediaBytes: Long,
    val metadataBytes: Long,
    val metadata: Map<String, PoseHubPackFile>
) {
    companion object {
        fun parse(bytes: ByteArray): PoseHubPackLayout {
            val json = JSONObject(bytes.toString(Charsets.UTF_8))
            require(json.getString("format") == "ugk-posehub-pack-descriptor@1")
            require(json.getString("packId") == "app-test-pack-r1")
            val archive = json.getJSONObject("archive")
            val archiveName = archive.getString("name")
            require(archiveName == "posehub-app-test-pack-r1-v2.zip")
            require(archive.getString("format") == "zip" && archive.getString("compression") == "stored")
            val records = json.getJSONObject("files")
            val metadata = records.keys().asSequence().associateWith { name ->
                val row = records.getJSONObject(name)
                PoseHubPackFile(name, row.getLong("bytes"), row.getString("sha256"))
            }
            require(metadata.keys == setOf("catalog.json", "catalog/catalog.json", "manifest.json"))
            val result = PoseHubPackLayout(
                archiveName, archive.getLong("bytes"), archive.getString("sha256"),
                archive.getInt("entries"), json.getInt("mediaFiles"), json.getLong("mediaBytes"),
                json.getLong("metadataBytes"), metadata
            )
            result.validate()
            require(result.entries == json.getInt("archiveEntries"))
            require(metadata.size == json.getInt("metadataFiles"))
            require(metadata.getValue("catalog.json").sha256 == json.getString("catalogSha256"))
            require(metadata.getValue("manifest.json").sha256 == json.getString("manifestSha256"))
            require(metadata.getValue("catalog/catalog.json").sha256 == json.getString("semanticCatalogSha256"))
            require(json.getInt("semanticComplete") + json.getInt("semanticPending") == json.getInt("actions"))
            return result
        }

        fun mediaFromManifest(bytes: ByteArray): Map<String, PoseHubPackFile> {
            val manifest = JSONObject(bytes.toString(Charsets.UTF_8))
            require(manifest.getString("format") == "pose-hub-stacked-alpha-delivery@1")
            val actions = manifest.getJSONArray("actions")
            val result = linkedMapOf<String, PoseHubPackFile>()
            val ids = hashSetOf<String>()
            for (index in 0 until actions.length()) {
                val row = actions.getJSONObject(index)
                require(ids.add(row.getString("id"))) { "Duplicate action" }
                val files = row.getJSONObject("files")
                for (kind in listOf("video", "cover", "thumbnail")) {
                    val file = files.getJSONObject(kind)
                    val name = file.getString("path")
                    require(name.startsWith("media/"))
                    require(result.put(name, PoseHubPackFile(name, file.getLong("bytes"), file.getString("sha256"))) == null)
                }
            }
            require(actions.length() == manifest.getInt("readyCount"))
            require(actions.length() == manifest.getInt("totalCount"))
            require(manifest.getInt("pendingCount") == 0)
            return result
        }
    }

    fun validate() {
        require(archiveBytes in 1..(2L * 1024 * 1024 * 1024))
        require(entries in 1..10000 && mediaFiles > 0 && entries == mediaFiles + metadata.size)
        require(mediaBytes in 1..(2L * 1024 * 1024 * 1024))
        require(metadataBytes == metadata.values.sumOf { it.bytes } && metadataBytes <= 16L * 1024 * 1024)
        require(Regex("[a-f0-9]{64}").matches(archiveSha256))
        metadata.values.forEach(::validateFile)
    }
}

private fun validateFile(file: PoseHubPackFile) {
    require(file.bytes > 0 && Regex("[a-f0-9]{64}").matches(file.sha256))
    checkedPackPath(file.path)
}

/** Same strict relative-path contract as the SDK's verified posehub_pack.py. */
internal fun checkedPackPath(name: String): String {
    require(name.isNotEmpty() && name.length <= 1024)
    require(!name.startsWith('/') && !name.contains('\\') && !name.contains(':'))
    require(name.none { it.code < 32 || it.code == 127 })
    require(name.split('/').all { it.isNotEmpty() && it != "." && it != ".." && !it.endsWith('.') && !it.endsWith(' ') })
    return name
}

/** Platform-free streaming core; the Android bridge supplies assets and links. */
internal class PoseHubPackArchive(
    private val layout: PoseHubPackLayout,
    private val descriptorSha256: String,
    private val openArchive: () -> InputStream,
    private val readMedia: (ByteArray) -> Map<String, PoseHubPackFile>,
    private val link: (File, File) -> Boolean = { _, _ -> false }
) {
    private val marker = "$descriptorSha256\n${layout.archiveSha256}\n"

    fun install(destination: File, previous: List<File> = emptyList()): File {
        layout.validate()
        require(destination.absoluteFile == destination.canonicalFile) { "Installation contains a link" }
        if (complete(destination)) return destination
        check(!destination.exists()) { "A conflicting installation is preserved" }
        val parent = destination.parentFile!!
        check(parent.isDirectory || parent.mkdirs())
        require(parent.absoluteFile == parent.canonicalFile)
        // A killed process cannot run finally. Reclaim only this version's
        // unpublished UUID stages before starting another full-size copy.
        val staleStage = Regex("\\.${Regex.escape(destination.name)}\\.install-[a-f0-9-]{36}")
        parent.listFiles()?.filter { staleStage.matches(it.name) }?.forEach {
            require(it.absoluteFile == it.canonicalFile && it.parentFile!!.canonicalFile == parent.canonicalFile)
            check(it.deleteRecursively()) { "Could not remove an unpublished stage" }
        }
        val stage = File(parent, ".${destination.name}.install-${UUID.randomUUID()}")
        check(stage.mkdir())
        try {
            // Pass one verifies all APK bytes, including the ZIP directory and
            // trailer. Pass two streams extraction without a second archive copy.
            openArchive().use { copyVerified(it, NullOutput, layout.archiveBytes, layout.archiveSha256) }
            val expected = layout.metadata.toMutableMap()
            val seen = hashSetOf<String>()
            val folded = hashSetOf<String>()
            var totalBytes = 0L
            var media: Map<String, PoseHubPackFile>? = null
            ZipInputStream(openArchive().buffered(BUFFER)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val name = checkedPackPath(entry.name)
                    require(!entry.isDirectory && entry.method == ZipEntry.STORED)
                    require(seen.add(name) && folded.add(name.lowercase(Locale.ROOT))) { "Duplicate entry" }
                    require(seen.size <= layout.entries)
                    val spec = expected[name] ?: error("Unexpected or out-of-order entry")
                    require(entry.size == spec.bytes)
                    val target = inside(stage, name)
                    check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
                    val old = if (name.startsWith("media/")) previous.asSequence().mapNotNull { root ->
                        val file = inside(root, name)
                        if (verifiedFile(file, spec)) file else null
                    }.firstOrNull() else null
                    val linked = old != null && link(old, target)
                    if (linked) copyVerified(zip, NullOutput, spec.bytes, spec.sha256)
                    else FileOutputStream(target).use { copyVerified(zip, it, spec.bytes, spec.sha256) }
                    totalBytes += spec.bytes
                    require(totalBytes <= layout.mediaBytes + layout.metadataBytes)
                    zip.closeEntry()
                    if (name == "manifest.json") {
                        val entries = readMedia(target.readBytes())
                        media = entries
                        require(entries.size == layout.mediaFiles && entries.values.sumOf { it.bytes } == layout.mediaBytes)
                        entries.values.forEach(::validateFile)
                        require(entries.values.all { it.path.startsWith("media/") && it.bytes <= layout.mediaBytes })
                        require(entries.keys.map { it.lowercase(Locale.ROOT) }.toSet().size == entries.size)
                        require(entries.keys.none { expected.containsKey(it) })
                        expected.putAll(entries)
                    }
                }
            }
            require(media != null && seen == expected.keys && seen.size == layout.entries)
            require(totalBytes == layout.mediaBytes + layout.metadataBytes)
            FileOutputStream(File(stage, COMPLETE)).use {
                it.write(marker.toByteArray(Charsets.UTF_8))
                it.fd.sync()
            }
            check(!destination.exists() && stage.renameTo(destination)) { "Could not publish installation" }
            return destination
        } finally {
            // Only our unique unpublished stage is disposable; installed v1/v2
            // directories and user data are never cleaned or overwritten.
            if (stage.exists()) {
                check(stage.parentFile!!.canonicalFile == parent.canonicalFile)
                stage.deleteRecursively()
            }
        }
    }

    private fun complete(root: File): Boolean {
        if (!root.isDirectory) return false
        val done = inside(root, COMPLETE)
        if (!done.isFile || done.length() != marker.toByteArray(Charsets.UTF_8).size.toLong() || done.readText() != marker) return false
        if (!layout.metadata.values.all { verifiedFile(inside(root, it.path), it) }) return false
        val media = readMedia(inside(root, "manifest.json").readBytes())
        if (media.size != layout.mediaFiles || media.values.sumOf { it.bytes } != layout.mediaBytes) return false
        // Private immutable files were SHA-verified before publication. Check
        // every file's presence/size on the warm path without reading 600 MB.
        return media.values.all { spec ->
            validateFile(spec)
            val file = inside(root, spec.path)
            file.isFile && file.length() == spec.bytes
        }
    }

    private fun verifiedFile(file: File, spec: PoseHubPackFile): Boolean {
        if (!file.isFile || file.length() != spec.bytes) return false
        return file.inputStream().use { input ->
            runCatching { copyVerified(input, NullOutput, spec.bytes, spec.sha256); true }.getOrDefault(false)
        }
    }

    companion object {
        private const val BUFFER = 128 * 1024
        private const val COMPLETE = ".posehub-complete"
        private val NullOutput = object : OutputStream() {
            override fun write(value: Int) = Unit
            override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit
        }

        private fun inside(root: File, name: String): File {
            checkedPackPath(name)
            val file = File(root, name)
            require(file.absoluteFile == file.canonicalFile && file.canonicalPath.startsWith(root.canonicalPath + File.separator)) { "Path contains a link or escapes root" }
            return file
        }

        fun readPinned(input: InputStream, bytes: Long, sha256: String): ByteArray {
            require(bytes in 1..(16L * 1024 * 1024))
            val output = ByteArrayOutputStream(bytes.toInt())
            copyVerified(input, output, bytes, sha256)
            return output.toByteArray()
        }

        private fun copyVerified(input: InputStream, output: OutputStream, expectedBytes: Long, expectedSha256: String) {
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(BUFFER)
            var count = 0L
            while (true) {
                val size = input.read(buffer)
                if (size < 0) break
                if (size == 0) continue
                count += size
                require(count <= expectedBytes) { "Entry exceeds its byte limit" }
                digest.update(buffer, 0, size)
                output.write(buffer, 0, size)
            }
            require(count == expectedBytes && digest.digest().joinToString("") { "%02x".format(it) } == expectedSha256) { "Bytes or SHA256 mismatch" }
        }
    }
}
