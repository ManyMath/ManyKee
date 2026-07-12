/// A machine-readable error code plus a friendly message for the unlock UI.
///
/// [message] is always a single friendly sentence with no raw error text;
/// [detail] carries the (truncated) raw message for an optional muted
/// detail line under it.
typedef UnlockError = ({String code, String message, String? detail});

/// Truncates raw error text so a pathological message can't flood the UI.
String truncateErrorDetail(String rawMessage) =>
    rawMessage.length <= 300 ? rawMessage : '${rawMessage.substring(0, 300)}…';

/// Maps a raw `KeePassError` message onto a friendly unlock error.
///
/// Pure string matching, no keepass import, so it stays web-safe and unit
/// testable without the native library. Adapted from the reference Material
/// app (apps/native unlock_screen.dart).
UnlockError mapUnlockError(String rawMessage, {String? filePath}) {
  final message = rawMessage.toLowerCase();
  final detail = truncateErrorDetail(rawMessage);

  if (message.contains('failed to load native library') ||
      message.contains('native_worker') && message.contains('load')) {
    return (
      code: 'NATIVE_LIB_MISSING',
      message:
          'The KeePass engine could not be loaded. This is an app '
          'packaging problem, not an issue with your database file.',
      detail: detail,
    );
  }
  if (message.contains('yubikey') || message.contains('challenge')) {
    if (message.contains('disconnect') || message.contains('removed')) {
      return (
        code: 'YUBIKEY_DISCONNECTED',
        message: 'YubiKey was disconnected. Reconnect it and try again.',
        detail: detail,
      );
    }
    return (
      code: 'YUBIKEY_FAILED',
      message:
          'YubiKey communication failed. Make sure it is plugged in '
          '(touch it if it blinks) and try again.',
      detail: detail,
    );
  }
  if (message.contains('password') ||
      (message.contains('key') && !message.contains('key file')) ||
      message.contains('credentials') ||
      message.contains('unpad') ||
      message.contains('padding')) {
    return (
      code: 'WRONG_PASSWORD',
      message: 'Incorrect password. Please try again.',
      detail: detail,
    );
  }
  if (message.contains('no such file') ||
      message.contains('not found') ||
      message.contains('cannot open')) {
    return (
      code: 'FILE_NOT_FOUND',
      message: 'Could not find ${filePath ?? 'the selected file'}.',
      detail: detail,
    );
  }
  if (message.contains('permission') || message.contains('denied')) {
    return (
      code: 'PERMISSION_DENIED',
      message: 'Permission denied. Check file permissions and try again.',
      detail: detail,
    );
  }
  if (message.contains('locked') || message.contains('in use')) {
    return (
      code: 'FILE_LOCKED',
      message:
          'File is locked by another process. Close other applications '
          'using this file and try again.',
      detail: detail,
    );
  }
  if (message.contains('header') || message.contains('corrupt')) {
    return (
      code: 'CORRUPT_HEADER',
      message: 'Database header is corrupted. The file may be damaged.',
      detail: detail,
    );
  }
  if (message.contains('kdbx') &&
      (message.contains('version') ||
          message.contains('format') ||
          message.contains('not a'))) {
    return (
      code: 'NOT_KDBX4',
      message:
          'This is not a KDBX 4.x database. ManyKee requires KDBX 4 format.',
      detail: detail,
    );
  }
  return (
    code: 'PARSE_ERROR',
    message: 'Failed to open the database.',
    detail: detail,
  );
}
