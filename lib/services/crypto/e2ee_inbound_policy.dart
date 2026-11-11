/// Fail-closed policy for live private message delivery.
///
/// This only decides whether an incoming network packet may enter
/// the Signal decrypt path. It does not authenticate the packet.
/// Signal decryption and envelope identity checks must still succeed.
class E2eeInboundPolicy {
  const E2eeInboundPolicy();

  bool allowsNetworkMessage({required Object? e2eeMarker}) {
    return e2eeMarker == true;
  }
}