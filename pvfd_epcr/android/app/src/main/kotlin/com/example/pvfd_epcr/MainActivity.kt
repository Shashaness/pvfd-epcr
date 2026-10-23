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
                    "keyUsage" -> provider.usage(id)
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
        val recovery = RecoveryEncryption()
        MethodChannel(messenger, "com.pvfd3.pvfd_epcr/recovery", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            try {
                val der = call.argument<ByteArray>("publicKeyDer") ?: throw CryptoFailure("invalidPublicKey")
                val id = call.argument<String>("keyId") ?: throw CryptoFailure("invalidKeyId")
                when (call.method) {
                    "validatePublicKey" -> result.success(recovery.validate(der, id))
                    "encryptForRecovery" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: throw CryptoFailure("malformedEnvelope")
                        result.success(recovery.encrypt(bytes, der, id))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: CryptoFailure) {
                result.error(e.code, "Recovery operation failed", null)
            } catch (_: Exception) {
                result.error("cryptoFailure", "Recovery operation failed", null)
            }
        }
        MethodChannel(messenger, "com.pvfd3.pvfd_epcr/durability", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            try {
                if (call.method != "syncDirectory") { result.notImplemented(); return@setMethodCallHandler }
                val path = call.argument<String>("path") ?: throw IllegalArgumentException()
                val file = java.io.File(path)
                val allowed = java.io.File(applicationInfo.dataDir).canonicalPath + "/"
                if (!file.canonicalPath.startsWith(allowed) || !file.isDirectory) throw IllegalArgumentException()
                android.system.Os.chmod(file.path, 448) // 0700, app-private store only.
                val fd = android.system.Os.open(file.path, android.system.OsConstants.O_RDONLY or android.system.OsConstants.O_NOFOLLOW, 0)
                try {
                    if (!android.system.OsConstants.S_ISDIR(android.system.Os.fstat(fd).st_mode)) throw IllegalArgumentException()
                    android.system.Os.fsync(fd)
                } finally { android.system.Os.close(fd) }
                result.success(null)
            } catch (_: Exception) { result.error("directorySyncFailed", "Protected storage unavailable", null) }
        }

    }
}
