package io.jeph.grphoto

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * `io.jeph.grphoto/media`: copies downloaded camera files into MediaStore,
 * one entry per file, under `Pictures/<album>`. Gallery apps show a folder
 * as an album under the folder's name, so movies go there too rather than
 * to `Movies/<album>`, which would be a second album of the same name.
 * Apps may insert their own media on Android 10+ without any storage
 * permission.
 */
class MediaChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val resolver: ContentResolver = context.contentResolver
    private val channel = MethodChannel(messenger, "io.jeph.grphoto/media")
    private val main = Handler(Looper.getMainLooper())
    private val io: ExecutorService = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveShot") {
            result.notImplemented()
            return
        }
        val album = call.argument<String>("album")
        val files = call.argument<List<Map<String, Any?>>>("files")?.map(::fileArgs)
        if (album == null || files == null || files.isEmpty() || files.any { it == null }) {
            result.error("failed", "saveShot needs an album and files with path, name, kind and mimeType", null)
            return
        }
        io.execute {
            val error: Pair<String, String>? = try {
                saveShot(album, files.filterNotNull())
                null
            } catch (e: SecurityException) {
                "permissionDenied" to "Android refused access to the photo library: ${e.message}"
            } catch (e: Exception) {
                "failed" to "saving to the photo library failed: ${e.message}"
            }
            main.post {
                if (error == null) result.success(null) else result.error(error.first, error.second, null)
            }
        }
    }

    private data class FileArgs(val path: String, val name: String, val kind: String, val mimeType: String)

    private fun fileArgs(map: Map<String, Any?>): FileArgs? {
        val path = map["path"] as? String ?: return null
        val name = map["name"] as? String ?: return null
        val kind = map["kind"] as? String ?: return null
        val mimeType = map["mimeType"] as? String ?: return null
        return FileArgs(path, name, kind, mimeType)
    }

    /** All files of the shot land, or none: entries already written are removed on failure. */
    private fun saveShot(album: String, files: List<FileArgs>) {
        val inserted = mutableListOf<Uri>()
        try {
            for (file in files) inserted += save(album, file)
        } catch (e: Exception) {
            for (uri in inserted) {
                try {
                    resolver.delete(uri, null, null)
                } catch (ignored: Exception) {
                    // The original failure is what the caller needs to see.
                }
            }
            throw e
        }
    }

    private fun save(album: String, file: FileArgs): Uri {
        val video = file.kind == "movie"
        val collection = if (video) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val albumPath = "${Environment.DIRECTORY_PICTURES}/$album"
        val source = File(file.path)
        if (!source.isFile) throw IOException("${file.name} is missing")

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, file.mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, albumPath)
            // Hidden from other apps until the copy is complete.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore refused ${file.name}")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IOException("cannot write ${file.name}")
            out.use { sink -> source.inputStream().use { it.copyTo(sink) } }
            val publish = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, publish, null, null)
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Exception) {
                // The copy failure is what the caller needs to see.
            }
            throw e
        }
        return uri
    }
}
