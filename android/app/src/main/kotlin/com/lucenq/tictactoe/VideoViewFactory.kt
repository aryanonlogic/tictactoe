package com.lucenq.tictactoe

import android.content.Context
import android.graphics.Color
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

@androidx.annotation.OptIn(UnstableApi::class)
class VideoViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        private val players = ArrayList<ExoPlayer>()
        fun pauseAll() {
            players.forEach { it.pause() }
        }
    }

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val ctx = context!!
        val id = (args as Map<*, *>)["id"] as String
        val exo = ExoPlayer.Builder(ctx).build()
        players.add(exo)

        val view = PlayerView(ctx)
        view.player = exo
        view.useController = true
        view.setShowNextButton(false)
        view.setShowPreviousButton(false)
        view.controllerShowTimeoutMs = 2500
        view.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        view.setBackgroundColor(Color.BLACK)
        view.setShutterBackgroundColor(Color.BLACK)

        val factory = DataSource.Factory { EncryptedDataSource() }
        val source = ProgressiveMediaSource.Factory(factory)
            .createMediaSource(MediaItem.fromUri("vault://$id"))
        exo.setMediaSource(source)
        exo.prepare()
        exo.playWhenReady = true

        return object : PlatformView {
            override fun getView(): View = view
            override fun dispose() {
                players.remove(exo)
                view.player = null
                exo.release()
            }
        }
    }
}
