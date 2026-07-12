import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _securityScopedFilesChannelName =
    'com.manykee.native/security_scoped_files';

final securityScopedFileAccessProvider = Provider<SecurityScopedFileAccess>((
  ref,
) {
  final access = SecurityScopedFileAccess();
  ref.onDispose(() {
    unawaited(access.releaseAll());
  });
  return access;
});

class SecurityScopedFileAccess {
  SecurityScopedFileAccess({
    MethodChannel channel = const MethodChannel(
      _securityScopedFilesChannelName,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Set<String> _activeTokens = <String>{};
  final Map<String, String> _tokenOwners = <String, String>{};

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<String?> bookmarkForPath(String path) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>(
        'bookmarkForPath',
        <String, Object?>{'path': path},
      );
    } on PlatformException {
      return null;
    }
  }

  Future<SecurityScopedAccess?> startFromBookmark(String? bookmark) async {
    if (!isSupported || bookmark == null || bookmark.isEmpty) return null;
    final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>(
        'startAccessingBookmark',
        <String, Object?>{'bookmark': bookmark},
      );
    } on PlatformException {
      return null;
    }
    if (result == null) return null;

    final token = result['token'] as String?;
    final path = result['path'] as String?;
    if (token == null || token.isEmpty || path == null || path.isEmpty) {
      return null;
    }
    _activeTokens.add(token);

    return SecurityScopedAccess._(
      controller: this,
      token: token,
      path: path,
      stale: result['stale'] == true,
    );
  }

  void retain(SecurityScopedAccess access, {required String owner}) {
    if (!_activeTokens.contains(access.token)) return;
    _tokenOwners[access.token] = owner;
  }

  Future<void> stop(String token) async {
    if (!_activeTokens.remove(token)) return;
    _tokenOwners.remove(token);
    if (!isSupported || token.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('stopAccessing', <String, Object?>{
        'token': token,
      });
    } on PlatformException {
      // Stopping access is best-effort cleanup; the OS will tear down any
      // remaining access when the process exits.
    }
  }

  Future<void> releaseOwner(String owner) async {
    final tokens = _tokenOwners.entries
        .where((entry) => entry.value == owner)
        .map((entry) => entry.key)
        .toList();
    await Future.wait(tokens.map(stop));
  }

  Future<void> releaseAll() async {
    final tokens = _activeTokens.toList();
    await Future.wait(tokens.map(stop));
  }
}

class SecurityScopedAccess {
  SecurityScopedAccess._({
    required this.controller,
    required this.token,
    required this.path,
    required this.stale,
  });

  final SecurityScopedFileAccess controller;
  final String token;
  final String path;
  final bool stale;
  bool _stopped = false;

  void retain({required String owner}) => controller.retain(this, owner: owner);

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await controller.stop(token);
  }
}
