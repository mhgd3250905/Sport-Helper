package com.ugk.smartfit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/** Missing-cover fallback only: bounded frame-zero decode, never a live player. */
internal class GuidePosterExtractor(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "smartfit/guide_poster")
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "frameZero") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val source = call.argument<String>("source")
            val key = call.argument<String>("cacheKey")
            val width = call.argument<Int>("width")
            val time = call.argument<Number>("timeUs")
            if (source == null || source.length > 4096 || key == null ||
                !key.matches(Regex("[a-f0-9]{64}")) || width != 720 || time?.toLong() != 0L
            ) {
                result.error("invalid_poster_request", "Invalid poster request.", null)
                return@setMethodCallHandler
            }
            val packed = call.argument<Boolean>("packedAlpha") == true
            worker.execute {
                if (closed) return@execute
                val path = try { extract(Uri.parse(source), key, packed) } catch (_: Exception) { null }
                main.post { if (!closed) result.success(path) }
            }
        }
    }

    private fun extract(source: Uri, key: String, packed: Boolean): String? {
        if (closed || Thread.currentThread().isInterrupted) return null
        val directory = File(app.cacheDir, "guide-first-frames-v1")
        if (!directory.isDirectory && !directory.mkdirs()) return null
        val target = File(directory, "$key.webp")
        if (target.isFile && target.length() > 0) {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(target.absolutePath, bounds)
            if (bounds.outWidth == 720 && bounds.outHeight in 1..4096 &&
                bounds.outMimeType == "image/webp") {
                val cached = BitmapFactory.decodeFile(target.absolutePath)
                if (cached != null) {
                    cached.recycle()
                    return target.absolutePath
                }
            }
        }
        val retriever = MediaMetadataRetriever()
        var raw: Bitmap? = null
        var output: Bitmap? = null
        val temporary = File(directory, "$key.pending")
        try {
            when (source.scheme) {
                "file" -> {
                    val file = File(source.path ?: return null).canonicalFile
                    // Only verified App-private material is eligible. No remote URL
                    // or unrelated shared-storage file is decoded by this channel.
                    val roots = listOfNotNull(app.filesDir, app.cacheDir, app.getExternalFilesDir(null))
                    if (!file.isFile || roots.none {
                            file.path.startsWith(it.canonicalPath + File.separator)
                        }) return null
                    retriever.setDataSource(file.absolutePath)
                }
                "asset" -> {
                    val asset = source.path?.removePrefix("/") ?: return null
                    if (!asset.startsWith("assets/") || asset.contains("..") || asset.contains('\\')) return null
                    val lookup = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
                    app.assets.openFd(lookup).use {
                        retriever.setDataSource(it.fileDescriptor, it.startOffset, it.length)
                    }
                }
                else -> return null
            }
            if (closed || Thread.currentThread().isInterrupted) return null
            val videoWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
                ?.takeIf { it > 0 } ?: return null
            val videoHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
                ?.takeIf { it > 0 } ?: return null
            val scaledHeight = max(if (packed) 2 else 1,
                (720.0 * videoHeight / videoWidth).roundToInt())
            raw = if (Build.VERSION.SDK_INT >= 27) {
                retriever.getScaledFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST, 720, scaledHeight)
            } else {
                retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST)
            } ?: return null
            val frame = Bitmap.createScaledBitmap(raw, 720, scaledHeight, true)
            if (frame !== raw) raw.recycle()
            raw = frame
            val resultBitmap = if (packed) unpack(frame) else frame
            output = resultBitmap
            if (closed || Thread.currentThread().isInterrupted) return null
            @Suppress("DEPRECATION")
            val format = if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSLESS
                else Bitmap.CompressFormat.WEBP
            temporary.outputStream().use {
                if (!resultBitmap.compress(format, 100, it)) return null
                it.flush()
            }
            if (!temporary.renameTo(target)) return null
            return target.absolutePath
        } finally {
            if (output !== raw) output?.recycle()
            raw?.recycle()
            retriever.release()
            temporary.delete()
        }
    }

    /** The SDK's public packed source is RGB above its grayscale alpha plane. */
    private fun unpack(frame: Bitmap): Bitmap {
        val height = frame.height / 2
        val pixels = IntArray(720 * height)
        val alpha = IntArray(pixels.size)
        frame.getPixels(pixels, 0, 720, 0, 0, 720, height)
        frame.getPixels(alpha, 0, 720, 0, height, 720, height)
        for (i in pixels.indices) {
            val opacity = (alpha[i] ushr 16) and 255
            pixels[i] = (pixels[i] and 0x00ffffff) or (opacity shl 24)
        }
        return Bitmap.createBitmap(pixels, 720, height, Bitmap.Config.ARGB_8888)
    }

    fun dispose() {
        closed = true
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }
}
