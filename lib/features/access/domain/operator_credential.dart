/// PIN typed by an operator, or a fingerprint the reader already accepted.
class OperatorCredential {
  const OperatorCredential.pin(this.pin) : fingerprintVerified = false;

  const OperatorCredential.fingerprint() : pin = '', fingerprintVerified = true;

  final String pin;
  final bool fingerprintVerified;
}
