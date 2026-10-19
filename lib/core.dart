import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

const Map<String, String> kIptvHeaders = {
  'User-Agent': 'IPTVSmartersPlayer',
  'Accept': '*/*',
};

const Map<String, String> kVlcHeaders = {
  'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
  'Accept': '*/*',
};

const Map<String, String> kXciptvHeaders = {
  'User-Agent': 'XCIPTV',
  'Accept': '*/*',
};

const MethodChannel nativeChannel = MethodChannel('unex.vision/native');

enum DeviceMode { mobile, tv }
enum ContentType { live, movie, series }
enum MainSection { live, movie, series, continueWatching, favorites, recents }

// =============================================================================
// LIBERAÇÃO DE CERTIFICADOS SSL AUTOASSINADOS EM SERVIDORES IPTV
// =============================================================================
class UnexHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }
}

// =============================================================================
// 1. MODELOS DE DADOS (COM SUPORTE A UNIFICAÇÃO DUBLADO + LEGENDADO '(L)')
// =============================================================================
class StreamItem {
  final String id;
  final String streamId;
  final String tvgId;
  final String name;
  final String cleanName;
  final String seriesName;
  final int seasonNumber;
  final int episodeNumber;
  final String qualityTag;
  final String group;
  final String logo;
  final String url;
  final ContentType type;
  final bool isAdult;
  final String synopsis;
  final String rating;
  final String year;
  final String cast;

  // Campos para unificação de versão Legendada (L)
  final String? subtitledUrl;
  final String? subtitledStreamId;
  final String? subtitledName;
  final bool isSubtitledOnly;

  StreamItem({
    required this.id,
    required this.streamId,
    required this.tvgId,
    required this.name,
    required this.cleanName,
    required this.seriesName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.qualityTag,
    required this.group,
    required this.logo,
    required this.url,
    required this.type,
    required this.isAdult,
    this.synopsis = 'Nenhuma sinopse disponível.',
    this.rating = 'N/A',
    this.year = '',
    this.cast = '',
    this.subtitledUrl,
    this.subtitledStreamId,
    this.subtitledName,
    this.isSubtitledOnly = false,
  });

  bool get hasBothAudioOptions => subtitledUrl != null && subtitledUrl!.isNotEmpty;

