/// SyncService — the on-device side of the Phase-6d Offline + Sync plane.
///
/// Implements the four offline behaviours the CMS contracts expose, all
/// flag-gated server-side (offline OFF → the endpoints return `enabled:false`,
/// which this service treats as "skip"):
///
///   1. **Cache plan** — `GET /api/sync/manifest` → precache the listed
///      collections into Hive (via [CacheService]); honour `syncIntervalSeconds`,
///      `maxCacheMb`, `conflictStrategy`.
///   2. **Delta sync** — `GET /api/sync/delta?since=<cursor>` on an interval and
///      on resume / reconnect: apply per-type `items` (upserts) + `deleted`
///      (tombstones) to the cache, persist the new `cursor`, and re-poll while
///      `hasMore`.
///   3. **Offline form queue** — queue submissions locally with a
///      client-generated `clientSubmissionId`; flush via
///      `POST /api/sync/forms/submit` on reconnect — **idempotent**, so a flaky
///      flush is safe to retry (the server dedupes on `clientSubmissionId`).
///   4. **Favorites mirror** — local add/remove kept in Hive + synced via
///      `GET/POST /api/sync/favorites` (LWW on `clientTs`, device/uid-scoped).
///
/// Uses `connectivity_plus` (6.x → `List<ConnectivityResult>`) to flush the
/// form queue + pull a delta the moment the device comes back online.
///
/// **Graceful degradation:** every network call is via the raw client (never
/// throws); offline reads come straight from the cache; `enabled:false` from
/// the server short-circuits cleanly; with no base URL the whole service is
/// inert and the app uses whatever is cached.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../api_client.dart';
import '../storage/cache_service.dart';

