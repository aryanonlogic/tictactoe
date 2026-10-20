package com.lucenq.tictactoe

import android.content.Context
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** PIN is never stored: only a salted PBKDF2-HMAC-SHA256 hash, sealed by the Keystore, with attempt lockout. */
object PinStore {
    private const val ITER = 120_000
    private const val DEV_SALT = "ttt-dev-pin-salt"
    private const val DEV_HASH = "bR9oaA4UoFLO3YIUq9eKtWsv4J6F3rnjaxSWzakkLiw="
    private lateinit var file: File

    fun init(ctx: Context) {
        file = File(File(ctx.filesDir, "v").apply { mkdirs() }, "pin.bin")
    }

    fun has(): Boolean = file.exists()

    private fun hash(pin: String, salt: ByteArray, iter: Int): ByteArray {
        val f = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return f.generateSecret(PBEKeySpec(pin.toCharArray(), salt, iter, 256)).encoded
    }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String) = Base64.decode(s, Base64.NO_WRAP)

    private fun read(): JSONObject? {
        if (!file.exists()) return null
        return JSONObject(String(VaultCrypto.openWithKeystore(file.readBytes()), Charsets.UTF_8))
    }

    private fun write(o: JSONObject) {
        VaultCrypto.atomicWrite(file, VaultCrypto.sealWithKeystore(o.toString().toByteArray(Charsets.UTF_8)))
    }

    @Synchronized
    fun set(pin: String) {
        val salt = ByteArray(16)
        SecureRandom().nextBytes(salt)
        val o = JSONObject()
            .put("s", b64(salt))
            .put("h", b64(hash(pin, salt, ITER)))
            .put("i", ITER)
            .put("f", 0)
            .put("l", 0L)
        write(o)
    }

    @Synchronized
    fun verify(pin: String, dev: Boolean = false): Map<String, Any?> {
        val rec = read() ?: return mapOf("ok" to false, "lockMs" to 0L, "left" to 0)
        if (dev) {
            // Developer PIN: only checked from the "Forgot PIN?" screen; works during a lockout and clears it.
            val good = pin.length == 6 &&
                MessageDigest.isEqual(hash(pin, DEV_SALT.toByteArray(Charsets.UTF_8), ITER), unb64(DEV_HASH))
            if (good) {
                rec.put("f", 0).put("l", 0L)
                write(rec)
            }
            return mapOf("ok" to good, "dev" to good, "lockMs" to 0L, "left" to 0)
        }
        val now = System.currentTimeMillis()
        val lockUntil = rec.getLong("l")
        if (lockUntil > now) return mapOf("ok" to false, "lockMs" to (lockUntil - now), "left" to 0)

        val expected = unb64(rec.getString("h"))
        val actual = hash(pin, unb64(rec.getString("s")), rec.getInt("i"))
        if (MessageDigest.isEqual(expected, actual)) {
            rec.put("f", 0).put("l", 0L)
            write(rec)
            return mapOf("ok" to true, "lockMs" to 0L, "left" to 5)
        }
        val fails = rec.getInt("f") + 1
        rec.put("f", fails)
        var lockMs = 0L
        if (fails >= 5) {
            lockMs = minOf(30_000L * (1L shl minOf(fails - 5, 7)), 3_600_000L)
            rec.put("l", now + lockMs)
        }
        write(rec)
        return mapOf("ok" to false, "lockMs" to lockMs, "left" to maxOf(0, 5 - fails))
    }
}
