package com.lucenq.tictactoe

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import java.io.IOException
import java.io.InputStream

/** Lets ExoPlayer stream and seek a vault blob (vault://<id>) by decrypting on the fly. Nothing is written to disk. */
@androidx.annotation.OptIn(UnstableApi::class)
class EncryptedDataSource : BaseDataSource(false) {
    private var stream: InputStream? = null
    private var currentUri: Uri? = null
    private var remaining = 0L
    private var opened = false

    override fun open(dataSpec: DataSpec): Long {
        currentUri = dataSpec.uri
        transferInitializing(dataSpec)
        val id = dataSpec.uri.host ?: throw IOException("bad vault uri")
        val f = VaultCrypto.blobFile(id)
        val total = VaultCrypto.plainSize(f)
        if (dataSpec.position > total) throw IOException("position out of range")
        stream = VaultCrypto.openDecrypted(f, dataSpec.position)
        val available = total - dataSpec.position
        remaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) minOf(dataSpec.length, available) else available
        opened = true
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        val toRead = if (remaining < length) remaining.toInt() else length
        val n = stream!!.read(buffer, offset, toRead)
        if (n == -1) return C.RESULT_END_OF_INPUT
        remaining -= n
        bytesTransferred(n)
        return n
    }

    override fun getUri(): Uri? = currentUri

    override fun close() {
        try {
            stream?.close()
        } finally {
            stream = null
            if (opened) {
                opened = false
                transferEnded()
            }
        }
    }
}
