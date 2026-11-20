package id.myra.myra_mobile

import android.annotation.SuppressLint
import android.content.Context
import android.media.*
import android.os.Handler
import android.os.Looper
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class LiveAudio(context: Context, val onAudio: (ByteArray) -> Unit) {
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var oldMode = manager.mode
    private var oldSpeaker = manager.isSpeakerphoneOn
    @Volatile private var mic: AudioRecord? = null
    @Volatile private var track: AudioTrack? = null
    private val main = Handler(Looper.getMainLooper())
    private val playback = ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS,
        LinkedBlockingQueue<Runnable>(150), ThreadPoolExecutor.DiscardOldestPolicy())

    @SuppressLint("MissingPermission")
    fun start() {
        require(mic == null) { "Mikrofon sedang digunakan." }
        oldMode = manager.mode
        oldSpeaker = manager.isSpeakerphoneOn
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        speaker(true)
        try {
            val input = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION,16000,AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,maxOf(6400,AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)))
            mic = input
            check(input.state == AudioRecord.STATE_INITIALIZED) { "Mikrofon gagal dibuka." }
            val output = AudioTrack(AudioManager.STREAM_VOICE_CALL,24000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT,
                maxOf(12000,AudioTrack.getMinBufferSize(24000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT)),AudioTrack.MODE_STREAM)
            track = output
            output.play()
            input.startRecording()
            Thread {
                val buffer = ByteArray(1280)
                while (mic === input) {
                    val size = try { input.read(buffer,0,buffer.size) } catch (_: Exception) { break }
                    if (size <= 0) break
                    val chunk = buffer.copyOf(size)
                    main.post { if (mic === input) onAudio(chunk) }
                }
            }.start()
        } catch (e: Exception) { stop(); throw e }
    }
    fun play(bytes: ByteArray) {
        val current = track ?: return
        playback.execute { if (track === current) runCatching { current.write(bytes,0,bytes.size) } }
    }
    fun interrupt() {
        playback.queue.clear()
        track?.let { runCatching { it.pause(); it.flush(); it.play() } }
    }
    fun speaker(enabled: Boolean) { manager.isSpeakerphoneOn = enabled }
    fun stop() {
        if (mic == null && track == null && manager.mode != AudioManager.MODE_IN_COMMUNICATION) return
        val input = mic
        mic = null
        input?.let { runCatching { it.stop() }; it.release() }
        playback.queue.clear()
        val out = track
        track = null
        out?.let { runCatching { it.pause(); it.flush() }; it.release() }
        speaker(oldSpeaker)
        manager.mode = oldMode
    }
    fun destroy() { stop(); playback.shutdownNow() }
}
