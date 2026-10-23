package com.pvfd3.pvfd_epcr

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val provider = KeystoreEncryption(applicationContext)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.pvfd3.pvfd_epcr/encryption", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            try {
                val id = call.argument<String>("keyId") ?: throw CryptoFailure("invalidKeyId")
                fun bytes(name: String) = call.argument<ByteArray>(name) ?: throw CryptoFailure("malformedEnvelope")
                val value = when (call.method) {
                    "createKey" -> provider.create(id)
                    "lookupKey" -> provider.lookup(id)
                    "encrypt" -> provider.encrypt(id, bytes("bytes"), bytes("aad"))
                    "decrypt" -> provider.decrypt(id, bytes("ciphertext"), bytes("nonce"), bytes("tag"), bytes("aad"))
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(value)
            } catch (e: CryptoFailure) {
                result.error(e.code, "Encryption operation failed", null)
            } catch (_: Exception) {
                result.error("cryptoFailure", "Encryption operation failed", null)
            }
        }
    }
}
