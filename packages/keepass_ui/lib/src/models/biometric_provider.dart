abstract class BiometricProvider {
  Future<void> enroll();

  Future<bool> authenticate({
    String localizedReason = 'Unlock ManyKee',
  });

  Future<void> revoke();
}

class NoBiometricProvider implements BiometricProvider {
  const NoBiometricProvider();

  @override
  Future<void> enroll() async {}

  @override
  Future<bool> authenticate({
    String localizedReason = 'Unlock ManyKee',
  }) async =>
      false;

  @override
  Future<void> revoke() async {}
}
