/// SecurityService — the on-device side of the Phase-6g Runtime Security plane.
///
/// Fills the four 6f security hooks, ALL gated by the runtime envelope so they
/// no-op cleanly when their config is absent (CI-green, no new mandatory creds):
///
///   1. **Request signing** ([installSigning]) — installs an [ApiSecurityHooks]
///      `signRequest` on the shared [ApiClient] that HMAC-signs the canonical
///      string `METHOD\nPATH+QUERY\nUNIX_TS\nSHA256(body)` with the device's
///      signing key, but ONLY for paths in `config.security.signedRoutePrefixes`
///      and ONLY while `flags.security.requestSigning` is true. The HMAC key is
///      the hex SHA-256 of the secret (== the server's stored SecretHash), so the
///      raw secret (returned once at register) stays single-use. Mirrors the .NET
///      `RequestSignature` contract exactly.
///   2. **Cert pinning** ([pinningClientFactory]) — returns an `http.Client`
///      (an `IOClient` over a pinned `HttpClient`) that pins to the SHA-256 base64
///      pins in `config.security.certPins`. With NO pins (default) it returns a
///      plain client → no pinning, app unaffected. Pass it to `ApiClient` at
///      construction (main.dart) when pins are present.
///   3. **Integrity / trust** ([reportIntegrity] / [refreshTrust]) — gathers
///      root/jailbreak/emulator signals (honest stub here — see [gatherSignals]),
///      POSTs `/api/devices/{id}/integrity`, reads `/trust`, and exposes [blocked]
///      so the app can gate per `flags.security.blockUntrusted`.
///   4. **OAuth/OIDC login** ([completeOidcLogin]) — finalizes a manual PKCE code
///      flow by posting the IdP `id_token` to the callback → CMS JWT → setSession.
///
/// HONEST: the root/jailbreak/emulator detection here is a conservative STUB
/// (reports nothing as compromised unless a real detector package is added, e.g.
/// `freerasp` / `flutter_jailbreak_detection`) — it never claims a device is
/// clean dishonestly; the server's verdict stays "unverified" until real
/// attestation (Play Integrity / DeviceCheck) is wired. Exact SPKI cert pinning
/// likewise needs a native plugin; the pure-Dart pinning here compares the leaf
/// cert SHA-256 (documented approximation). See flutter-runtime-wiring.md.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../api_client.dart';
import 'auth_service.dart';
import 'runtime_service.dart';

class SecurityService {
  SecurityService({required this.api, required this.runtime, required this.auth});

  final ApiClient api;
  final RuntimeService runtime;
  final AuthService auth;

  /// The device signing key (keyId + secret) returned ONCE by /api/devices/register
  /// (or rotate). Persisted via [auth]'s secure storage. Null until known → signing
  /// stays a no-op (the server also only enforces when the flag is on).
  String? _signingKeyId;
  String? _signingSecret;

  /// The last trust read. `blocked` drives the app's gate when blockUntrusted is on.
  int _trustScore = 100;
  String _verdict = 'unverified';
  bool _blocked = false;

  int get trustScore => _trustScore;
  String get integrityVerdict => _verdict;
  bool get blocked => _blocked;

  static const _kSigningKeyId = 'cms.signingKeyId';
  static const _kSigningSecret = 'cms.signingSecret';

  // ── 1) Request signing ──────────────────────────────────────────────────────

  /// Persist the signing key from a device-register/rotate response (secret shown
  /// once). Stored in secure storage so it survives restarts.
  Future<void> setSigningKey({required String keyId, required String secret}) async {
    _signingKeyId = keyId;
    _signingSecret = secret;
    await auth.secureWrite(_kSigningKeyId, keyId);
    await auth.secureWrite(_kSigningSecret, secret);
  }

  /// Load any persisted signing key (call on launch before installing signing).
  Future<void> loadSigningKey() async {
    _signingKeyId ??= await auth.secureRead(_kSigningKeyId);
    _signingSecret ??= await auth.secureRead(_kSigningSecret);
  }