class SyncService {
  SyncService({
    required this.api,
    required this.cache,
    required this.localeProvider,
    this.deviceIdProvider,
    this.uidProvider,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final ApiClient api;
  final CacheService cache;
  final String Function() localeProvider;

  /// Resolves the stable device id at call time (it's generated during
  /// bootstrap, possibly after this service is constructed).
  final String? Function()? deviceIdProvider;
  final String? Function()? uidProvider;
  final Connectivity _connectivity;

  static const _cursorKey = 'sync.cursor';

  Timer? _deltaTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _enabled = true;
  bool _syncing = false;

  bool get enabled => _enabled;

  // ── bootstrap ───────────────────────────────────────────────────────────────

  /// Load the manifest, precache the listed collections, then start the delta
  /// loop + connectivity listener. Safe to call once on launch. Honours the
  /// server's `syncIntervalSeconds`. Offline OFF → the service idles.
  Future<void> start() async {
    if (!api.hasBaseUrl) return;
    final manifest = await _fetchManifest();
    _enabled = manifest?['enabled'] == true;

    if (_enabled && manifest != null) {
      await _precacheFromManifest(manifest);
      final intervalSec = (manifest['syncIntervalSeconds'] as num?)?.toInt() ?? 900;
      _deltaTimer?.cancel();
      _deltaTimer = Timer.periodic(Duration(seconds: max(60, intervalSec)), (_) => syncDelta());
      // An immediate first delta after precache to catch anything fresh.
      await syncDelta();
    }

    // Flush the offline form queue + pull a delta whenever connectivity returns.
    _connSub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        flushFormQueue();
        if (_enabled) syncDelta();
      }
    });
  }

  /// Called on app resume to pull anything changed while backgrounded.
  Future<void> onResume() async {
    if (_enabled) await syncDelta();
    await flushFormQueue();
  }

  // ── manifest + precache ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchManifest() async {
    final res = await api.getRaw('/api/sync/manifest', query: {'lang': localeProvider()});
    if (res.isOk && res.body is Map && (res.body as Map)['data'] is Map) {
      return ((res.body as Map)['data'] as Map).map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Pre-cache each `precache[]` collection. Content collections resolve to a
  /// full delta (`since` empty); menu/home endpoints are already cached by the
  /// shell, so we only pull content here (keys that aren't menu/home).
  Future<void> _precacheFromManifest(Map<String, dynamic> manifest) async {
    final precache = manifest['precache'];
    if (precache is! List) return;
    for (final entry in precache.whereType<Map>()) {
      final key = (entry['key'] ?? '').toString();
      if (key.isEmpty || key == 'menu' || key == 'home') continue;
      await _fullSyncType(key);
    }
  }

  /// Initial full pull for a single type (since=empty) → cache it.
  Future<void> _fullSyncType(String type) async {
    final res = await api.getRaw('/api/sync/delta', query: {
      'types': type,
      'lang': localeProvider(),
    });
    final data = _deltaData(res);
    if (data == null) return;
    final types = data['types'];
    if (types is List) {
      for (final t in types.whereType<Map>()) {
        final tName = (t['type'] ?? '').toString();
        final items = (t['items'] as List?)?.whereType<Map>().map(_asStrMap).toList() ?? const [];
        await cache.putCollection(tName, items);
      }
    }
  }

  // ── delta sync ────────────────────────────────────────────────────────────────

  /// Pull the changed-since delta, apply upserts + tombstones, advance the
  /// cursor, and re-poll while the server says `hasMore`. Concurrency-guarded.
  Future<void> syncDelta() async {
    if (_syncing || !_enabled || !api.hasBaseUrl) return;
    _syncing = true;
    try {
      var guard = 0; // safety bound on the hasMore loop
      while (guard++ < 20) {
        final since = cache.getString(_cursorKey) ?? '';
        final res = await api.getRaw('/api/sync/delta', query: {
          if (since.isNotEmpty) 'since': since,
          'lang': localeProvider(),
        });
        final data = _deltaData(res);
        if (data == null) break;
        if (data['enabled'] == false) {
          _enabled = false;
          break;
        }

        final types = data['types'];
        if (types is List) {
          for (final t in types.whereType<Map>()) {
            final tName = (t['type'] ?? '').toString();
            if (tName.isEmpty) continue;
            final items = (t['items'] as List?)?.whereType<Map>().map(_asStrMap).toList() ?? const [];
            final deleted = (t['deleted'] as List?)?.whereType<num>().map((n) => n.toInt()).toList() ?? const [];
            await cache.applyCollectionDelta(tName, items: items, deletedIds: deleted);
          }
        }

        final cursor = (data['cursor'] ?? '').toString();
        if (cursor.isNotEmpty) await cache.setString(_cursorKey, cursor);

        if (data['hasMore'] != true) break; // done
      }
    } finally {
      _syncing = false;
    }
  }

  /// Read a cached collection (for offline list rendering). Returns the items
  /// (newest-id-first is not guaranteed; callers can sort by their own field).
  List<Map<String, dynamic>> cachedCollection(String key) =>
      cache.readCollection(key).values.toList();

  // ── offline form queue ──────────────────────────────────────────────────────

  /// Queue a form submission locally. Returns the generated clientSubmissionId.
  /// [submissionData] is the JSON string the online submit path expects.
  Future<String> queueFormSubmission({
    required int formId,
    required String submissionData,
    String? formKey,
    String? submitterEmail,
    String? submitterName,
  }) async {
    final clientSubmissionId = 'offline-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    await cache.enqueueForm(clientSubmissionId, {
      'clientSubmissionId': clientSubmissionId,
      'formId': formId,
      'submissionData': submissionData,
      'formKey': formKey,
      'submitterEmail': submitterEmail,
      'submitterName': submitterName,
    });
    // Best-effort immediate flush (in case we're actually online).
    unawaited(flushFormQueue());
    return clientSubmissionId;
  }

  /// Flush all queued submissions in one idempotent batch. On a confirmed
  /// per-item result (`accepted`/`duplicate`/`rejected`) the row is dequeued;
  /// a network failure keeps the queue for the next reconnect. Never throws.
  Future<void> flushFormQueue() async {
    if (!api.hasBaseUrl) return;
    final queued = cache.readFormQueue();
    if (queued.isEmpty) return;

    final items = queued.values.toList();
    final res = await api.postJsonRaw('/api/sync/forms/submit', {'items': items});
    if (res.statusCode == 0) return; // offline → keep + retry
    if (!res.isOk || res.body is! Map) return;

    final data = (res.body as Map)['data'];
    if (data is! Map) return;
    if (data['enabled'] == false) return; // offline disabled server-side; keep queue

    final results = data['results'];
    if (results is List) {
      for (final r in results.whereType<Map>()) {
        final csid = (r['clientSubmissionId'] ?? '').toString();
        final status = (r['status'] ?? '').toString();
        // accepted | duplicate → done (idempotent). rejected → drop (won't ever
        // succeed: validation/form-missing) so it doesn't wedge the queue.
        if (csid.isNotEmpty && (status == 'accepted' || status == 'duplicate' || status == 'rejected')) {
          await cache.dequeueForm(csid);
        }
      }
    }
  }

  // ── favorites (LWW mirror) ────────────────────────────────────────────────────

  /// The local favorite keys ("entityType:entityId") currently marked.
  List<Map<String, dynamic>> localFavorites() =>
      cache.readFavorites().values.where((f) => f['isRemoved'] != true).toList();

  bool isFavorite(String entityType, int entityId) {
    final row = cache.readFavorites()['${entityType.toLowerCase()}:$entityId'];
    return row != null && row['isRemoved'] != true;
  }

  /// Toggle a favorite: update the local mirror immediately (optimistic) then
  /// sync to the server (LWW). Returns the new state (true = favorited).
  Future<bool> toggleFavorite(String entityType, int entityId) async {
    final type = entityType.toLowerCase();
    final key = '$type:$entityId';
    final existing = cache.readFavorites()[key];
    final nowFavorited = !(existing != null && existing['isRemoved'] != true);
    final clientTs = DateTime.now().toUtc().toIso8601String();

    await cache.putFavorite(key, {
      'entityType': type,
      'entityId': entityId,
      'isRemoved': !nowFavorited,
      'clientTs': clientTs,
    });

    // Server sync (best-effort; the local mirror already reflects the change).
    await _syncFavoriteOp(type, entityId, nowFavorited ? 'add' : 'remove', clientTs);
    return nowFavorited;
  }

  Future<void> _syncFavoriteOp(String entityType, int entityId, String action, String clientTs) async {
    if (!api.hasBaseUrl) return;
    final owner = _favoriteOwnerQuery();
    if (owner.isEmpty) return; // no deviceId/uid → local-only
    await api.postJsonRaw('/api/sync/favorites', {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'clientTs': clientTs,
    }, query: owner);
  }

  /// Pull the server's merged favorite set (e.g. on launch / after sign-in) and
  /// reconcile into the local mirror (server is the merged LWW truth).
  Future<void> pullFavorites() async {
    if (!api.hasBaseUrl) return;
    final owner = _favoriteOwnerQuery();
    if (owner.isEmpty) return;
    final res = await api.getRaw('/api/sync/favorites', query: owner);
    if (!res.isOk || res.body is! Map) return;
    final data = (res.body as Map)['data'];
    if (data is! Map) return;
    final favs = data['favorites'];
    if (favs is! List) return;
    for (final f in favs.whereType<Map>()) {
      final type = (f['entityType'] ?? '').toString().toLowerCase();
      final id = (f['entityId'] as num?)?.toInt();
      if (type.isEmpty || id == null) continue;
      await cache.putFavorite('$type:$id', {
        'entityType': type,
        'entityId': id,
        'isRemoved': false,
        'clientTs': (f['clientTs'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
      });
    }
  }

  Map<String, String> _favoriteOwnerQuery() {
    final uid = uidProvider?.call();
    if (uid != null && uid.isNotEmpty) return {'uid': uid};
    final dev = deviceIdProvider?.call() ?? api.deviceId;
    if (dev != null && dev.isNotEmpty) return {'deviceId': dev};
    return const {};
  }

  // ── helpers ──

  /// Unwrap a delta `RawResponse` → its `data` map.
  Map<String, dynamic>? _deltaData(RawResponse res) {
    if (res.isOk && res.body is Map && (res.body as Map)['data'] is Map) {
      return ((res.body as Map)['data'] as Map).map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Map<String, dynamic> _asStrMap(Map m) => m.map((k, v) => MapEntry(k.toString(), v));

  /// Expose the raw cursor (for an admin/debug view).
  String? get cursor => cache.getString(_cursorKey);

  /// JSON dump of the queue (debug).
  String debugQueueJson() => jsonEncode(cache.readFormQueue());

  void dispose() {
    _deltaTimer?.cancel();
    _connSub?.cancel();
  }
}
