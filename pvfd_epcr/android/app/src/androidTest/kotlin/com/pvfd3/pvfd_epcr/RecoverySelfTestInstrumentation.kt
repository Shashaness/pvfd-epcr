package com.pvfd3.pvfd_epcr

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import java.io.File
import java.security.KeyStore

/** Synthetic public key in, encrypted test files out; no clinical storage access. */
class RecoverySelfTestInstrumentation : Instrumentation() {
    private lateinit var args: Bundle
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        args = arguments ?: Bundle()
        start()
    }
    override fun onStart() {
        val result = Bundle()
        var stage = "configuration"
        try {
            val run = args.getString("run") ?: throw CryptoFailure("invalidTestConfiguration")
            check(Regex("^m42a_test_[a-f0-9]{32}$").matches(run))
            val root = File(targetContext.cacheDir, run)
            stage = "readPublic"
            val der = File(root, "public.der").readBytes()
            val id = args.getString("keyId") ?: throw CryptoFailure("invalidTestConfiguration")
            val provider = RecoveryEncryption()
            stage = "publicSize"
            check(der.size == 422)
            stage = "publicParse"
            val parsed = java.security.KeyFactory.getInstance("RSA").generatePublic(java.security.spec.X509EncodedKeySpec(der)) as java.security.interfaces.RSAPublicKey
            stage = "publicParameters"
            check(parsed.modulus.bitLength() == 3072 && parsed.publicExponent == java.math.BigInteger.valueOf(65537))
            stage = "publicCanonical"
            check(parsed.encoded.contentEquals(der))
            stage = "validatePublic"
            check(provider.validate(der, id)["keyId"] == id)
            fun rejects(code: String, action: () -> Unit) {
                try { action() } catch (e: CryptoFailure) { check(e.code == code); return }
                throw CryptoFailure("selfTestAssertion")
            }
            stage = "rejectInvalidPublic"
            rejects("keyIdMismatch") { provider.validate(der, "0".repeat(64)) }
            rejects("invalidPublicKey") { provider.validate(byteArrayOf(1, 2), id) }
            rejects("invalidPublicKey") { provider.validate(der + byteArrayOf(0), id) }
            val samples = listOf(
                "{\"synthetic\":true,\"note\":\"TEST ONLY\"}".toByteArray(Charsets.UTF_8),
                ByteArray(0),
                "{\"synthetic\":true,\"note\":\"Δ 日本語 🩺\"}".toByteArray(Charsets.UTF_8),
                ByteArray(1024 * 1024) { (it % 256).toByte() },
                ByteArray(256) { it.toByte() }
            )
            stage = "encryptSamples"
            val boxes = samples.map { provider.encrypt(it, der, id) }
            val repeated = provider.encrypt(samples[0], der, id)
            check(!boxes[0].copyOfRange(468, 480).contentEquals(repeated.copyOfRange(468, 480)))
            check(!boxes[0].copyOfRange(84, 468).contentEquals(repeated.copyOfRange(84, 468)))
            // Simulate loss only of a fresh synthetic Keystore key, never existing keys.
            stage = "keystoreLoss"
            val alias = run
            KeystoreEncryption(targetContext).create(alias)
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            ks.deleteEntry("pvfd.epcr.aes.v1.$alias")
            rejects("keyMissing") { KeystoreEncryption(targetContext).lookup(alias) }
            val afterLoss = provider.encrypt(samples[0], der, id) // Recovery never consults Keystore.
            // Remove only our synthetic enrollment (no nonce was used).
            targetContext.openOrCreateDatabase("epcr_crypto_nonce_v1.db", 0, null).use {
                it.delete("key_ids", "id = ?", arrayOf(alias))
            }
            stage = "writeEnvelopes"
            (boxes + listOf(repeated, afterLoss)).forEachIndexed { index, bytes ->
                val output = File(root, "case_$index.pvfdbak")
                check(output.createNewFile())
                output.outputStream().use { it.write(bytes); it.fd.sync() }
            }
            result.putString("result", "PASS: RSA3072/SPKI/fingerprint/OAEP-SHA256-MGF1SHA256; 7 synthetic envelopes; isolated Keystore loss")
            finish(Activity.RESULT_OK, result)
        } catch (e: Exception) {
            result.putString("result", "FAIL: " + (if (e is CryptoFailure) e.code else "selfTestFailure") + ":" + stage)
            finish(Activity.RESULT_CANCELED, result)
        }
    }
}