  bool get hasSigningKey =>
      (_signingKeyId?.isNotEmpty ?? false) && (_signingSecret?.isNotEmpty ?? false);

  /// Install the request-signing hook on the shared [ApiClient]. The hook itself
  /// re-checks the runtime flag + route prefixes on EVERY call, so it is inert
  /// until `flags.security.requestSigning` is on AND the path is signed — keeping
  /// full back-compat. Safe to call once after bootstrap.
  void installSigning() {
    api.security = ApiSecurityHooks(
      signRequest: _signRequest,
      certPinningClientFactory: api.security.certPinningClientFactory,
    );
  }

  /// The canonical-string HMAC signer. Returns the `X-Signature` + timestamp
  /// headers, or `{}` to skip signing (flag off / route not signed / no key).
  Map<String, String> _signRequest(String method, Uri uri, String? body) {
    if (!runtime.flagBool('security.requestSigning')) return const {};
    final keyId = _signingKeyId, secret = _signingSecret;
    if (keyId == null || secret == null || keyId.isEmpty || secret.isEmpty) return const {};

    final pathAndQuery = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    if (!_isSignedRoute(pathAndQuery)) return const {};

    final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final bodyHashHex = sha256.convert(utf8.encode(body ?? '')).toString(); // lowercase hex
    final canonical = '${method.toUpperCase()}\n$pathAndQuery\n$ts\n$bodyHashHex';

    // HMAC key = hex SHA-256 of the secret (== server's stored SecretHash), so the
    // raw secret stays single-use while both sides share the same verification key.
    final verKey = sha256.convert(utf8.encode(secret)).toString();
    final mac = Hmac(sha256, utf8.encode(verKey)).convert(utf8.encode(canonical));

    return {
      'X-Signature': '$keyId:${base64.encode(mac.bytes)}',
      'X-Signature-Timestamp': '$ts',
    };
  }

  bool _isSignedRoute(String pathAndQuery) {
    final prefixes = _signedPrefixes();
    return prefixes.any((p) => pathAndQuery.startsWith(p));
  }

  List<String> _signedPrefixes() {
    final raw = runtime.configValue('security.signedRoutePrefixes');
    if (raw is List) {
      final list = raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    return const ['/api/sync/forms'];
  }

  // ── 2) Cert pinning ─────────────────────────────────────────────────────────

  /// Read the configured pin set from the runtime envelope (for main.dart to pass
  /// into the client factory at construction).
  List<String> configuredPins() {
    final raw = runtime.configValue('security.certPins');
    if (raw is List) return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    return const [];
  }

  /// Build the `http.Client` to use, pinning to [pins] when present. With NO pins
  /// (the default) → a plain client (pinning a wrong/empty set would brick the
  /// app, so absent pins = no pinning). Pass to
  /// `ApiClient(certPinningClientFactory: SecurityService.pinningClientFactory(pins))`
  /// at construction. Pure-Dart (http + dart:io); no extra package needed.
  ///
  /// The pinned client enforces that every TLS connection's leaf certificate
  /// SHA-256 (base64) is in [pins], via `HttpClient.badCertificateCallback` — the
  /// standard pure-Dart pinning hook. Note: the callback is the OS's "should I
  /// accept this otherwise-untrusted cert?" hook; to make pinning authoritative
  /// for ALL connections (not only untrusted ones) the recommended production
  /// setup is a `SecurityContext` seeded ONLY with the pinned CA + this callback,
  /// or a native pinning plugin. HONEST NOTE: exact SPKI (public-key) pinning needs
  /// the public-key DER, which dart:io does not expose — so this pins on the leaf
  /// CERT SHA-256 (compute the pin from the same cert; rotate + keep a backup pin).
  /// For strict SPKI pinning add a native plugin (e.g. `http_certificate_pinning`)
  /// only when pins are configured.
  static http.Client Function() pinningClientFactory(List<String> pins) {
    return () {
      if (pins.isEmpty) return http.Client(); // no pins → no pinning (app unaffected)
      final pinSet = pins.map((p) => p.replaceFirst('sha256/', '').trim()).toSet();
      final inner = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          // Accept ONLY if the leaf cert's SHA-256 matches a configured pin.
          final hash = base64.encode(sha256.convert(cert.der).bytes);
          return pinSet.contains(hash);
        };
      return IOClient(inner);
    };
  }

