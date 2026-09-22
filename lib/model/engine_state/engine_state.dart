/// Confirmed / transient engine immobilizer state per device.
enum EngineState {
  /// Relay reported unblocked / engine allowed.
  on,

  /// Relay reported blocked / engine cut.
  off,

  /// Command sent; waiting for device confirmation.
  pending,

  /// Timed out or device went offline before confirmation.
  unconfirmed,

  /// Device returned a non-OK result for a pending command.
  commandFailed,

  /// No confirmed state yet.
  unknown,
}
