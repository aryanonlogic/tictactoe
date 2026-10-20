package com.lucenq.tictactoe

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val pool = Executors.newFixedThreadPool(3)
    private val ui = Handler(Looper.getMainLooper())

    private var pendingShared: List<String> = emptyList()
    private val pending = HashMap<Int, MethodChannel.Result>()
    private var captureFile: File? = null
    private var deleteCount = 0
    private var deleteSkipped = 0

    companion object {
        const val RC_PICK = 9101
        const val RC_CAPTURE = 9102
        const val RC_VIDEO = 9103
        const val RC_DELETE = 9104
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        VaultCrypto.init(applicationContext)
        PinStore.init(applicationContext)
        // leftovers from a previous session (decrypted share copies, camera temp files)
        File(cacheDir, "share").deleteRecursively()
        File(cacheDir, "cap").deleteRecursively()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleIntent(intent, false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, true)
    }

    override fun onPause() {
        VideoViewFactory.pauseAll()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory("ttt/video", VideoViewFactory())
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.lucenq.tictactoe/native")
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    // ---------------- incoming share intents ----------------

    private fun handleIntent(i: Intent?, notify: Boolean) {
        if (i == null) return
        if (i.action != Intent.ACTION_SEND && i.action != Intent.ACTION_SEND_MULTIPLE) return
        val list = LinkedHashSet<String>()
        try {
            if (i.action == Intent.ACTION_SEND) {
                val u: Uri? = if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM)
                if (u != null) list.add(u.toString())
            } else {
                val us: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") i.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                us?.forEach { list.add(it.toString()) }
            }
            val cd = i.clipData
            if (cd != null) for (k in 0 until cd.itemCount) cd.getItemAt(k).uri?.let { list.add(it.toString()) }
        } catch (e: Exception) {
        }
        if (list.isEmpty()) return
        pendingShared = list.toList()
        i.action = null
        if (notify) channel.invokeMethod("shared", null)
    }

    // ---------------- channel ----------------

    private fun bg(result: MethodChannel.Result, block: () -> Any?) {
        pool.execute {
            try {
                val r = block()
                ui.post { result.success(r) }
            } catch (e: Throwable) {
                ui.post { result.error("ERR", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPin" -> result.success(PinStore.has())
            "setPin" -> bg(result) { PinStore.set(call.argument<String>("pin")!!); true }
            "verifyPin" -> bg(result) { PinStore.verify(call.argument<String>("pin")!!, call.argument<Boolean>("dev") ?: false) }
            "getSettings" -> bg(result) { VaultCrypto.readSettings() }
            "saveSettings" -> bg(result) { VaultCrypto.writeSettings(call.argument<String>("json")!!); true }
            "loadIndex" -> bg(result) { VaultCrypto.readIndex() }
            "saveIndex" -> bg(result) { VaultCrypto.writeIndex(call.argument<String>("json")!!); true }
            "cleanupOrphans" -> bg(result) {
                VaultCrypto.cleanupOrphans(call.argument<List<String>>("ids")!!.toSet()); true
            }
            "deleteBlobs" -> bg(result) { VaultCrypto.deleteBlobs(call.argument<List<String>>("ids")!!); true }
            "wipeAll" -> bg(result) { VaultCrypto.wipeMedia(); true }
            "getThumb" -> bg(result) { VaultCrypto.readThumb(call.argument<String>("id")!!) }
            "getPhoto" -> bg(result) {
                MediaOps.photoBytes(
                    call.argument<String>("id")!!, call.argument<String>("mime") ?: "image/jpeg",
                    call.argument<Int>("maxSide") ?: 2048
                )
            }
            "importUris" -> bg(result) {
                MediaOps.importAll(
                    applicationContext, call.argument<List<String>>("uris")!!, call.argument<List<String>>("known")!!
                )
            }
            "pick" -> startPick(call.argument<String>("kind") ?: "image", result)
            "capture" -> startCapture(call.argument<String>("kind") ?: "image", result)
            "purgeCapture" -> {
                File(cacheDir, "cap").deleteRecursively()
                result.success(true)
            }
            "deleteOriginals" -> deleteOriginals(call.argument<List<String>>("uris")!!, result)
            "restore" -> {
                val items = call.argument<List<Map<String, Any?>>>("items")!!
                bg(result) {
                    val ok = ArrayList<String>()
                    for (m in items) {
                        if (MediaOps.restore(
                                applicationContext, m["id"] as String, m["name"] as String,
                                m["mime"] as String, m["hash"] as String
                            )
                        ) ok.add(m["id"] as String)
                    }
                    ok
                }
            }
            "share" -> shareItems(call.argument<List<Map<String, Any?>>>("items")!!, result)
            "clearShareCache" -> {
                File(cacheDir, "share").deleteRecursively()
                result.success(true)
            }
            "setSecure" -> {
                if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                result.success(true)
            }
            "takeShared" -> {
                val l = pendingShared
                pendingShared = emptyList()
                result.success(l)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------- pickers ----------------

    private fun photoPickerAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 33 ||
            (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)

    private fun pickMax(): Int = try {
        minOf(100, MediaStore.getPickImagesMaxLimit())
    } catch (t: Throwable) {
        50
    }

    @Suppress("DEPRECATION")
    private fun startPick(kind: String, result: MethodChannel.Result) {
        if (pending.containsKey(RC_PICK)) {
            result.error("BUSY", "Another picker is open", null)
            return
        }
        pending[RC_PICK] = result
        try {
            val intent = if (kind == "files") {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
            } else if (photoPickerAvailable()) {
                Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                    type = if (kind == "video") "video/*" else "image/*"
                    putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, pickMax())
                }
            } else {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (kind == "video") "video/*" else "image/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
            }
            startActivityForResult(intent, RC_PICK)
        } catch (e: Exception) {
            pending.remove(RC_PICK)?.error("PICK", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun startCapture(kind: String, result: MethodChannel.Result) {
        val video = kind == "video"
        val rc = if (video) RC_VIDEO else RC_CAPTURE
        if (pending.containsKey(rc)) {
            result.error("BUSY", "Camera already open", null)
            return
        }
        try {
            val dir = File(cacheDir, "cap").apply { mkdirs() }
            val f = File(dir, "cap_${System.currentTimeMillis()}." + if (video) "mp4" else "jpg")
            captureFile = f
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
            val intent = Intent(if (video) MediaStore.ACTION_VIDEO_CAPTURE else MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            pending[rc] = result
            startActivityForResult(intent, rc)
        } catch (e: Exception) {
            pending.remove(rc)
            result.error("CAMERA", e.message ?: "No camera app available", null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            RC_PICK -> {
                val r = pending.remove(RC_PICK) ?: return
                val out = ArrayList<String>()
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val cd = data.clipData
                    if (cd != null) {
                        for (i in 0 until cd.itemCount) cd.getItemAt(i).uri?.let { out.add(it.toString()) }
                    } else {
                        data.data?.let { out.add(it.toString()) }
                    }
                }
                r.success(out)
            }
            RC_CAPTURE, RC_VIDEO -> {
                val r = pending.remove(requestCode) ?: return
                val f = captureFile
                if (resultCode == Activity.RESULT_OK && f != null && f.exists() && f.length() > 0) {
                    r.success(FileProvider.getUriForFile(this, "$packageName.fileprovider", f).toString())
                } else {
                    f?.delete()
                    r.success(null)
                }
            }
            RC_DELETE -> {
                val r = pending.remove(RC_DELETE) ?: return
                r.success(
                    mapOf(
                        "status" to if (resultCode == Activity.RESULT_OK) "deleted" else "cancelled",
                        "count" to deleteCount, "skipped" to deleteSkipped
                    )
                )
            }
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }

    // ---------------- delete originals (user confirmation via system dialog) ----------------

    @Suppress("DEPRECATION")
    private fun deleteOriginals(uris: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 30) {
            result.success(mapOf("status" to "unsupported", "message" to "Automatic deletion needs Android 11 or newer."))
            return
        }
        val conv = ArrayList<Uri>()
        var skipped = 0
        for (s in uris) {
            val m = try { MediaOps.toMediaStoreUri(this, Uri.parse(s)) } catch (e: Exception) { null }
            if (m != null) conv.add(m) else skipped++
        }
        if (conv.isEmpty()) {
            result.success(mapOf("status" to "failed", "message" to "Android did not allow deleting these originals from here."))
            return
        }
        if (pending.containsKey(RC_DELETE)) {
            result.error("BUSY", "Another delete request is open", null)
            return
        }
        try {
            val pi = MediaStore.createDeleteRequest(contentResolver, conv)
            deleteCount = conv.size
            deleteSkipped = skipped
            pending[RC_DELETE] = result
            startIntentSenderForResult(pi.intentSender, RC_DELETE, null, 0, 0, 0)
        } catch (e: Exception) {
            pending.remove(RC_DELETE)
            result.success(mapOf("status" to "failed", "message" to (e.message ?: "Delete request failed")))
        }
    }

    // ---------------- sharing out of the vault ----------------

    private fun shareItems(items: List<Map<String, Any?>>, result: MethodChannel.Result) {
        pool.execute {
            try {
                val root = File(cacheDir, "share")
                root.deleteRecursively()
                root.mkdirs()
                val uris = ArrayList<Uri>()
                val mimes = HashSet<String>()
                items.forEachIndexed { idx, m ->
                    val safe = (m["name"] as String).replace(Regex("[\\\\/:*?\"<>|]"), "_")
                    val f = File(root, "$idx/$safe")
                    VaultCrypto.decryptTo(m["id"] as String, f)
                    uris.add(FileProvider.getUriForFile(this, "$packageName.fileprovider", f))
                    mimes.add(m["mime"] as String)
                }
                ui.post {
                    try {
                        startShare(uris, mimes)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE", e.message, null)
                    }
                }
            } catch (e: Throwable) {
                ui.post { result.error("SHARE", e.message ?: "Share failed", null) }
            }
        }
    }

    private fun startShare(uris: List<Uri>, mimes: Set<String>) {
        val type = if (mimes.size == 1) mimes.first()
        else if (mimes.all { it.startsWith("image/") }) "image/*"
        else if (mimes.all { it.startsWith("video/") }) "video/*"
        else "*/*"
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                this.type = type
                putExtra(Intent.EXTRA_STREAM, uris[0])
                clipData = ClipData.newRawUri("", uris[0])
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                this.type = type
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                val cd = ClipData.newRawUri("", uris[0])
                for (k in 1 until uris.size) cd.addItem(ClipData.Item(uris[k]))
                clipData = cd
            }
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }
}
