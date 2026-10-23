package com.pvfd3.pvfd_epcr

import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.KeyStore
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/** No clinical/schema/file dependencies; never logs exception messages or inputs. */
class CryptoFailure(val code: String) : Exception(code)

class KeystoreEncryption(context: Context) {
    private val app = context.applicationContext
    // Lazy: merely opening the app does not create a DB, key, or encrypted file.
    private val ledger by lazy { NonceLedger(app) }
    private val store: KeyStore get() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    companion object {
        private val lock = Any()
        private const val PREFIX = "pvfd.epcr.aes.v1."
        private const val MAX_BYTES = 16 * 1024 * 1024
        private const val MAX_USES = 65536
        private val ID = Regex("^[A-Za-z0-9_-]{1,64}$")
    }

    private fun validate(id: String) {
        if (!ID.matches(id)) throw CryptoFailure("invalidKeyId")
    }

    private fun key(id: String): SecretKey {
        validate(id)
        val ks = store
        if (!ks.containsAlias(PREFIX + id)) throw CryptoFailure("keyMissing")
        val key = ks.getKey(PREFIX + id, null) as? SecretKey ?: throw CryptoFailure("keyUnavailable")
        if (!ledger.hasKey(id)) throw CryptoFailure("keyUnavailable")
        return key
    }

    private fun protection(key: SecretKey): String {
        val info = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        if (info.keySize != 256 || key.algorithm != "AES") throw CryptoFailure("keyUnavailable")
        return if (Build.VERSION.SDK_INT >= 31) {
            when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongBox"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "trustedEnvironment"
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
                else -> "unknown"
            }
        } else {
            @Suppress("DEPRECATION")
            if (info.isInsideSecureHardware) "hardwareBacked" else "software"
        }
    }

    private fun generate(id: String, strongBox: Boolean): SecretKey {
        val builder = KeyGenParameterSpec.Builder(PREFIX + id,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)
        if (Build.VERSION.SDK_INT >= 28) builder.setIsStrongBoxBacked(strongBox)
        return KeyGenerator.getInstance("AES", "AndroidKeyStore").apply { init(builder.build()) }.generateKey()
    }

    /** Explicit create only; never repair/reset a missing ledger or replace keys. */
    fun create(id: String): Map<String, Any> = synchronized(lock) {
        guarded {
            validate(id)
            if (store.containsAlias(PREFIX + id) || ledger.hasKey(id)) throw CryptoFailure("keyAlreadyExists")
            val strongBox = Build.VERSION.SDK_INT >= 28 &&
                app.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
            val key = if (strongBox) {
                try { generate(id, true) } catch (_: StrongBoxUnavailableException) {
                    // Fallback only for an unavailable optional security level, never for lost keys.
                    if (store.containsAlias(PREFIX + id)) throw CryptoFailure("keyUnavailable")
                    generate(id, false)
                }
            } else generate(id, false)
            val level = protection(key)
            ledger.addKey(id) // Failure leaves an inaccessible orphan, never an auto-replacement.
            mapOf("protection" to level)
        }
    }

    fun lookup(id: String): Map<String, Any> = synchronized(lock) {
        guarded { mapOf("protection" to protection(key(id))) }
    }

    fun usage(id: String): Map<String, Any> = synchronized(lock) {
        guarded { key(id); mapOf("used" to ledger.uses(id)) }
    }

    fun encrypt(id: String, plaintext: ByteArray, aad: ByteArray): Map<String, Any> = synchronized(lock) {
        guarded {
            bounded(plaintext, aad)
            val key = key(id)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            try { cipher.init(Cipher.ENCRYPT_MODE, key) } catch (_: ProviderException) {
                throw CryptoFailure("randomFailure")
            }
            val nonce = cipher.iv ?: throw CryptoFailure("randomFailure")
            if (nonce.size != 12 || (cipher.parameters.getParameterSpec(GCMParameterSpec::class.java)).tLen != 128)
                throw CryptoFailure("cryptoFailure")
            // Durable reservation BEFORE any ciphertext may be returned. Collision => no output.
            ledger.reserve(id, nonce)
            cipher.updateAAD(aad)
            val sealed = cipher.doFinal(plaintext)
            if (sealed.size != plaintext.size + 16) throw CryptoFailure("cryptoFailure")
            mapOf("nonce" to nonce, "ciphertext" to sealed.copyOfRange(0, sealed.size - 16),
                "tag" to sealed.copyOfRange(sealed.size - 16, sealed.size))
        }
    }

    fun decrypt(id: String, ciphertext: ByteArray, nonce: ByteArray, tag: ByteArray,
                aad: ByteArray): Map<String, Any> = synchronized(lock) {
        guarded {
            bounded(ciphertext, aad)
            if (nonce.size != 12 || tag.size != 16) throw CryptoFailure("malformedEnvelope")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(id), GCMParameterSpec(128, nonce))
            cipher.updateAAD(aad)
            // doFinal must authenticate before any plaintext is exposed to Dart.
            mapOf("bytes" to cipher.doFinal(ciphertext + tag))
        }
    }

    private fun bounded(bytes: ByteArray, aad: ByteArray) {
        if (bytes.size > MAX_BYTES || aad.size > MAX_BYTES + 128) throw CryptoFailure("payloadTooLarge")
    }

    private inline fun <T> guarded(block: () -> T): T {
        try { return block() }
        catch (e: CryptoFailure) { throw e }
        catch (_: KeyPermanentlyInvalidatedException) { throw CryptoFailure("keyInvalidated") }
        catch (_: AEADBadTagException) { throw CryptoFailure("authenticationFailed") }
        catch (_: UnrecoverableKeyException) { throw CryptoFailure("keyUnavailable") }
        catch (_: Exception) { throw CryptoFailure("keyUnavailable") }
    }

    /** Non-secret nonce uniqueness state; no keys, payloads, AAD or record paths. */
    private class NonceLedger(context: Context) : SQLiteOpenHelper(context, "epcr_crypto_nonce_v1.db", null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE key_ids (id TEXT PRIMARY KEY NOT NULL)")
            db.execSQL("CREATE TABLE nonces (id TEXT NOT NULL, nonce BLOB NOT NULL, PRIMARY KEY(id, nonce))")
        }
        override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
            throw CryptoFailure("keyUnavailable") // No destructive schema migrations.
        }
        fun hasKey(id: String): Boolean = readableDatabase.rawQuery(
            "SELECT 1 FROM key_ids WHERE id = ?", arrayOf(id)).use { it.moveToFirst() }
        fun uses(id: String): Int = readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM nonces WHERE id = ?", arrayOf(id)).use {
                it.moveToFirst(); it.getInt(0)
            }
        fun addKey(id: String) {
            writableDatabase.insertOrThrow("key_ids", null, ContentValues().apply { put("id", id) })
        }
        fun reserve(id: String, nonce: ByteArray) {
            val db = writableDatabase
            db.beginTransaction()
            try {
                if (!hasKey(id)) throw CryptoFailure("keyUnavailable")
                val count = db.rawQuery("SELECT COUNT(*) FROM nonces WHERE id = ?", arrayOf(id)).use {
                    it.moveToFirst(); it.getLong(0)
                }
                if (count >= MAX_USES) throw CryptoFailure("keyExhausted")
                val inserted = db.insertWithOnConflict("nonces", null, ContentValues().apply {
                    put("id", id); put("nonce", nonce)
                }, SQLiteDatabase.CONFLICT_IGNORE)
                if (inserted == -1L) throw CryptoFailure("nonceReuse")
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
        }
    }
}
