/// AuthService — on-device session + security basics (Phase 6f).
///
/// Owns:
///   • the **stable device id** (generated once, persisted in
///     `flutter_secure_storage`, with a Hive/in-memory fallback) — the bucket
///     seed for the runtime plane + the key for analytics/sync/favorites,
///   • **secure token storage** (access + refresh) in the keychain /
///     EncryptedSharedPrefs, mirrored onto [ApiClient.authToken],
///   • a **token-refresh-on-401** seam (calls the refresh endpoint when set),
///   • optional **biometric unlock** via `local_auth`, gated by
///     `config.session.biometric` from the runtime envelope.
///
/// **Graceful degradation everywhere.** This reference ships ANONYMOUS — there
/// is no login screen wired — so by default there is no token and `uid` is
/// null; every method is a safe no-op in that state. Secure storage failures
/// fall back to a cached value or in-memory, never a crash. Biometrics fall
/// back to "allowed" when the device has none enrolled or `local_auth` errors.
///
/// **6g will build on the hooks left here:** real OAuth/OIDC login, API request
/// signing + cert pinning (the [ApiSecurityHooks] passed to [ApiClient]), and
/// integrity / root-jailbreak checks. This file deliberately leaves the
/// token-refresh callback + the biometric gate as the seams those plug into.
library;

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../api_client.dart';
import '../storage/cache_service.dart';

class AuthService {
  AuthService({required this.api, required this.cache, FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final ApiClient api;
  final CacheService cache;
  final FlutterSecureStorage _secure;
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const _kDeviceId = 'cms.deviceId';
  static const _kAccessToken = 'cms.accessToken';
  static const _kRefreshToken = 'cms.refreshToken';
  static const _kUid = 'cms.uid';
  static const _kRole = 'cms.role';

  String? _deviceId;
  String? _accessToken;
  String? _refreshToken;
  String? _uid;
  String? _role;
  bool _unlocked = false;

  String? get uid => _uid;
  String? get role => _role;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  /// 6g supplies this: given the stored refresh token, return a fresh
  /// `{ accessToken, refreshToken? }` (or null on failure). Left null here, so
  /// a 401 simply clears the session (anonymous) rather than looping.
  Future<Map<String, String>?> Function(String refreshToken)? refreshCallback;

  // ── device id ───────────────────────────────────────────────────────────────

  /// The stable per-install id. Reads secure storage (then the Hive cache),
  /// generating + persisting a new one on first run. Never throws.
  Future<String> ensureDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    // Secure storage first; then the plain cache (in case secure storage is
    // unavailable on this platform); then generate.
    String? id = await _secureRead(_kDeviceId) ?? cache.getString(_kDeviceId);
    id ??= _generateId();

    _deviceId = id;
    // Persist to both stores so a later secure-storage hiccup still resolves.
    await _secureWrite(_kDeviceId, id);
    await cache.setString(_kDeviceId, id);
    api.deviceId = id;
    return id;
  }

  String get deviceIdOrAnon => _deviceId ?? 'anon';

  /// A 128-bit hex id with a `dev-` prefix (matches the kind of stable seed the
  /// runtime plane buckets on). Uses Random.secure when available.
  String _generateId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'dev-$hex';
  }

  // ── session restore + token management ───────────────────────────────────────

  /// Load any persisted session on launch (sets [ApiClient.authToken]).
  Future<void> restoreSession() async {
    _accessToken = await _secureRead(_kAccessToken);
    _refreshToken = await _secureRead(_kRefreshToken);
    _uid = await _secureRead(_kUid);
    _role = await _secureRead(_kRole);
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      api.authToken = _accessToken;
    }
  }

  /// Store a freshly-issued session (after a login that 6g would implement).
  Future<void> setSession({
    required String accessToken,
    String? refreshToken,
    String? uid,
    String? role,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _uid = uid;
    _role = role;
    api.authToken = accessToken;
    await _secureWrite(_kAccessToken, accessToken);
    if (refreshToken != null) await _secureWrite(_kRefreshToken, refreshToken);
    if (uid != null) await _secureWrite(_kUid, uid);
    if (role != null) await _secureWrite(_kRole, role);
  }

  /// Clear the session (logout / unrecoverable 401). Device id is preserved.
  Future<void> clearSession() async {
    _accessToken = _refreshToken = _uid = _role = null;
    api.authToken = null;
    await _secureDelete(_kAccessToken);
    await _secureDelete(_kRefreshToken);
    await _secureDelete(_kUid);
    await _secureDelete(_kRole);
  }

  /// Attempt a token refresh after a 401. Returns true when a new token was
  /// installed. With no [refreshCallback] (the default), it clears the session
  /// and returns false (the app drops to anonymous — no refresh loop).
  Future<bool> handleUnauthorized() async {
    final rt = _refreshToken;
    final cb = refreshCallback;
    if (rt == null || rt.isEmpty || cb == null) {
      await clearSession();
      return false;
    }
    try {
      final fresh = await cb(rt);
      if (fresh == null || (fresh['accessToken'] ?? '').isEmpty) {
        await clearSession();
        return false;
      }
      await setSession(
        accessToken: fresh['accessToken']!,
        refreshToken: fresh['refreshToken'] ?? rt,
        uid: _uid,
        role: _role,
      );
      return true;
    } catch (_) {
      await clearSession();
      return false;
    }
  }

  // ── biometric unlock (config-gated) ──────────────────────────────────────────

  /// Whether the app should require a biometric unlock — gated by the runtime
  /// `config.session.biometric` AND the baked `features.biometricAuth`. Pass
  /// the resolved runtime flag in; this just ANDs it with the build feature.
  bool biometricRequired({required bool runtimeEnabled, required bool featureEnabled}) =>
      runtimeEnabled && featureEnabled;

  /// Prompt for biometric unlock. Returns true to proceed. Degrades to TRUE
  /// (allow) when the device has no biometrics enrolled or `local_auth` errors,
  /// so a misconfigured device is never locked out of a public app.
  Future<bool> unlock({String reason = 'Unlock the app'}) async {
    if (_unlocked) return true;
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) {
        _unlocked = true;
        return true;
      }
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      _unlocked = ok;
      return ok;
    } catch (_) {
      // No hardware / not enrolled / platform exception → don't lock out.
      _unlocked = true;
      return true;
    }
  }

  // ── secure-storage wrappers (never throw) ─────────────────────────────────────

  Future<String?> _secureRead(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _secureWrite(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {/* fall back to cache only */}
  }

  Future<void> _secureDelete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {/* ignore */}
  }
}
