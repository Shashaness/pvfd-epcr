package com.pvfd3.pvfd_epcr

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import android.os.Process
import java.io.File
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Test APK only. Headless; never starts Flutter or opens existing record files. */
class CryptoSelfTestInstrumentation : Instrumentation() {
    private lateinit var args: Bundle
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        args = arguments ?: Bundle()
        start()
    }
    private fun requireTest(value: Boolean) {
        if (!value) throw CryptoFailure("selfTestAssertion")
    }
    private fun expectFailure(code: String, action: () -> Unit) {
        try { action() } catch (e: CryptoFailure) { requireTest(e.code == code); return }
        throw CryptoFailure("selfTestAssertion")
    }
    override fun onStart() {
        val result = Bundle()
        try {
            val id = args.getString("keyId") ?: throw CryptoFailure("invalidKeyId")
            requireTest(Regex("^m41_test_[a-f0-9]{32}$").matches(id))
            val provider = KeystoreEncryption(targetContext)
            val fixture = File(targetContext.cacheDir, "$id.synthetic_envelope")
            val header = "PVFD/ePCR/synthetic-selftest/v1".toByteArray(Charsets.US_ASCII)
            val plaintext = "SYNTHETIC cryptographic self-test Δ 🩺".toByteArray(Charsets.UTF_8)
            when (args.getString("mode")) {
                "prepare" -> {
                    requireTest(!fixture.exists())
                    expectFailure("keyMissing") { provider.lookup(id) }
                    val info = provider.create(id)
                    requireTest(info == provider.lookup(id))
                    expectFailure("keyAlreadyExists") { provider.create(id) }
                    val box = provider.encrypt(id, plaintext, header)
                    val nonce = box["nonce"] as ByteArray
                    val ct = box["ciphertext"] as ByteArray
                    val tag = box["tag"] as ByteArray
                    requireTest((provider.decrypt(id, ct, nonce, tag, header)["bytes"] as ByteArray).contentEquals(plaintext))
                    val next = provider.encrypt(id, plaintext, header)
                    requireTest(!nonce.contentEquals(next["nonce"] as ByteArray))
                    for (part in listOf("nonce", "ciphertext", "tag", "aad")) {
                        val n = nonce.clone(); val c = ct.clone(); val t = tag.clone(); val a = header.clone()
                        val changed = when (part) { "nonce" -> n; "ciphertext" -> c; "tag" -> t; else -> a }
                        changed[0] = (changed[0].toInt() xor 1).toByte()
                        expectFailure("authenticationFailed") { provider.decrypt(id, c, n, t, a) }
                    }
                    for (input in listOf(ByteArray(0), ByteArray(1024 * 1024) { (it % 256).toByte() })) {
                        val b = provider.encrypt(id, input, header)
                        requireTest((provider.decrypt(id, b["ciphertext"] as ByteArray, b["nonce"] as ByteArray,
                            b["tag"] as ByteArray, header)["bytes"] as ByteArray).contentEquals(input))
                    }
                    nistVector()
                    ledgerCollision(id, nonce)
                    // ONLY ciphertext, tag, nonce and process ID persisted; no plaintext or key bytes.
                    fixture.outputStream().use { out ->
                        out.write(ByteBuffer.allocate(4).putInt(Process.myPid()).array())
                        out.write(nonce); out.write(ct); out.write(tag); out.fd.sync()
                    }
                    result.putString("protection", info["protection"] as String)
                    result.putString("result", "PASS: create/retrieve/roundtrip/tampering/nonces/large/empty/NIST; restart pending")
                }
                "verify" -> {
                    val saved = fixture.readBytes()
                    requireTest(saved.size == 4 + 12 + plaintext.size + 16)
                    val priorPid = ByteBuffer.wrap(saved, 0, 4).int
                    requireTest(priorPid != Process.myPid())
                    val nonce = saved.copyOfRange(4, 16)
                    val ct = saved.copyOfRange(16, saved.size - 16)
                    val tag = saved.copyOfRange(saved.size - 16, saved.size)
                    val info = provider.lookup(id)
                    requireTest((provider.decrypt(id, ct, nonce, tag, header)["bytes"] as ByteArray).contentEquals(plaintext))
                    val fresh = provider.encrypt(id, plaintext, header)
                    requireTest(!nonce.contentEquals(fresh["nonce"] as ByteArray))
                    val wrongId = id.replace("m41_test_", "m41_other_")
                    provider.create(wrongId)
                    expectFailure("authenticationFailed") { provider.decrypt(wrongId, ct, nonce, tag, header) }
                    // Tamper only our synthetic ledger entry to prove missing state is fail-closed.
                    targetContext.openOrCreateDatabase("epcr_crypto_nonce_v1.db", 0, null).use { db ->
                        db.delete("key_ids", "id = ?", arrayOf(wrongId))
                    }
                    expectFailure("keyUnavailable") { provider.lookup(wrongId) }
                    expectFailure("keyAlreadyExists") { provider.create(wrongId) }
                    // Clean up only this run's synthetic aliases, fixture and ledger rows.
                    val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    for (testId in listOf(id, wrongId)) {
                        ks.deleteEntry("pvfd.epcr.aes.v1.$testId")
                        targetContext.openOrCreateDatabase("epcr_crypto_nonce_v1.db", 0, null).use { db ->
                            db.delete("nonces", "id = ?", arrayOf(testId))
                            db.delete("key_ids", "id = ?", arrayOf(testId))
                        }
                    }
                    requireTest(fixture.delete())
                    result.putString("protection", info["protection"] as String)
                    result.putString("result", "PASS: distinct process/key retrieval/decrypt/fresh nonce/wrong key/missing ledger; synthetic artifacts removed")
                }
                else -> throw CryptoFailure("invalidTestMode")
            }
            finish(Activity.RESULT_OK, result)
        } catch (e: Exception) {
            result.putString("result", "FAIL: " + if (e is CryptoFailure) e.code else "selfTestFailure")
            finish(Activity.RESULT_CANCELED, result) // No exception messages, keys or payloads.
        }
    }
    private fun nistVector() {
        fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        // NIST CAVP gcmEncryptExtIV256.rsp, PTlen=0/AADlen=0/Taglen=128 Count=0.
        val key = hex("b52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4")
        val nonce = hex("516c33929df5a3284ff463d7")
        val tag = hex("bdc1ac884d332457a1d2664f168c76f0")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        requireTest(cipher.doFinal(ByteArray(0)).contentEquals(tag))
        val otherKey = SecretKeySpec(hex("92e11dcdaa866f5ce790fd24501f92509aacf4cb8b1339d50c9c1240935dd08b"), "AES")
        val iv = hex("ac93a1a6145299bde902f21a")
        val plaintext = hex("2d71bcfa914e4ac045b2aa60955fad24")
        val aad = hex("1e0889016f67601c8ebea4943bc23ad6")
        val expected = hex("8995ae2e6df3dbf96fac7b7137bae67feca5aa77d51d4a0a14d9c51e1da474ab")
        cipher.init(Cipher.ENCRYPT_MODE, otherKey, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        requireTest(cipher.doFinal(plaintext).contentEquals(expected))
        cipher.init(Cipher.DECRYPT_MODE, otherKey, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        requireTest(cipher.doFinal(expected).contentEquals(plaintext))
    }
    private fun ledgerCollision(id: String, nonce: ByteArray) {
        // Test-only reflection exercises the actual durable collision guard without
        // adding any production random/nonce injection or public testing API.
        val cls = KeystoreEncryption::class.java.declaredClasses.first { it.simpleName == "NonceLedger" }
        val constructor = cls.getDeclaredConstructor(android.content.Context::class.java).apply { isAccessible = true }
        val helper = constructor.newInstance(targetContext) as android.database.sqlite.SQLiteOpenHelper
        try {
            val reserve = cls.getDeclaredMethod("reserve", String::class.java, ByteArray::class.java).apply { isAccessible = true }
            expectFailure("nonceReuse") {
                try { reserve.invoke(helper, id, nonce) }
                catch (e: java.lang.reflect.InvocationTargetException) { throw e.cause ?: e }
            }
        } finally { helper.close() }
    }

}
