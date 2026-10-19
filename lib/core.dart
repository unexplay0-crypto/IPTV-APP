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
// 1. MODELOS DE DADOS (CANAIS, FILMES, SÉRIES, PROGRESSO E EPG)
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
  });

  StreamItem copyWith({
    String? synopsis,
    String? rating,
    String? year,
    String? cast,
    String? url,
  }) {
    return StreamItem(
      id: id,
      streamId: streamId,
      tvgId: tvgId,
      name: name,
      cleanName: cleanName,
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
// 2. ARMAZENAMENTO OFFLINE-FIRST E PERSISTÊNCIA EM DISCO
// =============================================================================
class AppStorage {
  static String get _tmp => Directory.systemTemp.path;
  static File get _sessionFile => File('$_tmp/unex_v21_session.json');
  static File get _deviceFile => File('$_tmp/unex_v21_device.json');
  static File get _vodProgressFile => File('$_tmp/unex_v21_vod_progress.json');
  static File get _favoritesFile => File('$_tmp/unex_v21_favorites.json');
  static File get _recentsFile => File('$_tmp/unex_v21_recents.json');
  static File get _offlinePlaylistFile => File('$_tmp/unex_v21_offline_playlist.json');
  static File get _parentalPinFile => File('$_tmp/unex_v21_parental_pin.txt');

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
// 3. MOTOR DE VÍDEO COMPARTILHADO (PADRÃO XCIPTV / IPTV SMARTERS)
// =============================================================================
class _StreamAttempt {
  final String url;
  final VideoFormat? formatHint;
  final Map<String, String> headers;
  final String label;
  final bool resolveRedirectFirst;

  const _StreamAttempt({
    required this.url,
    this.formatHint,
    required this.headers,
    required this.label,
    this.resolveRedirectFirst = false,
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
  String activeFormatLabel = 'AUTO';
  String lastErrorDetails = '';

  int _opId = 0;
  Timer? _watchdogTimer;
  Duration _lastPosition = Duration.zero;
  int _stallCounter = 0;

  void Function(VodProgressEntry entry)? onVodProgressSaved;

  /// Segue redirecionamentos HTTP 301/302/307/308 de balanceadores IPTV sem baixar o corpo do vídeo
  Future<String> _resolveRedirectLocationOnly(String rawUrl, Map<String, String> headers) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) => true;
      if (headers['User-Agent'] != null) {
        client.userAgent = headers['User-Agent'];
      }

      Uri currentUri = Uri.parse(rawUrl);
      for (int hop = 0; hop < 4; hop++) {
        final req = await client.getUrl(currentUri).timeout(const Duration(seconds: 5));
        req.followRedirects = false;
        headers.forEach((k, v) => req.headers.set(k, v));

        final res = await req.close().timeout(const Duration(seconds: 5));
        final code = res.statusCode;

        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
          final loc = res.headers.value(HttpHeaders.locationHeader);
          // Fecha o socket do painel imediatamente após ler o cabeçalho Location
          client.close(force: true);
          client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..badCertificateCallback = (cert, host, port) => true;
          if (loc != null && loc.isNotEmpty) {
            currentUri = currentUri.resolve(loc);
            continue;
          }
        }
        // Fecha imediatamente para não consumir conexão no servidor de mídia
        client.close(force: true);
        break;
      }
      return currentUri.toString();
    } catch (_) {
      return rawUrl;
    } finally {
      client?.close(force: true);
    }
  }

  List<_StreamAttempt> _buildAttempts(StreamItem item, {required bool preferAlternate}) {
    final raw = item.url.trim();
    final List<_StreamAttempt> list = [];

    if (item.type == ContentType.live) {
      String tsUrl = raw;
      String m3u8Url = raw;
      String shortTsUrl = raw;

      if (raw.endsWith('.ts')) {
        m3u8Url = '${raw.substring(0, raw.length - 3)}.m3u8';
      } else if (raw.endsWith('.m3u8')) {
        tsUrl = '${raw.substring(0, raw.length - 5)}.ts';
      } else {
        tsUrl = '$raw.ts';
        m3u8Url = '$raw.m3u8';
      }

      // Formato curto estilo XCIPTV (sem /live/ no caminho) caso o servidor use rota direta
      if (tsUrl.contains('/live/')) {
        shortTsUrl = tsUrl.replaceFirst('/live/', '/');
      }

      if (!preferAlternate) {
        // 1. HLS (.m3u8) com auto-detecção (Padrão mais estável para ExoPlayer em Smart TVs)
        list.add(_StreamAttempt(
          url: m3u8Url,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'HLS-AUTO',
        ));
        // 2. MPEG-TS (.ts) com resolução de redirecionamento 302 e User-Agent VLC
        list.add(_StreamAttempt(
          url: tsUrl,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'MPEG-TS',
          resolveRedirectFirst: true,
        ));
        // 3. HLS com dica explícita VideoFormat.hls e User-Agent XCIPTV
        list.add(_StreamAttempt(
          url: m3u8Url,
          formatHint: VideoFormat.hls,
          headers: kXciptvHeaders,
          label: 'HLS-FORÇADO',
          resolveRedirectFirst: true,
        ));
        // 4. Rota curta sem /live/
        if (shortTsUrl != tsUrl) {
          list.add(_StreamAttempt(
            url: shortTsUrl,
            formatHint: null,
            headers: kIptvHeaders,
            label: 'DIRETO',
          ));
        }
      } else {
        // Ordem invertida quando o usuário clica em "Alternar Formato (TS/HLS)"
        list.add(_StreamAttempt(
          url: tsUrl,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'MPEG-TS',
          resolveRedirectFirst: true,
        ));
        list.add(_StreamAttempt(
          url: m3u8Url,
          formatHint: VideoFormat.hls,
          headers: kIptvHeaders,
          label: 'HLS',
          resolveRedirectFirst: true,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: const {},
          label: 'NATIVO',
        ));
      }
    } else {
      // Filmes e Séries (VOD)
      if (!preferAlternate) {
        // 1. Conexão direta padrão Smarters
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kIptvHeaders,
          label: 'VOD-DIRETO',
        ));
        // 2. Resolução de redirecionamento 302 (Balanceador VOD) + User-Agent VLC
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'VOD-302',
          resolveRedirectFirst: true,
        ));
        // 3. Sem cabeçalhos customizados
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: const {},
          label: 'VOD-NATIVO',
        ));
      } else {
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: kVlcHeaders,
          label: 'VOD-302',
          resolveRedirectFirst: true,
        ));
        list.add(_StreamAttempt(
          url: raw,
          formatHint: null,
          headers: const {},
          label: 'VOD-NATIVO',
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

    // Libera 100% do decoder de hardware e da conexão anterior antes de abrir o novo stream
    if (oldController != null) {
      try {
        await oldController.pause();
      } catch (_) {}
      try {
        await oldController.dispose();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
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
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      try {
        await testCtrl.initialize().timeout(const Duration(seconds: 12));
        if (myOp != _opId) {
          await testCtrl.dispose().catchError((_) {});
          return;
        }

        controller = testCtrl;
        activeFormatLabel = attempt.label;

        if (item.type != ContentType.live &&
            startPosition != null &&
            startPosition.inSeconds > 5) {
          await testCtrl.seekTo(startPosition);
        }

        await testCtrl.setVolume(1.0);
        await testCtrl.play();

        isReady = true;
        hasError = false;
        isRecovering = false;
        lastErrorDetails = '';
        _startWatchdog();
        notifyListeners();
        return;
      } catch (e) {
        lastErrorDetails = e.toString().replaceAll('PlatformException', '').trim();
        await testCtrl.dispose().catchError((_) {});
        if (myOp != _opId) return;
        await Future.delayed(const Duration(milliseconds: 250));
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

  /// Para imediatamente qualquer pré-visualização ativa e libera a conexão no servidor IPTV
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
// 4. SERVIÇO DE CATÁLOGO XTREAM CODES API (COM LEITURA DE SERVER_INFO) + M3U
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

      // 1. Consulta server_info para descobrir a URL/Porta oficial de streaming caso o DNS não tenha porta explícita
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

  final List<StreamItem> allItems = [];
  final List<SeriesGroup> seriesGroups = [];

  // 1. Canais Ao Vivo
  try {
    final liveList = jsonDecode(payload['liveStreams'] ?? '[]');
    if (liveList is List) {
      for (final s in liveList) {
        final sid = s['stream_id']?.toString().trim() ?? '';
        if (sid.isEmpty) continue;
        final name = s['name']?.toString() ?? 'Canal $sid';
        final group = liveCatMap[s['category_id']?.toString() ?? ''] ?? 'Canais';
        allItems.add(
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

  // 2. Filmes (VOD) com extensão higienizada
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
        allItems.add(
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

  // 3. Séries
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

  return CatalogBundle(
    allItems: allItems,
    seriesGroups: seriesGroups,
    resolvedStreamBaseUrl: dns,
  );
}

// =============================================================================
// 5. PARSER M3U EM BACKGROUND (FALLBACK PARA LINKS M3U ESTÁTICOS)
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
  return result;
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

Route<T> createSmoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
