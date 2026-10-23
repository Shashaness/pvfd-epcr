package com.pvfd3.pvfd_epcr

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.interfaces.RSAPublicKey
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/** Portable public-key encryption only. No Keystore, filesystem, network or key provisioning. */
class RecoveryEncryption {
    companion object {
        const val MAX_PAYLOAD = 16 * 1024 * 1024
        const val HEADER_LENGTH = 480
        private val MAGIC = "PVFDBAK1".toByteArray(StandardCharsets.US_ASCII)
        private val DOMAIN = "PVFD/ePCR/recovery-backup/v1\u0000".toByteArray(StandardCharsets.US_ASCII)
        private val KEY_ID = Regex("^[0-9a-f]{64}$")
    }

    private fun publicKey(der: ByteArray, expectedId: String): RSAPublicKey {
        if (!KEY_ID.matches(expectedId)) throw CryptoFailure("invalidKeyId")
        if (der.isEmpty() || der.size > 1024) throw CryptoFailure("invalidPublicKey")
        val key = try {
            KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(der)) as? RSAPublicKey
                ?: throw CryptoFailure("invalidPublicKey")
        } catch (_: Exception) { throw CryptoFailure("invalidPublicKey") }
        if (key.modulus.bitLength() != 3072 || key.publicExponent != BigInteger.valueOf(65537) ||
            key.modulus.signum() != 1 || !key.encoded.contentEquals(der)) throw CryptoFailure("invalidPublicKey")
        val digest = MessageDigest.getInstance("SHA-256").digest(key.encoded)
        val actual = digest.joinToString("") { "%02x".format(it.toInt() and 255) }
        if (!MessageDigest.isEqual(actual.toByteArray(StandardCharsets.US_ASCII),
                expectedId.toByteArray(StandardCharsets.US_ASCII))) throw CryptoFailure("keyIdMismatch")
        return key
    }

    fun validate(der: ByteArray, expectedId: String): Map<String, Any> {
        try {
            publicKey(der, expectedId)
            return mapOf("keyId" to expectedId)
        } catch (e: CryptoFailure) { throw e }
        catch (_: Exception) { throw CryptoFailure("cryptoFailure") }
    }

    fun encrypt(plaintext: ByteArray, der: ByteArray, expectedId: String): ByteArray {
        if (plaintext.size > MAX_PAYLOAD) throw CryptoFailure("payloadTooLarge")
        val dek = ByteArray(32)
        try {
            val publicKey = publicKey(der, expectedId)
            val nonce = ByteArray(12)
            val random = try {
                SecureRandom().also { it.nextBytes(dek); it.nextBytes(nonce) }
            } catch (_: Exception) { throw CryptoFailure("randomFailure") }
            val rsa = Cipher.getInstance("RSA/ECB/OAEPPadding") // RSA name; no AES-ECB.
            rsa.init(Cipher.ENCRYPT_MODE, publicKey,
                OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, PSource.PSpecified.DEFAULT), random)
            val wrapped = rsa.doFinal(dek)
            if (wrapped.size != 384) throw CryptoFailure("cryptoFailure")
            val header = ByteBuffer.allocate(HEADER_LENGTH)
                .put(MAGIC).put(1.toByte()).put(1.toByte()).putShort(64.toShort()).putShort(384.toShort())
                .put(12.toByte()).put(16.toByte()).putInt(plaintext.size)
                .put(expectedId.toByteArray(StandardCharsets.US_ASCII)).put(wrapped).put(nonce).array()
            val aes = Cipher.getInstance("AES/GCM/NoPadding")
            aes.init(Cipher.ENCRYPT_MODE, SecretKeySpec(dek, "AES"), GCMParameterSpec(128, nonce), random)
            aes.updateAAD(DOMAIN + header)
            val sealed = aes.doFinal(plaintext)
            if (sealed.size != plaintext.size + 16) throw CryptoFailure("cryptoFailure")
            return header + sealed
        } catch (e: CryptoFailure) { throw e }
        catch (_: Exception) { throw CryptoFailure("cryptoFailure") }
        finally { dek.fill(0) } // Best effort; JVM/provider copies cannot be guaranteed zeroized.
    }
}
