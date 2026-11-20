package id.myra.myra_mobile

import android.app.Activity
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.widget.*

class MediaActivity : Activity() {
    private lateinit var player: VideoView
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val uri = Uri.parse(intent.getStringExtra("url") ?: return finish())
        if (uri.scheme != "https") return finish()
        player = VideoView(this)
        val layout = FrameLayout(this)
        layout.addView(player, FrameLayout.LayoutParams(-1,-2,Gravity.CENTER))
        val controls = MediaController(this)
        controls.setAnchorView(player)
        player.setMediaController(controls)
        player.setOnPreparedListener { player.start(); controls.show() }
        player.setOnErrorListener { _,_,_ ->
            Toast.makeText(this,"Media gagal diputar.",Toast.LENGTH_LONG).show()
            finish(); true
        }
        setContentView(layout)
        player.setVideoURI(uri)
    }
    override fun onStop() { if (::player.isInitialized) player.pause(); super.onStop() }
    override fun onDestroy() { if (::player.isInitialized) player.stopPlayback(); super.onDestroy() }
}
