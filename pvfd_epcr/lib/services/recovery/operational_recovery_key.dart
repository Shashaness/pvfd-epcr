import 'dart:convert';

import 'recovery_encryption_service.dart';

/// District public key only. Provisioned explicitly; no startup/backup activation.
/// ID is SHA-256 of canonical DER SubjectPublicKeyInfo, pinned at provisioning.
const operationalRecoveryKeyId =
    '23c0301fc9fbf5898b1354484203b928c197ed95d843411fa6e3f3acc1dd88dd';
const _operationalSpkiBase64 =
    'MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAusjrMRjlJRgpkUgRmxO4pyLKk5vYH5X4urH1d2m7EYm1JcNBRApOyvBlQI4Uap8lupYMBOhi/WfVpbQWA54oPWTdzuf30JSygS7V8EEHOBQs4oGSo7P2Rio+Sa3XYb2DSH7U2CGxDjvGsWVsUQ3tVGgvgpHmHEiOrgp9MgwrOs1gk8oBRx1b3LOTvplT4uFnQiwLa4CF69d5Hht04goXOIy/uVEDGhNpp8uPWlCA8mUsxyB4y8TuafDJm5fTb2/fUtdvIGKhzOS1+9yRIuHKB5F3XNiawR6eG+mF2bHND59qW8yJKUHbzXlMhTNUzeGfyHOw5mgK8MMBLHifWTaFjPrAX6/fqT0Cqqmq1ALUbpDtSk/SkPTPcuzdcS0cVV8c6o3q+oLz9hgmf9bRY1MsBN92AziOys5zHq8BAoCwp1JFGuZCUNJMR51kLkv/AbM8fSaTHoGC+upb0qxJXheUO2nrlNhpwOPUlxvaD04T765lVzHHja/5TXma9CGRSUIlAgMBAAE=';

/// Native loading verifies RSA parameters and fingerprint. Never substitutes a
/// development key or generates a replacement on failure.
Future<PublicRecoveryKey> loadOperationalRecoveryKey(
  RecoveryEncryptionService service,
) => service.loadPublicKey(
  base64Decode(_operationalSpkiBase64),
  operationalRecoveryKeyId,
);
