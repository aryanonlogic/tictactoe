package com.lucenq.tictactoe

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.math.BigInteger
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Storage layout (app-private filesDir/v):
 *   mk.bin   random 256-bit master key, wrapped (AES-GCM) by a non-exportable Android Keystore key
 *   cfg.bin  settings JSON, sealed by the Keystore key
 *   idx.bin  vault index JSON (names, folders), AES-GCM with the master key
 *   <id>.b   media blob: 16-byte IV || AES-256-CTR ciphertext (seekable, so ExoPlayer can scrub)
 *   <id>.t   encrypted thumbnail, same format
 */
object VaultCrypto {
    private const val ALIAS = "ttt_vault_wrap_v1"
    private val rnd = SecureRandom()
    private lateinit var dir: File
    @Volatile private var mk: ByteArray? = null
    private val idRe = Regex("^[0-9a-f]{32}$")

    fun init(ctx: Context) {
        dir = File(ctx.filesDir, "v")
        dir.mkdirs()
    }

    fun newId(): String {
        val b = ByteArray(16)
        rnd.nextBytes(b)
        return b.joinToString("") { "%02x".format(it) }
    }

    fun blobFile(id: String): File {
        require(idRe.matches(id)) { "bad id" }
        return File(dir, "$id.b")
    }

    fun thumbFile(id: String): File {
        require(idRe.matches(id)) { "bad id" }
        return File(dir, "$id.t")
    }

    fun plainSize(f: File): Long = f.length() - 16

    // ---------- keys ----------
    private fun ksKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        kg.init(
            KeyGenParameterSpec.Builder(
                ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return kg.generateKey()
    }

    private fun sealKs(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, ksKey())
        return c.iv + c.doFinal(plain)
    }

