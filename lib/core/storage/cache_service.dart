/// Lightweight on-device cache for the Phase-6f runtime + offline planes.
///
/// Backed by **Hive** (pure-Dart, no native code, no codegen — raw dynamic
/// boxes), so it adds nothing to the Android Kotlin/Gradle scaffold the CI
/// builds. Everything is **degradation-safe**: if Hive fails to initialise
/// (e.g. a platform without a writable docs dir during a test), the service
/// flips to an in-memory map so callers never crash — the app just loses
/// persistence for that session.
///
/// Box layout (one box per concern, all opened lazily on [init]):
///   • `kv`         — small scalars: device id, runtime ETag + envelope JSON,
///                    sync cursor, analytics session, consent flag, tokens-meta.
///   • `collections`— cached content collections by key (delta upserts), each a
///                    `{ id: itemJson }` map so a tombstone can evict by id.
///   • `formQueue`  — queued offline form submissions (clientSubmissionId → row).
///   • `favorites`  — local favorites mirror (key → row) for LWW sync.
///
/// Used by: RuntimeService (ETag/envelope), SyncService (cursor/collections/
/// queue/favorites), AnalyticsService (session/consent), AuthService (uid hint).
library;

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  CacheService._();

  static final CacheService instance = CacheService._();

  static const _kvBox = 'cms_kv';
  static const _collectionsBox = 'cms_collections';
  static const _formQueueBox = 'cms_form_queue';
  static const _favoritesBox = 'cms_favorites';

  Box<dynamic>? _kv;
  Box<dynamic>? _collections;
  Box<dynamic>? _forms;
  Box<dynamic>? _favorites;

  /// In-memory fallback maps used when Hive is unavailable, so every read/write
  /// below still works (just not persisted).
  final Map<String, dynamic> _memKv = {};
  final Map<String, Map<String, dynamic>> _memCollections = {};
  final Map<String, dynamic> _memForms = {};
  final Map<String, dynamic> _memFavorites = {};

  bool _ready = false;
  bool get usingFallback => _kv == null;

  /// Open Hive + the boxes. Idempotent and never throws — on any failure it
  /// logs nothing (no `print`, per lints) and silently uses the in-memory maps.
  Future<void> init() async {
    if (_ready) return;
    try {
      await Hive.initFlutter('cms2026_cache');
      _kv = await Hive.openBox<dynamic>(_kvBox);
      _collections = await Hive.openBox<dynamic>(_collectionsBox);
      _forms = await Hive.openBox<dynamic>(_formQueueBox);
      _favorites = await Hive.openBox<dynamic>(_favoritesBox);
    } catch (_) {
      // Keep boxes null → fall back to in-memory maps.
      _kv = null;
      _collections = null;
      _forms = null;
      _favorites = null;
    }
    _ready = true;
  }

  // ── KV scalars ──────────────────────────────────────────────────────────────

  String? getString(String key) {
    final v = _kv != null ? _kv!.get(key) : _memKv[key];
    return v is String ? v : null;
  }

  Future<void> setString(String key, String value) async {
    if (_kv != null) {
      await _kv!.put(key, value);
    } else {
      _memKv[key] = value;
    }
  }

  bool? getBool(String key) {
    final v = _kv != null ? _kv!.get(key) : _memKv[key];
    return v is bool ? v : null;
  }

  Future<void> setBool(String key, bool value) async {
    if (_kv != null) {
      await _kv!.put(key, value);
    } else {
      _memKv[key] = value;
    }
  }

  Future<void> remove(String key) async {
    if (_kv != null) {
      await _kv!.delete(key);
    } else {
      _memKv.remove(key);
    }
  }

  // ── Collections (delta-synced content) ───────────────────────────────────────

  /// The cached `{ idString: itemMap }` for a collection key (e.g. "news").
  Map<String, Map<String, dynamic>> readCollection(String key) {
    if (_collections != null) {
      final raw = _collections!.get(key);
      if (raw is String && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            return decoded.map((k, v) => MapEntry(
                k.toString(),
                v is Map ? v.map((kk, vv) => MapEntry(kk.toString(), vv)) : <String, dynamic>{}));
          }
        } catch (_) {/* corrupt → empty */}
      }
      return {};
    }
    return Map<String, Map<String, dynamic>>.from(_memCollections[key] ?? {});
  }

  /// Apply a delta to a collection: upsert [items] (keyed by their `id`) and
  /// evict [deletedIds] (tombstones). Persists the merged map.
  Future<void> applyCollectionDelta(
    String key, {
    required List<Map<String, dynamic>> items,
    required List<int> deletedIds,
  }) async {
    final current = readCollection(key);
    for (final it in items) {
      final id = it['id'];
      if (id != null) current['$id'] = it;
    }
    for (final d in deletedIds) {
      current.remove('$d');
    }
    if (_collections != null) {
      await _collections!.put(key, jsonEncode(current));
    } else {
      _memCollections[key] = current;
    }
  }

  /// Replace a collection wholesale (used by an initial precache from a list).
  Future<void> putCollection(String key, List<Map<String, dynamic>> items) async {
    final map = <String, Map<String, dynamic>>{};
    for (final it in items) {
      final id = it['id'];
      if (id != null) map['$id'] = it;
    }
    if (_collections != null) {
      await _collections!.put(key, jsonEncode(map));
    } else {
      _memCollections[key] = map;
    }
  }

  // ── Offline form queue ────────────────────────────────────────────────────────

  /// All queued submissions (clientSubmissionId → row map).
  Map<String, Map<String, dynamic>> readFormQueue() => _readJsonMap(_forms, _memForms);

  Future<void> enqueueForm(String clientSubmissionId, Map<String, dynamic> row) =>
      _putInMap(_forms, _memForms, clientSubmissionId, row);

  Future<void> dequeueForm(String clientSubmissionId) =>
      _deleteFromMap(_forms, _memForms, clientSubmissionId);

  // ── Favorites mirror ────────────────────────────────────────────────────────

  Map<String, Map<String, dynamic>> readFavorites() => _readJsonMap(_favorites, _memFavorites);

  Future<void> putFavorite(String key, Map<String, dynamic> row) =>
      _putInMap(_favorites, _memFavorites, key, row);

  Future<void> deleteFavorite(String key) =>
      _deleteFromMap(_favorites, _memFavorites, key);

  // ── shared box/map helpers ──

  Map<String, Map<String, dynamic>> _readJsonMap(Box<dynamic>? box, Map<String, dynamic> mem) {
    if (box != null) {
      final out = <String, Map<String, dynamic>>{};
      for (final k in box.keys) {
        final v = box.get(k);
        if (v is String) {
          try {
            final d = jsonDecode(v);
            if (d is Map) out['$k'] = d.map((kk, vv) => MapEntry(kk.toString(), vv));
          } catch (_) {/* skip corrupt */}
        }
      }
      return out;
    }
    return {
      for (final e in mem.entries)
        if (e.value is Map) e.key: (e.value as Map).map((k, v) => MapEntry(k.toString(), v)),
    };
  }

  Future<void> _putInMap(
      Box<dynamic>? box, Map<String, dynamic> mem, String key, Map<String, dynamic> row) async {
    if (box != null) {
      await box.put(key, jsonEncode(row));
    } else {
      mem[key] = row;
    }
  }

  Future<void> _deleteFromMap(Box<dynamic>? box, Map<String, dynamic> mem, String key) async {
    if (box != null) {
      await box.delete(key);
    } else {
      mem.remove(key);
    }
  }
}