  StreamItem copyWith({
    String? name,
    String? cleanName,
    String? synopsis,
    String? rating,
    String? year,
    String? cast,
    String? url,
    String? subtitledUrl,
    String? subtitledStreamId,
    String? subtitledName,
    bool? isSubtitledOnly,
  }) {
    return StreamItem(
      id: id,
      streamId: streamId,
      tvgId: tvgId,
      name: name ?? this.name,
      cleanName: cleanName ?? this.cleanName,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      qualityTag: qualityTag,
      group: group,
      logo: logo,
      url: url ?? this.url,
      type: type,
      isAdult: isAdult,
      synopsis: (synopsis != null && synopsis.trim().isNotEmpty) ? synopsis : this.synopsis,
      rating: (rating != null && rating.trim().isNotEmpty) ? rating : this.rating,
      year: (year != null && year.trim().isNotEmpty) ? year : this.year,
      cast: (cast != null && cast.trim().isNotEmpty) ? cast : this.cast,
      subtitledUrl: subtitledUrl ?? this.subtitledUrl,
      subtitledStreamId: subtitledStreamId ?? this.subtitledStreamId,
      subtitledName: subtitledName ?? this.subtitledName,
      isSubtitledOnly: isSubtitledOnly ?? this.isSubtitledOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'streamId': streamId,
        'tvgId': tvgId,
        'name': name,
        'cleanName': cleanName,
        'seriesName': seriesName,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'qualityTag': qualityTag,
        'group': group,
        'logo': logo,
        'url': url,
        'type': type.index,
        'isAdult': isAdult,
        'synopsis': synopsis,
        'rating': rating,
        'year': year,
        'cast': cast,
        'subtitledUrl': subtitledUrl,
        'subtitledStreamId': subtitledStreamId,
        'subtitledName': subtitledName,
        'isSubtitledOnly': isSubtitledOnly,
      };

  factory StreamItem.fromJson(Map<String, dynamic> json) {
    return StreamItem(
      id: json['id']?.toString() ?? '',
      streamId: json['streamId']?.toString() ?? '',
      tvgId: json['tvgId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Conteúdo',
      cleanName: json['cleanName']?.toString() ?? (json['name']?.toString() ?? 'Conteúdo'),
      seriesName: json['seriesName']?.toString() ?? '',
      seasonNumber: (json['seasonNumber'] as int?) ?? 1,
      episodeNumber: (json['episodeNumber'] as int?) ?? 1,
      qualityTag: json['qualityTag']?.toString() ?? 'HD',
      group: json['group']?.toString() ?? 'Geral',
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: ContentType.values[(json['type'] as int?)?.clamp(0, 2) ?? 0],
      isAdult: json['isAdult'] == true,
      synopsis: json['synopsis']?.toString() ?? 'Nenhuma sinopse disponível.',
      rating: json['rating']?.toString() ?? 'N/A',
      year: json['year']?.toString() ?? '',
      cast: json['cast']?.toString() ?? '',
      subtitledUrl: json['subtitledUrl']?.toString(),
      subtitledStreamId: json['subtitledStreamId']?.toString(),
      subtitledName: json['subtitledName']?.toString(),
      isSubtitledOnly: json['isSubtitledOnly'] == true,
    );
  }
}

class VodProgressEntry {
  final StreamItem item;
  final int positionSeconds;
  final int durationSeconds;
  final int updatedAtMs;

  VodProgressEntry({
    required this.item,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAtMs,
  });

  double get progress =>
      durationSeconds > 0 ? (positionSeconds / durationSeconds).clamp(0.0, 1.0) : 0.0;

  String get formattedRemaining {
    final rem = (durationSeconds - positionSeconds).clamp(0, 86400);
    return 'Faltam ${(rem / 60).ceil()} min';
  }

  String get formattedPosition {
    final m = (positionSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (positionSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'updatedAtMs': updatedAtMs,
      };

  factory VodProgressEntry.fromJson(Map<String, dynamic> json) => VodProgressEntry(
        item: StreamItem.fromJson((json['item'] as Map?)?.cast<String, dynamic>() ?? {}),
        positionSeconds: (json['positionSeconds'] as int?) ?? 0,
        durationSeconds: (json['durationSeconds'] as int?) ?? 1,
        updatedAtMs: (json['updatedAtMs'] as int?) ?? 0,
      );
}

class EpgProgramInfo {
  final String nowTitle;
  final String nextTitle;
  final double progress;
  const EpgProgramInfo({
    required this.nowTitle,
    required this.nextTitle,
    this.progress = 0.45,
  });
}

class SeriesGroup {
  final String id;
  final String seriesId;
  final String title;
  final String group;
  final String logo;
  final String synopsis;
  final String rating;
  final String year;
  final String cast;
  final String qualityTag;
  final bool isAdult;
  final Map<int, List<StreamItem>> seasons;

  SeriesGroup({
    required this.id,
    this.seriesId = '',
    required this.title,
    required this.group,
    required this.logo,
    this.synopsis = 'Selecione para explorar as temporadas e episódios desta série.',
    this.rating = '8.5',
    this.year = '',
    this.cast = '',
    required this.qualityTag,
    required this.isAdult,
    required this.seasons,
  });

  int get totalSeasons => seasons.isEmpty ? 1 : seasons.length;
  int get totalEpisodes => seasons.values.fold(0, (sum, list) => sum + list.length);

  List<StreamItem> get allEpisodesFlat {
    final sortedKeys = seasons.keys.toList()..sort();
    return sortedKeys.expand((k) => seasons[k]!).toList();
  }
}

// =============================================================================
// UNIFICADOR AUTOMÁTICO DE FILMES DUBLADOS E LEGENDADOS '(L)'
// =============================================================================
final RegExp _kSubtitledMarkerRegex = RegExp(
  r'(\(\s*[lL]\s*\)|\[\s*[lL]\s*\]|\(\s*leg(?:endado)?\s*\)|\[\s*leg(?:endado)?\s*\]|\blegendado\b)',
  caseSensitive: false,
);

final RegExp _kDubbedMarkerRegex = RegExp(
  r'(\(\s*dub(?:lado)?\s*\)|\[\s*dub(?:lado)?\s*\]|\bdublado\b)',
  caseSensitive: false,
);

final RegExp _kQualityStripRegex = RegExp(
  r'\b(4K|UHD|FHD|1080P|HD|720P|SD|H265|HEVC)\b',
  caseSensitive: false,
);

class _MovieLanguageBucket {
  final List<StreamItem> dubbed = [];
  final List<StreamItem> subtitled = [];
}

String _normalizeMovieTitleKey(String rawTitle) {
  String s = rawTitle
      .replaceAll(_kSubtitledMarkerRegex, ' ')
      .replaceAll(_kDubbedMarkerRegex, ' ')
      .replaceAll(_kQualityStripRegex, ' ')
      .replaceAll(RegExp(r'[\[\]\(\)\-\|\:\._]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  return s.isEmpty ? rawTitle.trim().toLowerCase() : s;
}

String _cleanSubtitledDisplayTitle(String rawTitle) {
  final cleaned = rawTitle
      .replaceAll(_kSubtitledMarkerRegex, '')
      .replaceAll(_kDubbedMarkerRegex, '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  return cleaned.isEmpty ? rawTitle.trim() : cleaned;
}

List<StreamItem> unifyMoviesByLanguage(List<StreamItem> items) {
  final List<StreamItem> nonMovies = [];
  final Map<String, _MovieLanguageBucket> movieBuckets = {};
  final List<String> keyOrder = [];

  for (final item in items) {
    if (item.type != ContentType.movie) {
      nonMovies.add(item);
      continue;
    }

    final isSub = _kSubtitledMarkerRegex.hasMatch(item.name) ||
        item.group.toLowerCase().contains('legendado');
    final normKey = _normalizeMovieTitleKey(item.name);

    final bucket = movieBuckets.putIfAbsent(normKey, () {
      keyOrder.add(normKey);
      return _MovieLanguageBucket();
    });

    if (isSub) {
      bucket.subtitled.add(item);
    } else {
      bucket.dubbed.add(item);
    }
  }

  final List<StreamItem> unifiedMovies = [];

  for (final key in keyOrder) {
    final bucket = movieBuckets[key]!;
    final int pairCount = bucket.dubbed.length < bucket.subtitled.length
        ? bucket.dubbed.length
        : bucket.subtitled.length;

    // 1. Casa cada versão Dublada com sua versão Legendada (L) em um único item
    for (int i = 0; i < pairCount; i++) {
      final dub = bucket.dubbed[i];
      final sub = bucket.subtitled[i];
      final displayTitle = _cleanSubtitledDisplayTitle(dub.name);
      unifiedMovies.add(
        dub.copyWith(
          name: displayTitle,
          cleanName: displayTitle,
          subtitledUrl: sub.url,
          subtitledStreamId: sub.streamId,
          subtitledName: sub.name,
          isSubtitledOnly: false,
        ),
      );
    }

    // 2. Mantém versões apenas Dubladas restantes
    for (int i = pairCount; i < bucket.dubbed.length; i++) {
      unifiedMovies.add(bucket.dubbed[i]);
    }

    // 3. Mantém versões apenas Legendadas (L) que não possuem par dublado
    for (int i = pairCount; i < bucket.subtitled.length; i++) {
      final subOnly = bucket.subtitled[i];
      unifiedMovies.add(
        subOnly.copyWith(isSubtitledOnly: true),
      );
    }
  }

  return [...nonMovies, ...unifiedMovies];
}

// =============================================================================
// 2. ARMAZENAMENTO OFFLINE-FIRST E PERSISTÊNCIA EM DISCO
// =============================================================================
class AppStorage {
  static String get _tmp => Directory.systemTemp.path;
  static File get _sessionFile => File('$_tmp/unex_v23_session.json');
  static File get _deviceFile => File('$_tmp/unex_v23_device.json');
  static File get _vodProgressFile => File('$_tmp/unex_v23_vod_progress.json');
  static File get _favoritesFile => File('$_tmp/unex_v23_favorites.json');
  static File get _recentsFile => File('$_tmp/unex_v23_recents.json');
  static File get _offlinePlaylistFile => File('$_tmp/unex_v23_offline_playlist.json');
  static File get _parentalPinFile => File('$_tmp/unex_v23_parental_pin.txt');

  static Future<DeviceMode> getOrDetectDeviceMode() async {
    try {
      if (await _deviceFile.exists()) {
        final data = jsonDecode(await _deviceFile.readAsString());
        if (data['mode'] == 'tv') return DeviceMode.tv;
        if (data['mode'] == 'mobile') return DeviceMode.mobile;
      }
      final bool isTV = await nativeChannel.invokeMethod('isAndroidTV') ?? false;
      return isTV ? DeviceMode.tv : DeviceMode.mobile;
    } catch (_) {
      return DeviceMode.tv;
    }
  }

  static Future<void> saveDeviceMode(DeviceMode mode) async {
    try {
      await _deviceFile.writeAsString(jsonEncode({'mode': mode == DeviceMode.tv ? 'tv' : 'mobile'}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadVerifiedSession() async {
    try {
      if (await _sessionFile.exists()) {
        return jsonDecode(await _sessionFile.readAsString());
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveVerifiedSession(Map<String, dynamic> data) async {
    try {
      data['verified'] = true;
      await _sessionFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> clearAllData() async {
    try {
      for (final f in [
        _sessionFile,
        _vodProgressFile,
        _favoritesFile,
        _recentsFile,
        _offlinePlaylistFile,
      ]) {
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  static Future<String> loadParentalPin() async {
    try {
      if (await _parentalPinFile.exists()) {
        final saved = (await _parentalPinFile.readAsString()).trim();
        if (saved.isNotEmpty) return saved;
      }
    } catch (_) {}
    return '0000';
  }

  static Future<void> saveParentalPin(String pin) async {
    try {
      final clean = pin.trim();
      if (clean.isNotEmpty) {
        await _parentalPinFile.writeAsString(clean);
      }
    } catch (_) {}
  }

  static Future<List<StreamItem>> loadOfflinePlaylist() async {
    try {
      if (await _offlinePlaylistFile.exists()) {
        final raw = await _offlinePlaylistFile.readAsString();
        return await compute(_decodePlaylistIsolate, raw);
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveOfflinePlaylist(List<StreamItem> items) async {
    try {
      final capped = items.length > 18000 ? items.sublist(0, 18000) : items;
      final encoded = await compute(_encodePlaylistIsolate, capped);
      await _offlinePlaylistFile.writeAsString(encoded);
    } catch (_) {}
  }

  static Future<Set<String>> loadFavorites() async {
    try {
      if (await _favoritesFile.exists()) {
        final list = jsonDecode(await _favoritesFile.readAsString()) as List;
        return list.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveFavorites(Set<String> favs) async {
    try {
      await _favoritesFile.writeAsString(jsonEncode(favs.toList()));
    } catch (_) {}
  }

  static Future<List<StreamItem>> loadRecents() async {
    try {
      if (await _recentsFile.exists()) {
        final list = jsonDecode(await _recentsFile.readAsString()) as List;
        return list.map((e) => StreamItem.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveRecents(List<StreamItem> recents) async {
    try {
      await _recentsFile.writeAsString(
        jsonEncode(recents.take(40).map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<Map<String, VodProgressEntry>> loadVodProgressMap() async {
    try {
      if (await _vodProgressFile.exists()) {
        final raw = jsonDecode(await _vodProgressFile.readAsString()) as Map<String, dynamic>;
        return raw.map(
          (k, v) => MapEntry(k, VodProgressEntry.fromJson(v.cast<String, dynamic>())),
        );
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveVodProgressEntry(VodProgressEntry entry) async {
    try {
      final map = await loadVodProgressMap();
      if (entry.progress >= 0.96) {
        map.remove(entry.item.id);
      } else {
        map[entry.item.id] = entry;
      }
      await _vodProgressFile.writeAsString(
        jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (_) {}
  }
}

String _encodePlaylistIsolate(List<StreamItem> items) =>
    jsonEncode(items.map((e) => e.toJson()).toList());

List<StreamItem> _decodePlaylistIsolate(String raw) =>
    (jsonDecode(raw) as List).map((e) => StreamItem.fromJson(e)).toList();

// =============================================================================
// 3. MOTOR DE VÍDEO COMPARTILHADO (BLINDADO — INALTERADO)
// =============================================================================
class _StreamAttempt {
  final String url;
  final VideoFormat? formatHint;
  final Map<String, String> headers;
  final String label;
  final bool resolveRedirectFirst;
  final VideoViewType viewType;

  const _StreamAttempt({
    required this.url,
    this.formatHint,
    required this.headers,
    required this.label,
    this.resolveRedirectFirst = false,
    required this.viewType,
  });
}

class SharedStreamEngine extends ChangeNotifier {
  static final SharedStreamEngine instance = SharedStreamEngine._internal();
  SharedStreamEngine._internal();

  VideoPlayerController? controller;
  StreamItem? currentItem;
  EpgProgramInfo? currentEpg;

  bool isReady = false;
  bool hasError = false;
  bool isRecovering = false;
  bool isFullScreenActive = false;
  String activeFormatLabel = 'SURFACE-TV';
  String lastErrorDetails = '';

  int _opId = 0;
  bool _runtimeFallbackTriggered = false;
  Timer? _watchdogTimer;
  Duration _lastPosition = Duration.zero;
  int _stallCounter = 0;

  void Function(VodProgressEntry entry)? onVodProgressSaved;

  /// Ativa ou desativa o modo de Tela Cheia para isolar a superfície de vídeo única na TV
  void setFullScreenActive(bool active) {
    if (isFullScreenActive != active) {
      isFullScreenActive = active;
      notifyListeners();
    }
  }

  /// Segue redirecionamentos HTTP 301/302/307/308 sem consumir a conexão do vídeo
  Future<String> _resolveRedirectLocationOnly(String rawUrl, Map<String, String> headers) async {
    try {
      Uri currentUri = Uri.parse(rawUrl);
      for (int hop = 0; hop < 4; hop++) {
        final HttpClient hopClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5)
          ..badCertificateCallback = (cert, host, port) => true;

        try {
          if (headers['User-Agent'] != null) {
            hopClient.userAgent = headers['User-Agent'];
          }

          final req = await hopClient.getUrl(currentUri).timeout(const Duration(seconds: 5));
          req.followRedirects = false;
          headers.forEach((k, v) => req.headers.set(k, v));

          final res = await req.close().timeout(const Duration(seconds: 5));
          final code = res.statusCode;

          if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
            final loc = res.headers.value(HttpHeaders.locationHeader);
            if (loc != null && loc.isNotEmpty) {
              currentUri = currentUri.resolve(loc);
              continue;
            }
          }
          break;
        } finally {
          hopClient.close(force: true);
        }
      }
      return currentUri.toString();
    } catch (_) {
      return rawUrl;
    }
  }

  List<_StreamAttempt> _buildAttempts(StreamItem item, {required bool preferAlternate}) {
    final raw = item.url.trim();
    final List<_StreamAttempt> list = [];

    if (item.type == ContentType.live) {
      String tsUrl = raw;
      String m3u8Url = raw;

      if (raw.endsWith('.ts')) {
        m3u8Url = '${raw.substring(0, raw.length - 3)}.m3u8';
      } else if (raw.endsWith('.m3u8')) {
        tsUrl = '${raw.substring(0, raw.length - 5)}.ts';
      } else {
        tsUrl = '$raw.ts';
        m3u8Url = '$raw.m3u8';
      }

      if (!preferAlternate) {
        list.add(_StreamAttempt(
          url: m3u8Url,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'TV-SURFACE (HLS)',
          viewType: VideoViewType.platformView,
        ));
        list.add(_StreamAttempt(
          url: tsUrl,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'TV-SURFACE (TS)',
          resolveRedirectFirst: true,
          viewType: VideoViewType.platformView,
        ));
        list.add(_StreamAttempt(
          url: m3u8Url,
          formatHint: VideoFormat.hls,
          headers: kXciptvHeaders,
          label: 'TEXTURE (HLS)',
          resolveRedirectFirst: true,
          viewType: VideoViewType.textureView,
        ));
        list.add(_StreamAttempt(
          url: tsUrl,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'TEXTURE (TS)',
          viewType: VideoViewType.textureView,
        ));
      } else {
        list.add(_StreamAttempt(
          url: tsUrl,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'TV-SURFACE (TS)',
          resolveRedirectFirst: true,
          viewType: VideoViewType.platformView,
        ));
        list.add(_StreamAttempt(
          url: m3u8Url,
          formatHint: VideoFormat.hls,
          headers: kIptvHeaders,
          label: 'TEXTURE (HLS)',
          resolveRedirectFirst: true,
          viewType: VideoViewType.textureView,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: const {},
          label: 'SURFACE-DIRETO',
          viewType: VideoViewType.platformView,
        ));
      }
    } else {
      if (!preferAlternate) {
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'VOD-SURFACE',
          viewType: VideoViewType.platformView,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'VOD-SURFACE-302',
          resolveRedirectFirst: true,
          viewType: VideoViewType.platformView,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'VOD-TEXTURE',
          resolveRedirectFirst: true,
          viewType: VideoViewType.textureView,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: const {},
          label: 'VOD-NATIVO',
          viewType: VideoViewType.platformView,
        ));
      } else {
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'VOD-TEXTURE',
          resolveRedirectFirst: true,
          viewType: VideoViewType.textureView,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'VOD-SURFACE',
          viewType: VideoViewType.platformView,
        ));
      }
    }

    return list;
  }

  Future<void> openStream(
    StreamItem item, {
    Duration? startPosition,
    bool forceReload = false,
    bool tryHlsFallback = false,
  }) async {
    if (!forceReload &&
        currentItem?.id == item.id &&
        currentItem?.url == item.url &&
        controller != null &&
        isReady &&
        !hasError) {
      if (startPosition != null && item.type != ContentType.live) {
        await controller!.seekTo(startPosition);
      }
      if (!controller!.value.isPlaying) {
        await controller!.play();
      }
      notifyListeners();
      return;
    }

    final int myOp = ++_opId;
    if (!tryHlsFallback) _runtimeFallbackTriggered = false;

    _saveCurrentVodProgressImmediately();
    _watchdogTimer?.cancel();

    currentItem = item;
    isReady = false;
    hasError = false;
    isRecovering = false;
    lastErrorDetails = '';

    final oldController = controller;
    controller = null;
    notifyListeners();

    _fetchMockEpg(item);

    if (oldController != null) {
      try {
        await oldController.pause();
      } catch (_) {}
      try {
        await oldController.dispose();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 450));
    }

    if (myOp != _opId) return;

    final attempts = _buildAttempts(item, preferAlternate: tryHlsFallback);

    for (final attempt in attempts) {
      if (myOp != _opId) return;

      String targetUrl = attempt.url;
      if (attempt.resolveRedirectFirst) {
        targetUrl = await _resolveRedirectLocationOnly(targetUrl, attempt.headers);
        if (myOp != _opId) return;
      }

      final testCtrl = VideoPlayerController.networkUrl(
        Uri.parse(targetUrl),
        httpHeaders: attempt.headers,
        formatHint: attempt.formatHint,
        viewType: attempt.viewType,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      try {
        await testCtrl.initialize().timeout(const Duration(seconds: 12));
        if (myOp != _opId) {
          await testCtrl.dispose().catchError((_) {});
          return;
        }

        if (item.type != ContentType.live &&
            startPosition != null &&
            startPosition.inSeconds > 5) {
          await testCtrl.seekTo(startPosition);
        }

        await testCtrl.setVolume(1.0);
        await testCtrl.play();

        await Future.delayed(const Duration(milliseconds: 400));
        if (myOp != _opId) {
          await testCtrl.dispose().catchError((_) {});
          return;
        }
        if (testCtrl.value.hasError) {
          throw Exception(testCtrl.value.errorDescription ?? 'MediaCodec post-play error');
        }

        controller = testCtrl;
        activeFormatLabel = attempt.label;
        isReady = true;
        hasError = false;
        isRecovering = false;
        lastErrorDetails = '';

        testCtrl.addListener(() {
          if (controller == testCtrl && testCtrl.value.hasError && !hasError) {
            lastErrorDetails = testCtrl.value.errorDescription ?? 'Erro de decodificação de vídeo';
            if (!_runtimeFallbackTriggered && currentItem != null) {
              _runtimeFallbackTriggered = true;
              openStream(currentItem!, forceReload: true, tryHlsFallback: true);
            } else {
              hasError = true;
              isReady = false;
              notifyListeners();
            }
          }
        });

        _startWatchdog();
        notifyListeners();
        return;
      } catch (e) {
        lastErrorDetails = e.toString().replaceAll('PlatformException', '').trim();
        await testCtrl.dispose().catchError((_) {});
        if (myOp != _opId) return;
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    if (myOp == _opId) {
      hasError = true;
      isReady = false;
      notifyListeners();
    }
  }

  void _fetchMockEpg(StreamItem item) {
    if (item.type != ContentType.live) {
      currentEpg = null;
      return;
    }
    final now = DateTime.now();
    final nextHourStr = '${((now.hour + 1) % 24).toString().padLeft(2, '0')}:00';
    currentEpg = EpgProgramInfo(
      nowTitle: '${item.cleanName} • Transmissão Ao Vivo',
      nextTitle: 'A Seguir ($nextHourStr)',
      progress: (now.minute / 60.0).clamp(0.05, 0.95),
    );
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _stallCounter = 0;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final ctrl = controller;
      final item = currentItem;
      if (ctrl == null || item == null || !isReady || !ctrl.value.isPlaying) return;

      if (item.type != ContentType.live && timer.tick % 3 == 0) {
        _saveCurrentVodProgressImmediately();
      }

      if (ctrl.value.position == _lastPosition && ctrl.value.isBuffering) {
        _stallCounter++;
        if (_stallCounter >= 3 && !isRecovering) {
          isRecovering = true;
          notifyListeners();
          if (item.type == ContentType.live && ctrl.value.buffered.isNotEmpty) {
            final liveEdge = ctrl.value.buffered.last.end;
            if (liveEdge > ctrl.value.position + const Duration(seconds: 2)) {
              await ctrl.seekTo(liveEdge);
            }
            await ctrl.play();
          } else {
            await ctrl.pause();
            await Future.delayed(const Duration(milliseconds: 600));
            await ctrl.play();
          }
          isRecovering = false;
          _stallCounter = 0;
          notifyListeners();
        }
      } else {
        _stallCounter = 0;
      }
      _lastPosition = ctrl.value.position;
    });
  }

  void _saveCurrentVodProgressImmediately() {
    final ctrl = controller;
    final item = currentItem;
    if (ctrl == null || item == null || !isReady || item.type == ContentType.live) return;
    final pos = ctrl.value.position.inSeconds;
    final dur = ctrl.value.duration.inSeconds;
    if (pos >= 10 && dur > 30) {
      final entry = VodProgressEntry(
        item: item,
        positionSeconds: pos,
        durationSeconds: dur,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      AppStorage.saveVodProgressEntry(entry);
      onVodProgressSaved?.call(entry);
    }
  }

  void togglePlayPause() {
    if (controller == null || !isReady) return;
    if (controller!.value.isPlaying) {
      controller!.pause();
      _saveCurrentVodProgressImmediately();
    } else {
      controller!.play();
    }
    notifyListeners();
  }

  Future<void> seekRelative(int seconds) async {
    if (controller == null || !isReady) return;
    final target = controller!.value.position + Duration(seconds: seconds);

    Duration finalTarget = target;
    if (finalTarget < Duration.zero) {
      finalTarget = Duration.zero;
    } else if (finalTarget > controller!.value.duration) {
      finalTarget = controller!.value.duration;
    }

    await controller!.seekTo(finalTarget);
    _saveCurrentVodProgressImmediately();
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    _opId++;
    _saveCurrentVodProgressImmediately();
    _watchdogTimer?.cancel();
    final old = controller;
    controller = null;
    currentItem = null;
    currentEpg = null;
    isReady = false;
    hasError = false;
    isRecovering = false;
    notifyListeners();
    if (old != null) {
      try {
        await old.pause();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }
  }
}

// =============================================================================
// 4. SERVIÇO DE CATÁLOGO XTREAM CODES API + M3U (COM UNIFICAÇÃO DE '(L)')
// =============================================================================
class CatalogBundle {
  final List<StreamItem> allItems;
  final List<SeriesGroup> seriesGroups;
  final String resolvedStreamBaseUrl;

  CatalogBundle({
    required this.allItems,
    required this.seriesGroups,
    required this.resolvedStreamBaseUrl,
  });
}

class XtreamCatalogService {
  static String cleanInputUrl(String raw) {
    String s = raw.replaceAll(RegExp(r'\s+'), '').trim();
    while (s.toLowerCase().startsWith('http://http://')) {
      s = s.substring(7);
    }
    while (s.toLowerCase().startsWith('https://https://')) {
      s = s.substring(8);
    }
    if (!s.toLowerCase().startsWith('http://') && !s.toLowerCase().startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/') || s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static Map<String, String>? extractXtreamCredentials({
    required String serverDns,
    required String username,
    required String password,
    String? directM3uUrl,
  }) {
    if (serverDns.trim().isNotEmpty &&
        username.trim().isNotEmpty &&
        password.trim().isNotEmpty) {
      return {
        'dns': cleanInputUrl(serverDns),
        'user': username.trim(),
        'pass': password.trim(),
      };
    }
    if (directM3uUrl != null && directM3uUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(cleanInputUrl(directM3uUrl));
        final u = uri.queryParameters['username'] ?? '';
        final p = uri.queryParameters['password'] ?? '';
        if (u.isNotEmpty && p.isNotEmpty) {
          final portPart = uri.hasPort ? ':${uri.port}' : '';
          return {
            'dns': '${uri.scheme}://${uri.host}$portPart',
            'user': u,
            'pass': p,
          };
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<CatalogBundle?> fetchViaXtreamApi({
    required String dns,
    required String user,
    required String pass,
  }) async {
    try {
      final baseApi =
          '$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';

      String effectiveDns = dns;
      try {
        final infoRes = await http.get(Uri.parse(baseApi), headers: kIptvHeaders).timeout(const Duration(seconds: 8));
        if (infoRes.statusCode == 200) {
          final infoJson = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
          final srv = infoJson['server_info'];
          if (srv is Map) {
            final srvUrl = srv['url']?.toString().trim() ?? '';
            final srvPort = srv['port']?.toString().trim() ?? '';
            final srvProto = srv['server_protocol']?.toString().trim() ?? 'http';
            final inputUri = Uri.tryParse(dns);
            if (inputUri != null && !inputUri.hasPort && srvUrl.isNotEmpty && srvPort.isNotEmpty && srvPort != '80' && srvPort != '443') {
              effectiveDns = '$srvProto://${inputUri.host}:$srvPort';
            }
          }
        }
      } catch (_) {}

      final liveCatFuture = http
          .get(Uri.parse('$baseApi&action=get_live_categories'), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 12));
      final liveStreamsFuture = http
          .get(Uri.parse('$baseApi&action=get_live_streams'), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 20));

      final liveCatRes = await liveCatFuture;
      final liveStreamsRes = await liveStreamsFuture;

      if (liveStreamsRes.statusCode != 200) return null;

      final vodCatFuture = http
          .get(Uri.parse('$baseApi&action=get_vod_categories'), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 12))
          .catchError((_) => http.Response('[]', 200));
      final vodStreamsFuture = http
          .get(Uri.parse('$baseApi&action=get_vod_streams'), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 20))
          .catchError((_) => http.Response('[]', 200));
      final seriesCatFuture = http
          .get(Uri.parse('$baseApi&action=get_series_categories'), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 12))
          .catchError((_) => http.Response('[]', 200));
      final seriesListFuture = http
          .get(Uri.parse('$baseApi&action=get_series'), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 20))
          .catchError((_) => http.Response('[]', 200));

      final results = await Future.wait([
        vodCatFuture,
        vodStreamsFuture,
        seriesCatFuture,
        seriesListFuture,
      ]);

      return await compute(_parseXtreamJsonIsolate, {
        'dns': effectiveDns,
        'user': user,
        'pass': pass,
        'liveCats': utf8.decode(liveCatRes.bodyBytes, allowMalformed: true),
        'liveStreams': utf8.decode(liveStreamsRes.bodyBytes, allowMalformed: true),
        'vodCats': utf8.decode(results[0].bodyBytes, allowMalformed: true),
        'vodStreams': utf8.decode(results[1].bodyBytes, allowMalformed: true),
        'seriesCats': utf8.decode(results[2].bodyBytes, allowMalformed: true),
        'seriesList': utf8.decode(results[3].bodyBytes, allowMalformed: true),
      });
    } catch (_) {
      return null;
    }
  }

  static Future<StreamItem> fetchVodDetails({
    required StreamItem item,
    required String dns,
    required String user,
    required String pass,
  }) async {
    if (item.streamId.isEmpty || dns.isEmpty) return item;
    try {
      final url =
          '$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=get_vod_info&vod_id=${item.streamId}';
      final res = await http.get(Uri.parse(url), headers: kIptvHeaders).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final info = data['info'];
        final movieData = data['movie_data'];
        String? updatedUrl;
        if (movieData is Map) {
          final rawExt = movieData['container_extension']?.toString().replaceAll('.', '').trim() ?? '';
          if (rawExt.isNotEmpty) {
            updatedUrl = '$dns/movie/$user/$pass/${item.streamId}.$rawExt';
          }
        }
        if (info is Map) {
          final plot = info['plot']?.toString() ?? info['description']?.toString() ?? '';
          final cast = info['cast']?.toString() ?? info['actors']?.toString() ?? '';
          final year = info['releasedate']?.toString() ?? info['year']?.toString() ?? '';
          final rating = info['rating']?.toString() ?? item.rating;
          return item.copyWith(
            synopsis: plot,
            cast: cast,
            year: year,
            rating: rating,
            url: updatedUrl,
          );
        }
      }
    } catch (_) {}
    return item;
  }

  static Future<Map<int, List<StreamItem>>> fetchSeriesEpisodes({
    required SeriesGroup series,
    required String dns,
    required String user,
    required String pass,
  }) async {
    if (series.seasons.isNotEmpty) return series.seasons;
    if (series.seriesId.isEmpty || dns.isEmpty) return {};

    try {
      final url =
          '$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&action=get_series_info&series_id=${series.seriesId}';
      final res = await http.get(Uri.parse(url), headers: kIptvHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final episodesMap = data['episodes'];
        final Map<int, List<StreamItem>> parsedSeasons = {};

        if (episodesMap is Map) {
          episodesMap.forEach((seasonKey, epList) {
            final sNum = int.tryParse(seasonKey.toString()) ?? 1;
            if (epList is List) {
              for (final ep in epList) {
                final epId = ep['id']?.toString().trim() ?? '';
                var ext = ep['container_extension']?.toString().replaceAll('.', '').trim() ?? 'mp4';
                if (ext.isEmpty) ext = 'mp4';
                final epNum = int.tryParse(ep['episode_num']?.toString() ?? '1') ?? 1;
                final epTitle = ep['title']?.toString() ?? 'Episódio $epNum';
                if (epId.isNotEmpty) {
                  parsedSeasons.putIfAbsent(sNum, () => []).add(
                        StreamItem(
                          id: 'ep_$epId',
                          streamId: epId,
                          tvgId: '',
                          name: epTitle,
                          cleanName: epTitle,
                          seriesName: series.title,
                          seasonNumber: sNum,
                          episodeNumber: epNum,
                          qualityTag: series.qualityTag,
                          group: series.group,
                          logo: series.logo,
                          url: '$dns/series/$user/$pass/$epId.$ext',
                          type: ContentType.series,
                          isAdult: series.isAdult,
                          synopsis: series.synopsis,
                        ),
                      );
                }
              }
            }
          });
        }
        return parsedSeasons;
      }
    } catch (_) {}
    return {};
  }
}

CatalogBundle _parseXtreamJsonIsolate(Map<String, String> payload) {
  final dns = payload['dns']!;
  final user = payload['user']!;
  final pass = payload['pass']!;

  Map<String, String> parseCatMap(String raw) {
    final map = <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final c in decoded) {
          final id = c['category_id']?.toString() ?? '';
          final name = c['category_name']?.toString() ?? 'Geral';
          if (id.isNotEmpty) map[id] = name;
        }
      }
    } catch (_) {}
    return map;
  }

  final liveCatMap = parseCatMap(payload['liveCats'] ?? '[]');
  final vodCatMap = parseCatMap(payload['vodCats'] ?? '[]');
  final seriesCatMap = parseCatMap(payload['seriesCats'] ?? '[]');
  final qualityRegex = RegExp(r'\b(4K|UHD|FHD|1080P|HD|720P|SD)\b', caseSensitive: false);

  bool checkAdult(String group, String name, dynamic isAdultFlag) {
    if (isAdultFlag?.toString() == '1') return true;
    final g = group.toLowerCase();
    final n = name.toLowerCase();
    return g.contains('adult') ||
        g.contains('+18') ||
        g.contains('18+') ||
        g.contains('xxx') ||
        g.contains('erot') ||
        n.contains('xxx') ||
        n.contains('+18');
  }

  String extractQuality(String name) {
    final m = qualityRegex.firstMatch(name);
    if (m == null) return 'HD';
    return m
        .group(1)!
        .toUpperCase()
        .replaceAll('UHD', '4K')
        .replaceAll('1080P', 'FHD')
        .replaceAll('720P', 'HD');
  }

  final List<StreamItem> rawItems = [];
  final List<SeriesGroup> seriesGroups = [];

  try {
    final liveList = jsonDecode(payload['liveStreams'] ?? '[]');
    if (liveList is List) {
      for (final s in liveList) {
        final sid = s['stream_id']?.toString().trim() ?? '';
        if (sid.isEmpty) continue;
        final name = s['name']?.toString() ?? 'Canal $sid';
        final group = liveCatMap[s['category_id']?.toString() ?? ''] ?? 'Canais';
        rawItems.add(
          StreamItem(
            id: 'live_$sid',
            streamId: sid,
            tvgId: s['epg_channel_id']?.toString() ?? '',
            name: name,
            cleanName: name.replaceAll(qualityRegex, '').trim(),
            seriesName: '',
            seasonNumber: 1,
            episodeNumber: 1,
            qualityTag: extractQuality(name),
            group: group,
            logo: s['stream_icon']?.toString() ?? '',
            url: '$dns/live/$user/$pass/$sid.ts',
            type: ContentType.live,
            isAdult: checkAdult(group, name, s['is_adult']),
          ),
        );
      }
    }
  } catch (_) {}

  try {
    final vodList = jsonDecode(payload['vodStreams'] ?? '[]');
    if (vodList is List) {
      for (final v in vodList) {
        final sid = v['stream_id']?.toString().trim() ?? '';
        if (sid.isEmpty) continue;
        final name = v['name']?.toString() ?? 'Filme $sid';
        final group = vodCatMap[v['category_id']?.toString() ?? ''] ?? 'Filmes';
        var ext = v['container_extension']?.toString().replaceAll('.', '').trim() ?? 'mp4';
        if (ext.isEmpty) ext = 'mp4';
        final rating = v['rating']?.toString() ?? '8.2';
        rawItems.add(
          StreamItem(
            id: 'vod_$sid',
            streamId: sid,
            tvgId: '',
            name: name,
            cleanName: name,
            seriesName: '',
            seasonNumber: 1,
            episodeNumber: 1,
            qualityTag: extractQuality(name),
            group: group,
            logo: v['stream_icon']?.toString() ?? '',
            url: '$dns/movie/$user/$pass/$sid.$ext',
            type: ContentType.movie,
            isAdult: checkAdult(group, name, v['is_adult']),
            rating: rating.isNotEmpty ? rating : '8.2',
          ),
        );
      }
    }
  } catch (_) {}

  try {
    final sList = jsonDecode(payload['seriesList'] ?? '[]');
    if (sList is List) {
      for (final sr in sList) {
        final sid = sr['series_id']?.toString().trim() ?? '';
        if (sid.isEmpty) continue;
        final title = sr['name']?.toString() ?? 'Série $sid';
        final group = seriesCatMap[sr['category_id']?.toString() ?? ''] ?? 'Séries';
        final plot = sr['plot']?.toString() ?? '';
        final cast = sr['cast']?.toString() ?? '';
        final year = sr['releaseDate']?.toString() ?? '';
        final rating = sr['rating']?.toString() ?? '8.5';
        seriesGroups.add(
          SeriesGroup(
            id: 'series_$sid',
            seriesId: sid,
            title: title,
            group: group,
            logo: sr['cover']?.toString() ?? '',
            synopsis: plot.isNotEmpty
                ? plot
                : 'Selecione para explorar as temporadas e episódios desta série.',
            cast: cast,
            year: year,
            rating: rating.isNotEmpty ? rating : '8.5',
            qualityTag: extractQuality(title),
            isAdult: checkAdult(group, title, null),
            seasons: {},
          ),
        );
      }
    }
  } catch (_) {}

  // Unifica automaticamente filmes Dublados e Legendados (L)
  final unifiedItems = unifyMoviesByLanguage(rawItems);

  return CatalogBundle(
    allItems: unifiedItems,
    seriesGroups: seriesGroups,
    resolvedStreamBaseUrl: dns,
  );
}

// =============================================================================
// 5. PARSER M3U EM BACKGROUND (COM UNIFICAÇÃO DE FILMES DUBLADOS / LEGENDADOS)
// =============================================================================
List<StreamItem> parseM3UAdvanced(String raw) {
  final List<StreamItem> result = [];
  final lines = const LineSplitter().convert(raw);
  String name = '', group = 'Canais', logo = '', tvgId = '';
  int counter = 0;

  final groupRegex = RegExp(r'group-title="([^"]*)"', caseSensitive: false);
  final logoRegex = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);
  final qualityRegex = RegExp(r'\b(4K|UHD|FHD|1080P|HD|720P|SD)\b', caseSensitive: false);
  final sePattern = RegExp(r'[sS](\d{1,2})\s*[eE](\d{1,3})', caseSensitive: false);

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#EXTINF:')) {
      group = groupRegex.firstMatch(trimmed)?.group(1)?.trim() ?? 'Geral';
      if (group.isEmpty) group = 'Geral';
      logo = logoRegex.firstMatch(trimmed)?.group(1)?.trim() ?? '';
      name = trimmed.contains(',')
          ? trimmed.substring(trimmed.lastIndexOf(',') + 1).trim()
          : 'Canal ${counter + 1}';
    } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      counter++;
      final lowerUrl = trimmed.toLowerCase();
      final lowerGroup = group.toLowerCase();

      ContentType type = ContentType.live;
      final seMatch = sePattern.firstMatch(name);
      if (lowerUrl.contains('/series/') || lowerGroup.contains('série') || seMatch != null) {
        type = ContentType.series;
      } else if (lowerUrl.contains('/movie/') ||
          lowerGroup.contains('filme') ||
          lowerUrl.endsWith('.mp4') ||
          lowerUrl.endsWith('.mkv') ||
          lowerUrl.endsWith('.avi')) {
        type = ContentType.movie;
      }

      String quality = 'HD';
      final qMatch = qualityRegex.firstMatch(name);
      if (qMatch != null) {
        quality = qMatch
            .group(1)!
            .toUpperCase()
            .replaceAll('UHD', '4K')
            .replaceAll('1080P', 'FHD')
            .replaceAll('720P', 'HD');
      }

      final cleanName = name
          .replaceAll(qualityRegex, '')
          .replaceAll(RegExp(r'[\[\]\(\)\-\|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      int seasonNum = 1, episodeNum = 1;
      String extractedSeriesName = cleanName;

      if (type == ContentType.series && seMatch != null) {
        seasonNum = int.tryParse(seMatch.group(1) ?? '1') ?? 1;
        episodeNum = int.tryParse(seMatch.group(2) ?? '1') ?? 1;
        extractedSeriesName =
            name.substring(0, seMatch.start).replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
      }

      final isAdult = lowerGroup.contains('adult') ||
          lowerGroup.contains('+18') ||
          lowerGroup.contains('18+') ||
          lowerGroup.contains('xxx') ||
          lowerGroup.contains('erot') ||
          name.toLowerCase().contains('xxx') ||
          name.toLowerCase().contains('+18');

      result.add(
        StreamItem(
          id: '${counter}_${trimmed.hashCode}',
          streamId: '',
          tvgId: tvgId,
          name: name,
          cleanName: cleanName,
          seriesName: extractedSeriesName,
          seasonNumber: seasonNum,
          episodeNumber: episodeNum,
          qualityTag: quality,
          group: group,
          logo: logo,
          url: trimmed,
          type: type,
          isAdult: isAdult,
        ),
      );
      name = '';
      group = 'Geral';
      logo = '';
      tvgId = '';
    }
  }

  return unifyMoviesByLanguage(result);
}

List<SeriesGroup> groupSeriesItems(List<StreamItem> items) {
  final Map<String, Map<int, List<StreamItem>>> map = {};
  final Map<String, StreamItem> firstMap = {};
  for (final i in items) {
    final key = i.seriesName.toLowerCase();
    firstMap.putIfAbsent(key, () => i);
    map.putIfAbsent(key, () => {}).putIfAbsent(i.seasonNumber, () => []).add(i);
  }
  return map.entries.map((e) {
    final ref = firstMap[e.key]!;
    final seasons = e.value.map((k, v) {
      v.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return MapEntry(k, v);
    });
    return SeriesGroup(
      id: 's_${e.key.hashCode}',
      title: ref.seriesName,
      group: ref.group,
      logo: ref.logo,
      qualityTag: ref.qualityTag,
      isAdult: ref.isAdult,
      seasons: seasons,
    );
  }).toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}

Future<void> applyDeviceOrientation(DeviceMode mode) async {
  if (mode == DeviceMode.tv) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

// =============================================================================
// 6. TRANSIÇÕES DE NAVEGAÇÃO FLUIDAS E EXPANSÃO DO PLAYER
// =============================================================================
Route<T> createSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Animação fluida de expansão da janela de pré-visualização até a Tela Cheia (e encolhimento ao voltar)
Route<T> createPlayerExpandRoute<T>(Widget page, {required DeviceMode mode}) {
  final originAlignment = mode == DeviceMode.tv
      ? const Alignment(0.74, -0.24) // Ancorado na janela de pré-visualização à direita na TV
      : const Alignment(0.0, -0.68); // Ancorado na pré-visualização superior no Celular

  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 290),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final scaleCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInOutCubic,
      );
      final fadeCurve = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
        reverseCurve: const Interval(0.15, 1.0, curve: Curves.easeIn),
      );

      return FadeTransition(
        opacity: fadeCurve,
        child: ScaleTransition(
          alignment: originAlignment,
          scale: Tween<double>(begin: 0.30, end: 1.0).animate(scaleCurve),
          child: ClipRRect(
            borderRadius: Tween<BorderRadius>(
              begin: BorderRadius.circular(18),
              end: BorderRadius.zero,
            ).evaluate(scaleCurve),
            child: child,
          ),
        ),
      );
    },
  );
}
