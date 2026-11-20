package id.myra.myra_mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var permissionResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var note: File? = null
    private var sink: EventChannel.EventSink? = null
    private val live by lazy { LiveAudio(this) { sink?.success(it) } }
    private var push: MethodChannel? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger
        EventChannel(messenger,"id.myra.mobile/pcm").setStreamHandler(object: EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(args: Any?) { sink = null }
        })
        MethodChannel(messenger,"id.myra.mobile/device").setMethodCallHandler { call, result ->
            safely(result) {
                when (call.method) {
                    "pick" -> {
                        check(pendingPick == null) { "Pemilih media sedang terbuka." }
                        val type = call.argument<String>("type")
                        val types = when (type) {
                            "image/*" -> arrayOf("image/*")
                            "visual" -> arrayOf("image/*","video/*")
                            else -> arrayOf("image/*","video/*","audio/*")
                        }
                        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            this.type = if (types.size == 1) types[0] else "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES,types)
                        }
                        startActivityForResult(picker,91)
                        pendingPick = result
                    }
                    "openMedia" -> {
                        val url = call.argument<String>("url") ?: error("Media kosong")
                        require(Uri.parse(url).scheme == "https") { "URL media harus HTTPS." }
                        startActivity(Intent(this, MediaActivity::class.java).putExtra("url",url))
                        result.success(null)
                    }
                    "startNote" -> permission(Manifest.permission.RECORD_AUDIO,result) {
                        check(recorder == null)
                        val file = File.createTempFile("myra-voice-", ".m4a", cacheDir)
                        val r = MediaRecorder()
                        try {
                            r.setAudioSource(MediaRecorder.AudioSource.MIC)
                            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            r.setAudioEncodingBitRate(64000)
                            r.setAudioSamplingRate(44100)
                            r.setOutputFile(file.absolutePath)
                            r.setMaxFileSize(50L * 1024 * 1024)
                            r.prepare(); r.start()
                            recorder = r; note = file; result.success(null)
                        } catch (e: Exception) { r.release(); file.delete(); throw e }
                    }
                    "stopNote" -> result.success(finishNote())
                    "liveStart" -> permission(Manifest.permission.RECORD_AUDIO,result) { live.start(); result.success(null) }
                    "liveEnd" -> { live.stop(); result.success(null) }
                    "playPcm" -> { live.play(call.arguments as ByteArray); result.success(null) }
                    "interrupt" -> { live.interrupt(); result.success(null) }
                    "speaker" -> { live.speaker(call.arguments == true); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
        push = MethodChannel(messenger,"id.myra.mobile/push").also { channel ->
            channel.setMethodCallHandler { call, result -> safely(result) {
                when (call.method) {
                    "initial" -> { val id = intent?.getStringExtra("notification_id"); intent?.removeExtra("notification_id"); result.success(id) }
                    "disable" -> {
                        if (FirebaseApp.getApps(this).isEmpty()) result.success(null)
                        else { val f = FirebaseMessaging.getInstance(); f.isAutoInitEnabled = false
                            f.deleteToken().addOnCompleteListener { if(it.isSuccessful) result.success(null) else result.error("push","Gagal menghapus token FCM.",null) }
                        }
                    }
                    "enable" -> {
                        check(FirebaseApp.getApps(this).isNotEmpty()) { "Firebase belum dikonfigurasi untuk APK ini." }
                        val enable: () -> Unit = {
                            val f = FirebaseMessaging.getInstance(); f.isAutoInitEnabled = true
                            f.token.addOnCompleteListener { if(it.isSuccessful) result.success(it.result) else result.error("push","Gagal mengambil token FCM.",null) }
                        }
                        if (Build.VERSION.SDK_INT >= 33) permission(Manifest.permission.POST_NOTIFICATIONS,result,enable) else enable()
                    }
                    else -> result.notImplemented()
                }
            } }
        }
    }
    private fun safely(result: MethodChannel.Result, block: () -> Unit) {
        try { block() } catch (e: Exception) { result.error("device",e.localizedMessage ?: "Operasi perangkat gagal.",null) }
    }
    private fun permission(name: String, result: MethodChannel.Result, action: () -> Unit) {
        if (checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED) { action(); return }
        check(permissionResult == null) { "Permintaan izin lain sedang berlangsung." }
        permissionAction = action; permissionResult = result
        requestPermissions(arrayOf(name),92)
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code,permissions,grants)
        if (code != 92) return
        val action = permissionAction; val result = permissionResult
        permissionAction = null; permissionResult = null
        if (action != null && result != null) {
            if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) safely(result,action)
            else result.error("permission","Izin perangkat belum diberikan.",null)
        }
    }
    override fun onActivityResult(code: Int, status: Int, data: Intent?) {
        super.onActivityResult(code,status,data)
        if (code != 91) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (status != Activity.RESULT_OK || uri == null) { result.success(null); return }
        Thread {
            try {
                val mime = contentResolver.getType(uri) ?: error("Format file tidak dikenali.")
                require(mime.startsWith("image/") || mime.startsWith("audio/") || mime.startsWith("video/"))
                var name = "media." + (MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin")
                contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE),null,null,null)?.use {
                    if (it.moveToFirst()) { if (!it.isNull(0)) name = it.getString(0); require(it.getLong(1) <= 52428800L) { "File melebihi 50 MB." } }
                }
                val target = File(cacheDir,"myra-media-" + UUID.randomUUID())
                try {
                    contentResolver.openInputStream(uri)!!.use { source -> target.outputStream().use { dest ->
                        val buf = ByteArray(65536); var total = 0L
                        while (true) { val n = source.read(buf); if (n < 0) break
                            total += n; require(total <= 52428800L) { "File melebihi 50 MB." }; dest.write(buf,0,n) }
                    } }
                    runOnUiThread { result.success(mapOf("path" to target.absolutePath,"name" to name.take(180),"mime" to mime)) }
                } catch (e: Exception) { target.delete(); throw e }
            } catch (e: Exception) { runOnUiThread { result.error("media",e.localizedMessage,null) } }
        }.start()
    }
    private fun finishNote(): Map<String,String>? {
        val r = recorder ?: return null
        val f = note ?: return null
        recorder = null; note = null
        try { r.stop() } catch (e: RuntimeException) { f.delete(); throw IllegalStateException("Rekaman terlalu singkat.",e) } finally { r.release() }
        return mapOf("path" to f.absolutePath,"name" to f.name,"mime" to "audio/mp4")
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        intent.getStringExtra("notification_id")?.let { push?.invokeMethod("notice",it) }
    }
    override fun onDestroy() {
        runCatching { finishNote() }; live.destroy(); push?.setMethodCallHandler(null)
        super.onDestroy()
    }
}
