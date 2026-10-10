package com.nolean.no_lean

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Writes exports through SAF, without broad storage permissions or share-sheet lifetime races. */
internal class DocumentExportChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private data class Pending(val bytes: ByteArray, val result: MethodChannel.Result)

    private val channel = MethodChannel(messenger, "no_lean/export")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "NOLEANExport").apply { isDaemon = true }
    }
    private var pending: Pending? = null
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pending != null) {
                result.error("EXPORT_BUSY", "Finish the current export first.", null)
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType")
            if (bytes == null || bytes.isEmpty() || fileName.isNullOrBlank() ||
                fileName.contains('/') || fileName.contains('\\') ||
                mimeType !in listOf("application/json", "text/csv")) {
                result.error("EXPORT_ARGUMENT", "Invalid export request.", null)
                return@setMethodCallHandler
            }
            val request = Pending(bytes, result)
            pending = request
            try {
                activity.startActivityForResult(
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeType
                        putExtra(Intent.EXTRA_TITLE, fileName)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    },
                    REQUEST_CODE,
                )
            } catch (_: Exception) {
                pending = null
                result.error("EXPORT_PICKER", "The Save screen could not be opened.", null)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val request = pending ?: return true
        if (resultCode != Activity.RESULT_OK) {
            pending = null
            request.result.success(false)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            pending = null
            request.result.error("EXPORT_DOCUMENT", "No destination was returned.", null)
            return true
        }
        // Cloud and OEM document providers can block. Keep their I/O off the UI thread.
        val resolver = activity.applicationContext.contentResolver
        worker.execute {
            val failure = try {
                DocumentBytes.writeAndVerify(
                    request.bytes,
                    { resolver.openOutputStream(uri, "wt") },
                    { resolver.openInputStream(uri) },
                )
                false
            } catch (_: Exception) {
                true
            }
            main.post {
                if (!disposed && pending === request) {
                    pending = null
                    if (failure) {
                        request.result.error("EXPORT_WRITE", "The destination could not save a verified copy.", null)
                    } else {
                        request.result.success(true)
                    }
                }
            }
        }
        return true
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.result?.error("EXPORT_INTERRUPTED", "Export interrupted. Try again.", null)
        pending = null
        worker.shutdown()
    }

    companion object {
        private const val REQUEST_CODE = 20044
    }
}
