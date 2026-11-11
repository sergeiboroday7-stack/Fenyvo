/// Mandatory end-to-end encryption delivery policy.
///
/// This class is deliberately independent of socket and platform services.
class E2eeDeliveryPolicy {
  const E2eeDeliveryPolicy();

  /// Private messages must never use a plaintext transport.
  bool requiresEncryption({
    required bool isPrivateMessage,
  }) {
    return isPrivateMessage;
  }

  /// A private message can be transmitted only after encryption succeeded.
  bool mayTransmit({
    required bool isPrivateMessage,
    required bool encryptionSucceeded,
  }) {
    if (!isPrivateMessage) {
      return true;
    }

    return encryptionSucceeded;
  }

  /// Legacy outbox messages without an E2EE marker still require encryption.
  bool mustEncryptOutboxMessage(Map<String, dynamic> message) {
    return true;
  }
}