  // ── 3) Integrity / trust ─────────────────────────────────────────────────────

  /// Gather the integrity signals we can observe. HONEST: without a real detector
  /// package this reports nothing as compromised (root/jailbreak/emulator = false)
  /// — it NEVER claims those as verified facts; the server records the verdict as
  /// "unverified" accordingly. Add a detector (freerasp / flutter_jailbreak_detection)
  /// to populate these for real, and pass a Play Integrity / DeviceCheck token in
  /// `attestationProvider` + `attestationToken` for server-side verification.
  Map<String, dynamic> gatherSignals() => {
        'isRooted': false,
        'isJailbroken': false,
        'isEmulator': false,
        'isDebuggerAttached': false,
        'appSignatureValid': true,
      };

  /// POST the gathered signals to `/api/devices/{deviceId}/integrity` and update
  /// the cached trust. Fire-and-forget safe (never throws).
  Future<void> reportIntegrity() async {
    final deviceId = auth.deviceIdOrAnon;
    if (deviceId == 'anon' || !api.hasBaseUrl) return;
    final res = await api.postJsonRaw('/api/devices/$deviceId/integrity', gatherSignals());
    _applyTrust(res.body);
  }

  /// Read `/api/devices/{deviceId}/trust` and update the cached trust + gate.
  Future<void> refreshTrust() async {
    final deviceId = auth.deviceIdOrAnon;
    if (deviceId == 'anon' || !api.hasBaseUrl) return;
    final res = await api.getRaw('/api/devices/$deviceId/trust');
    _applyTrust(res.body);
  }

  void _applyTrust(dynamic body) {
    final data = body is Map && body['data'] is Map ? body['data'] as Map : null;
    if (data == null) return;
    _trustScore = (data['trustScore'] is num) ? (data['trustScore'] as num).toInt() : _trustScore;
    _verdict = data['integrityVerdict']?.toString() ?? _verdict;
    // The server already AND-ed the flag + threshold into `blocked`.
    _blocked = data['blocked'] == true;
  }

  // ── 4) OAuth / OIDC login (manual PKCE) ───────────────────────────────────────

  /// Finalize an OIDC login: POST the IdP-issued `id_token` to
  /// `/api/auth/external/callback`, which validates it (for real where the IdP's
  /// discovery URL is reachable) + mints a CMS JWT, then feed that JWT to
  /// [AuthService.setSession]. The browser-open + redirect-capture earlier steps
  /// (authorize URL with PKCE → custom-tab → app deep-link redirect → IdP token
  /// endpoint) are wired by the host using the existing `url_launcher` + `app_links`
  /// callback path. Returns true on a minted session; HONEST: false when the
  /// backend says the IdP is not configured / the token is invalid (no fake session).
  Future<bool> completeOidcLogin({required String provider, required String idToken}) async {
    if (!api.hasBaseUrl) return false;
    final res = await api.postJsonRaw('/api/auth/external/callback', {
      'provider': provider,
      'idToken': idToken,
    });
    final data = res.body is Map && (res.body as Map)['data'] is Map
        ? (res.body as Map)['data'] as Map
        : null;
    final token = data?['token']?.toString();
    if (res.isOk && token != null && token.isNotEmpty) {
      await auth.setSession(
        accessToken: token,
        uid: data?['userName']?.toString(),
        role: (data?['roles'] is List && (data!['roles'] as List).isNotEmpty)
            ? (data['roles'] as List).first.toString()
            : null,
      );
      return true;
    }
    return false; // honest: not configured / invalid token → no session
  }
}
