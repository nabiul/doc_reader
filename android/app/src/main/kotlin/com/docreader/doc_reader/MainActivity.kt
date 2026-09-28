package com.docreader.doc_reader

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "doc_reader/incoming_document"
    private var channel: MethodChannel? = null
    private var pendingDocument: Map<String, String>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureDocument(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialDocument") {
                result.success(pendingDocument)
                pendingDocument = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureDocument(intent)
        pendingDocument?.let { document ->
            channel?.invokeMethod("incomingDocument", document)
            pendingDocument = null
        }
    }

    private fun captureDocument(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        try {
            val displayName = queryDisplayName(uri) ?: "opened_document"
            val safeName = displayName.replace(Regex("[^A-Za-z0-9._ -]"), "_")
            val folder = File(cacheDir, "incoming_documents").apply { mkdirs() }
            val target = File(folder, "${System.currentTimeMillis()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return
            pendingDocument = mapOf(
                "path" to target.absolutePath,
                "name" to displayName,
                "mimeType" to (intent.type ?: contentResolver.getType(uri).orEmpty()),
            )
        } catch (_: Exception) {
            pendingDocument = null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) return cursor.getString(index)
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
