package com.lucenq.tictactoe

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.ByteArrayOutputStream
import java.io.InputStream

object MediaOps {

    // ---------------- import ----------------

    fun importAll(ctx: Context, uris: List<String>, known: List<String>): List<Map<String, Any?>> {
        val seen = HashSet(known)
        val out = ArrayList<Map<String, Any?>>()
        for (s in uris) out.add(importOne(ctx, s, seen))
        return out
    }

    private fun importOne(ctx: Context, s: String, seen: HashSet<String>): Map<String, Any?> {
        val uri = Uri.parse(s)
        val name = queryName(ctx, uri) ?: "file"
        fun fail(msg: String): Map<String, Any?> = mapOf("uri" to s, "name" to name, "ok" to false, "error" to msg)

        val cr = ctx.contentResolver
        val mime = cr.getType(uri) ?: guessMime(name)
        val isVideo = mime.startsWith("video/")
        val isImage = mime.startsWith("image/")
        if (!isVideo && !isImage) return fail("Unsupported file type")

        val id = VaultCrypto.newId()
        val blob = VaultCrypto.blobFile(id)
        try {
            val input = cr.openInputStream(uri) ?: return fail("Cannot open file")
            val (hash, size) = input.use { VaultCrypto.encryptStream(it, blob) }
            if (size <= 0L) {
                blob.delete()
                return fail("File is empty")
            }
            if (hash in seen) {
                blob.delete()
                return mapOf("uri" to s, "name" to name, "ok" to false, "dup" to true)
            }
            // Verify the private copy BEFORE reporting success: size and full decrypt+hash must match the source.
            if (VaultCrypto.plainSize(blob) != size || VaultCrypto.hashBlob(blob) != hash) {
                blob.delete()
                return fail("Verification of the private copy failed")
            }
            var dur = 0L
            try {
                val thumb = if (isVideo) videoThumb(ctx, uri) else photoThumb(ctx, uri)
                if (thumb != null) VaultCrypto.writeThumb(id, thumb)
                if (isVideo) dur = videoDuration(ctx, uri)
            } catch (e: Exception) {
                // thumbnail is optional
            }
            seen.add(hash)
            return mapOf(
                "uri" to s, "name" to name, "ok" to true, "id" to id, "mime" to mime,
                "type" to (if (isVideo) "video" else "photo"), "size" to size, "hash" to hash, "dur" to dur
            )
        } catch (e: Exception) {
            blob.delete()
            VaultCrypto.thumbFile(id).delete()
            return fail(e.message ?: "Import failed")
        }
    }

    fun queryName(ctx: Context, uri: Uri): String? {
        if (uri.scheme == "content") {
            try {
                ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (i >= 0) return c.getString(i)
                    }
                }
            } catch (e: Exception) {
            }
        }
        return uri.lastPathSegment
    }

    private fun guessMime(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    // ---------------- images ----------------

    fun decodeSampled(open: () -> InputStream, maxSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        open().use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bmp = open().use { BitmapFactory.decodeStream(it, null, opts) } ?: return null
        val orientation = try {
            open().use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }
        } catch (e: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
        }
        return if (m.isIdentity) bmp else Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }

    private fun jpeg(b: Bitmap, q: Int): ByteArray {
        val o = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.JPEG, q, o)
        return o.toByteArray()
    }

    private fun photoThumb(ctx: Context, uri: Uri): ByteArray? {
        val bmp = decodeSampled({ ctx.contentResolver.openInputStream(uri)!! }, 640) ?: return null
        return jpeg(ThumbnailUtils.extractThumbnail(bmp, 360, 360), 82)
    }

    private fun videoThumb(ctx: Context, uri: Uri): ByteArray? {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(ctx, uri)
            val frame = r.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: r.getFrameAtTime(0L) ?: return null
            return jpeg(ThumbnailUtils.extractThumbnail(frame, 360, 360), 82)
        } finally {
            r.release()
        }
    }

    private fun videoDuration(ctx: Context, uri: Uri): Long {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(ctx, uri)
            return r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } finally {
            r.release()
        }
    }

    /** Decrypts a vault photo, downsamples + applies EXIF rotation for on-screen display. */
    fun photoBytes(id: String, mime: String, maxSide: Int): ByteArray? {
        val f = VaultCrypto.blobFile(id)
        val bmp = decodeSampled({ VaultCrypto.openDecrypted(f) }, maxSide) ?: return null
        val o = ByteArrayOutputStream()
        val lossless = mime == "image/png" || mime == "image/webp" || mime == "image/gif"
        if (lossless) bmp.compress(Bitmap.CompressFormat.PNG, 100, o) else bmp.compress(Bitmap.CompressFormat.JPEG, 92, o)
        return o.toByteArray()
    }

    // ---------------- restore to the public gallery ----------------

    fun restore(ctx: Context, id: String, name: String, mime: String, hash: String): Boolean {
        val isVideo = mime.startsWith("video/")
        val collection = if (isVideo) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (isVideo) "Movies/Restored" else "Pictures/Restored")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val cr = ctx.contentResolver
        val uri = cr.insert(collection, values) ?: return false
        try {
            cr.openOutputStream(uri)!!.use { out ->
                VaultCrypto.openDecrypted(VaultCrypto.blobFile(id)).use { it.copyTo(out) }
            }
            // verify what actually landed in the gallery before the caller removes the vault copy
            val written = cr.openInputStream(uri)!!.use { VaultCrypto.sha256(it) }
            if (written != hash) {
                cr.delete(uri, null, null)
                return false
            }
            cr.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return true
        } catch (e: Exception) {
            try {
                cr.delete(uri, null, null)
            } catch (ignored: Exception) {
            }
            return false
        }
    }

    // ---------------- deleting originals ----------------

    /** Best-effort mapping of a picked/shared URI to a MediaStore URI that createDeleteRequest accepts. */
    fun toMediaStoreUri(ctx: Context, uri: Uri): Uri? {
        if (uri.scheme != "content") return null
        val auth = uri.authority ?: return null
        val segs = uri.pathSegments
        if (auth == "media") {
            if (segs.firstOrNull() == "picker") {
                // content://media/picker/<user>/com.android.providers.media.photopicker/media/<id>
                if (!uri.toString().contains("com.android.providers.media.photopicker")) return null
                val id = uri.lastPathSegment?.toLongOrNull() ?: return null
                val mime = ctx.contentResolver.getType(uri) ?: return null
                val base = if (mime.startsWith("video/")) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                return ContentUris.withAppendedId(base, id)
            }
            return uri // already a MediaStore uri
        }
        if (auth == "com.android.providers.media.documents") {
            val docId = DocumentsContract.getDocumentId(uri)
            val parts = docId.split(":")
            if (parts.size != 2) return null
            val id = parts[1].toLongOrNull() ?: return null
            return when (parts[0]) {
                "image" -> ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                "video" -> ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                else -> null
            }
        }
        return null
    }
}