    private fun openKs(blob: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, ksKey(), GCMParameterSpec(128, blob, 0, 12))
        return c.doFinal(blob, 12, blob.size - 12)
    }

    fun sealWithKeystore(plain: ByteArray): ByteArray = sealKs(plain)
    fun openWithKeystore(blob: ByteArray): ByteArray = openKs(blob)

    @Synchronized
    private fun master(): ByteArray {
        mk?.let { return it }
        val f = File(dir, "mk.bin")
        val k = if (f.exists()) {
            openKs(f.readBytes())
        } else {
            val fresh = ByteArray(32)
            rnd.nextBytes(fresh)
            atomicWrite(f, sealKs(fresh))
            fresh
        }
        mk = k
        return k
    }

    private fun sealMk(plain: ByteArray): ByteArray {
        val iv = ByteArray(12)
        rnd.nextBytes(iv)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(master(), "AES"), GCMParameterSpec(128, iv))
        return iv + c.doFinal(plain)
    }

    private fun openMk(blob: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, SecretKeySpec(master(), "AES"), GCMParameterSpec(128, blob, 0, 12))
        return c.doFinal(blob, 12, blob.size - 12)
    }

    // ---------- small files ----------
    fun atomicWrite(f: File, data: ByteArray) {
        val tmp = File(f.parentFile, f.name + ".tmp")
        FileOutputStream(tmp).use {
            it.write(data)
            it.fd.sync()
        }
        if (!tmp.renameTo(f)) {
            f.delete()
            if (!tmp.renameTo(f)) throw IOException("write failed")
        }
    }

    @Synchronized
    fun readSettings(): String? {
        val f = File(dir, "cfg.bin")
        return if (f.exists()) String(openKs(f.readBytes()), Charsets.UTF_8) else null
    }

    @Synchronized
    fun writeSettings(s: String) {
        atomicWrite(File(dir, "cfg.bin"), sealKs(s.toByteArray(Charsets.UTF_8)))
    }

    @Synchronized
    fun readIndex(): String? {
        val f = File(dir, "idx.bin")
        return if (f.exists()) String(openMk(f.readBytes()), Charsets.UTF_8) else null
    }

    @Synchronized
    fun writeIndex(s: String) {
        atomicWrite(File(dir, "idx.bin"), sealMk(s.toByteArray(Charsets.UTF_8)))
    }

    // ---------- blobs ----------
    /** Encrypts [input] into [out]; returns (sha256 hex of plaintext, plaintext size). */
    fun encryptStream(input: InputStream, out: File): Pair<String, Long> {
        val iv = ByteArray(16)
        rnd.nextBytes(iv)
        val cipher = Cipher.getInstance("AES/CTR/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(master(), "AES"), IvParameterSpec(iv))
        val md = MessageDigest.getInstance("SHA-256")
        var total = 0L
        FileOutputStream(out).use { fos ->
            fos.write(iv)
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
                cipher.update(buf, 0, n)?.let { fos.write(it) }
                total += n
            }
            cipher.doFinal()?.let { if (it.isNotEmpty()) fos.write(it) }
            fos.fd.sync()
        }
        return Pair(toHex(md.digest()), total)
    }

    private fun addToIv(iv: ByteArray, blocks: Long): ByteArray {
        val n = BigInteger(1, iv).add(BigInteger.valueOf(blocks)).mod(BigInteger.ONE.shiftLeft(128))
        val raw = n.toByteArray()
        val src = if (raw.size > 16) raw.copyOfRange(raw.size - 16, raw.size) else raw
        val out = ByteArray(16)
        System.arraycopy(src, 0, out, 16 - src.size, src.size)
        return out
    }

    /** Opens a decrypting stream positioned at plaintext offset [position]. */
    fun openDecrypted(f: File, position: Long = 0L): InputStream {
        val fis = FileInputStream(f)
        try {
            val iv = ByteArray(16)
            var read = 0
            while (read < 16) {
                val n = fis.read(iv, read, 16 - read)
                if (n < 0) throw IOException("truncated blob")
                read += n
            }
            val blocks = position / 16
            val rem = (position % 16).toInt()
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(master(), "AES"), IvParameterSpec(addToIv(iv, blocks)))
            if (rem > 0) cipher.update(ByteArray(rem))
            if (position > 0) fis.channel.position(16 + position)
            return CipherInputStream(fis, cipher)
        } catch (e: Throwable) {
            fis.close()
            throw e
        }
    }

    fun sha256(input: InputStream): String {
        val md = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(64 * 1024)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            md.update(buf, 0, n)
        }
        return toHex(md.digest())
    }

    fun hashBlob(f: File): String = openDecrypted(f).use { sha256(it) }

    fun writeThumb(id: String, bytes: ByteArray) {
        encryptStream(ByteArrayInputStream(bytes), thumbFile(id))
    }

    fun readThumb(id: String): ByteArray? {
        val f = thumbFile(id)
        return if (f.exists()) openDecrypted(f).use { it.readBytes() } else null
    }

    fun decryptTo(id: String, dest: File) {
        dest.parentFile?.mkdirs()
        openDecrypted(blobFile(id)).use { input ->
            FileOutputStream(dest).use { input.copyTo(it) }
        }
    }

    fun deleteBlobs(ids: List<String>) {
        for (id in ids) {
            blobFile(id).delete()
            thumbFile(id).delete()
        }
    }

    fun cleanupOrphans(valid: Set<String>) {
        dir.listFiles()?.forEach { f ->
            val n = f.name
            if (n.endsWith(".tmp")) {
                f.delete()
            } else if (n.endsWith(".b") || n.endsWith(".t")) {
                if (n.substringBeforeLast('.') !in valid) f.delete()
            }
        }
    }

    /** Removes all media + index. Keeps master key, settings and PIN. */
    fun wipeMedia() {
        dir.listFiles()?.forEach { f ->
            val n = f.name
            if (n.endsWith(".b") || n.endsWith(".t") || n == "idx.bin" || n.endsWith(".tmp")) f.delete()
        }
    }

    private fun toHex(b: ByteArray): String = b.joinToString("") { "%02x".format(it) }
}
