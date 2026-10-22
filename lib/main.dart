import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'core.dart';
import 'widgets.dart';
import 'tv_screen.dart';
import 'mobile_screen.dart';
import 'player_screen.dart';
import 'ativacao_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UnexVisionApp());
}

class UnexVisionApp extends StatelessWidget {
  const UnexVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      child: MaterialApp(
        title: 'UNEX PLAY',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF07090E),
          primaryColor: const Color(0xFF00E5FF),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            secondary: Color(0xFF0088FF),
          ),
        ),
        home: const UnexRootController(),
      ),
    );
  }
}

// ===========================================================================
// PARSER M3U EM ISOLATE (100% COMPATÍVEL COM LIB/CORE.DART)
// ===========================================================================
List<StreamItem> _parseM3uInBackground(String rawContent) {
  final lines = rawContent.split(RegExp(r'\r?\n'));
  final List<StreamItem> rawItems = [];

  String currentName = '';
  String currentLogo = '';
  String currentGroup = 'Geral';

  final regLogo = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false);
  final regGroup = RegExp(r'group-title="([^"]*)"', caseSensitive: false);
  final regQuality = RegExp(r'\b(4K|UHD|FHD|1080P|HD|720P|SD|H265|HEVC)\b', caseSensitive: false);
  final regAdult = RegExp(r'\b(XXX|ADULTO|ADULT|\+18|18\+|PORN|SEXO|EROTICO)\b', caseSensitive: false);
  final regSeries = RegExp(r'\bS(\d{1,2})\s*E(\d{1,3})\b|\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false);

  int indexCounter = 0;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF:')) {
      final logoMatch = regLogo.firstMatch(line);
      final groupMatch = regGroup.firstMatch(line);

      currentLogo = logoMatch != null ? logoMatch.group(1)!.trim() : '';
      currentGroup = groupMatch != null && groupMatch.group(1)!.trim().isNotEmpty
          ? groupMatch.group(1)!.trim()
          : 'Geral';

      final commaIndex = line.lastIndexOf(',');
      currentName = commaIndex != -1 ? line.substring(commaIndex + 1).trim() : 'Canal ${indexCounter + 1}';
    } else if (!line.startsWith('#') && (line.startsWith('http://') || line.startsWith('https://'))) {
      if (currentName.isEmpty) {
        currentName = 'Stream ${indexCounter + 1}';
      }

      final url = line;
      final lowerUrl = url.toLowerCase();
      final lowerGroup = currentGroup.toLowerCase();

      ContentType type = ContentType.live;
      // URL é a fonte da verdade: .ts ou /live/ = sempre canal ao vivo (ignora nome do grupo)
      final bool isLiveUrl = lowerUrl.contains('/live/') || lowerUrl.endsWith('.ts');
      if (!isLiveUrl) {
        if (lowerUrl.contains('/series/') ||
            regSeries.hasMatch(currentName) ||
            lowerGroup.contains('série') ||
            lowerGroup.contains('serie') ||
            lowerGroup.contains('novela')) {
          type = ContentType.series;
        } else if (lowerUrl.contains('/movie/') ||
            lowerUrl.endsWith('.mp4') ||
            lowerUrl.endsWith('.mkv') ||
            lowerGroup.contains('filme') ||
            lowerGroup.contains('vod') ||
            lowerGroup.contains('cinema') ||
            lowerGroup.contains('coletânea') ||
            lowerGroup.contains('lançamento')) {
          type = ContentType.movie;
        }
      }

      final qMatch = regQuality.firstMatch(currentName) ?? regQuality.firstMatch(currentGroup);
      final qualityTag = qMatch != null ? qMatch.group(1)!.toUpperCase() : 'HD';

      final isAdult = regAdult.hasMatch(currentGroup) || regAdult.hasMatch(currentName);
      final itemId = '${type.name}_${currentName.hashCode}_${url.hashCode}_$indexCounter';
      indexCounter++;

      rawItems.add(
        StreamItem(
          id: itemId,
          name: currentName,
          url: url,
          logo: currentLogo,
          group: currentGroup,
          type: type,
          qualityTag: qualityTag,
          isAdult: isAdult,
        ),
      );

      currentName = '';
      currentLogo = '';
      currentGroup = 'Geral';
    }
  }

  return rawItems;
}

// ===========================================================================
// CONTROLADOR PRINCIPAL (LOGIN, ESTADO, FAVORITOS E TRANSIÇÃO FLUIDA)
// ===========================================================================
class UnexRootController extends StatefulWidget {
  const UnexRootController({super.key});

  @override
  State<UnexRootController> createState() => _UnexRootControllerState();
}

class _UnexRootControllerState extends State<UnexRootController> {
  static const String _kPrefM3uUrl = 'unex_saved_m3u_url_v1';
  static const String _kPrefDns = 'unex_saved_dns_v1';
  static const String _kPrefUser = 'unex_saved_user_v1';
  static const String _kPrefPass = 'unex_saved_pass_v1';
  static const String _kPrefActivatedByCode = 'unex_activated_by_code_v1';
  static const String _kPrefDeviceMode = 'unex_device_mode_v1';
  static const String _kPrefFavorites = 'unex_favorites_v2';
  static const String _kPrefHistory = 'unex_history_v1';
  static const String _kPrefProgress = 'unex_watch_progress_v1';

  DeviceMode _deviceMode = DeviceMode.tv;
  bool _isCheckingBoot = true;
  bool _isLoggedIn = false;
  bool _isLoadingPlaylist = false;
  String? _loginError;

  bool _useDirectM3uLink = false;
  bool _forceTraditionalLogin = false;
  final TextEditingController _dnsController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _m3uController = TextEditingController();

  List<StreamItem> _allItems = [];
  List<SeriesGroup> _allSeriesGroups = [];

  int _activeSection = 0;
  String _selectedCategory = 'Todas';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  StreamItem? _selectedLiveChannel;
  Set<String> _favorites = {};
  List<String> _historyIds = [];
  Map<String, double> _watchProgress = {};
  bool _isAdultUnlocked = false;

  @override
  void initState() {
    super.initState();
    _initializeBoot();
  }

  @override
  void dispose() {
    _dnsController.dispose();
    _userController.dispose();
    _passController.dispose();
    _m3uController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeBoot() async {
    final savedMode = await LocalAppStorage.getString(_kPrefDeviceMode);
    if (savedMode == 'mobile') {
      _deviceMode = DeviceMode.mobile;
    } else {
      _deviceMode = DeviceMode.tv;
    }
    applyDeviceOrientation(_deviceMode);

    _favorites = (await LocalAppStorage.getStringList(_kPrefFavorites)).toSet();
    _historyIds = await LocalAppStorage.getStringList(_kPrefHistory);

    final savedProgressList = await LocalAppStorage.getStringList(_kPrefProgress);
    final Map<String, double> progMap = {};
    for (final entry in savedProgressList) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        final val = double.tryParse(parts[1]);
        if (val != null) progMap[parts[0]] = val;
      }
    }
    _watchProgress = progMap;

    final savedDns = (await LocalAppStorage.getString(_kPrefDns)) ?? '';
    final savedUser = (await LocalAppStorage.getString(_kPrefUser)) ?? '';
    final savedPass = (await LocalAppStorage.getString(_kPrefPass)) ?? '';
    final savedM3u = (await LocalAppStorage.getString(_kPrefM3uUrl)) ?? '';
    final activatedByCode = (await LocalAppStorage.getBool(_kPrefActivatedByCode)) ?? false;

    _dnsController.text = savedDns;
    _userController.text = savedUser;
    _passController.text = savedPass;
    if (!activatedByCode) {
      _m3uController.text = savedM3u;
    }

    if (savedM3u.isNotEmpty) {
      // 1) Tenta cache offline primeiro (inicio instantaneo, sem tela de login)
      bool cacheHit = false;
      try {
        final cached = await AppStorage.loadOfflinePlaylist();
        if (cached.isNotEmpty) {
          final cachedGroups = _buildSeriesGroups(cached);
          final firstLiveCached = cached.cast<StreamItem?>().firstWhere(
                (i) => i != null && i.type == ContentType.live && !i.isAdult,
                orElse: () => null,
              );
          if (mounted) {
            setState(() {
              _allItems = cached;
              _allSeriesGroups = cachedGroups;
              _selectedLiveChannel = firstLiveCached;
              _isLoggedIn = true;
              _isCheckingBoot = false;
            });
          }
          if (firstLiveCached != null) {
            SharedStreamEngine.instance.openStream(firstLiveCached);
          }
          cacheHit = true;
        }
      } catch (_) {}

      // 2) Atualiza em segundo plano (silencioso) com a versao online
      unawaited(_loadPlaylistFromUrl(
        savedM3u,
        fromActivationCode: activatedByCode,
        silent: cacheHit,
      ));

      if (!cacheHit) {
        setState(() => _isCheckingBoot = false);
      }
    } else {
      setState(() => _isCheckingBoot = false);
    }
  }

  void _setDeviceMode(DeviceMode mode) async {
    setState(() => _deviceMode = mode);
    applyDeviceOrientation(mode);
    await LocalAppStorage.setString(
      _kPrefDeviceMode,
      mode == DeviceMode.mobile ? 'mobile' : 'tv',
    );
  }

  Future<void> _loadPlaylistFromUrl(
    String rawUrl, {
    bool fromActivationCode = false,
    bool silent = false,
  }) async {
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) {
      if (!silent) setState(() => _loginError = 'Informe os dados de acesso para continuar.');
      return;
    }

    if (!silent) {
      setState(() {
        _isLoadingPlaylist = true;
        _loginError = null;
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse(cleanUrl),
            headers: const {'User-Agent': 'IPTVSmartersPlayer'},
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (!body.contains('#EXTM3U') && !body.contains('#EXTINF')) {
          if (!silent) {
            setState(() {
              _isLoadingPlaylist = false;
              _loginError = 'Lista inválida ou credenciais incorretas.';
            });
          }
          return;
        }

        final parsedItems = await compute(_parseM3uInBackground, body);
        if (parsedItems.isEmpty) {
          if (!silent) {
            setState(() {
              _isLoadingPlaylist = false;
              _loginError = 'Nenhum canal ou filme encontrado nesta lista.';
            });
          }
          return;
        }

        final seriesGroups = _buildSeriesGroups(parsedItems);

        // Salva lista em cache offline para inicio rapido nas proximas vezes
        await AppStorage.saveOfflinePlaylist(parsedItems);

        await LocalAppStorage.setString(_kPrefM3uUrl, cleanUrl);
        await LocalAppStorage.setBool(_kPrefActivatedByCode, fromActivationCode);
        if (!fromActivationCode && !_useDirectM3uLink) {
          await LocalAppStorage.setString(_kPrefDns, _dnsController.text.trim());
          await LocalAppStorage.setString(_kPrefUser, _userController.text.trim());
          await LocalAppStorage.setString(_kPrefPass, _passController.text.trim());
        }

        final firstLive = parsedItems.cast<StreamItem?>().firstWhere(
              (i) => i != null && i.type == ContentType.live && !i.isAdult,
              orElse: () => null,
            );

        if (!mounted) return;
        setState(() {
          _allItems = parsedItems;
          _allSeriesGroups = seriesGroups;
          _activeSection = 0;
          _selectedCategory = 'Todas';
          _selectedLiveChannel = firstLive;
          _isLoggedIn = true;
          _isLoadingPlaylist = false;
          _loginError = null;
        });

        if (firstLive != null) {
          SharedStreamEngine.instance.openStream(firstLive);
        }
      } else {
        if (!silent) {
          setState(() {
            _isLoadingPlaylist = false;
            _loginError = 'Erro ao conectar no servidor (Código ${response.statusCode}).';
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _isLoadingPlaylist = false;
          _loginError = 'Não foi possível carregar a lista. Verifique sua conexão e dados.';
        });
      }
    }
  }

  Future<void> _handleTraditionalLogin() async {
    if (_useDirectM3uLink) {
      await _loadPlaylistFromUrl(_m3uController.text, fromActivationCode: false);
      return;
    }

    String dns = _dnsController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (dns.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _loginError = 'Preencha Servidor/DNS, Usuário e Senha.');
      return;
    }

    if (!dns.startsWith('http://') && !dns.startsWith('https://')) {
      dns = 'http://$dns';
    }
    if (dns.endsWith('/')) {
      dns = dns.substring(0, dns.length - 1);
    }

    final generatedM3uUrl =
        '$dns/get.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}&type=m3u_plus&output=ts';

    await _loadPlaylistFromUrl(generatedM3uUrl, fromActivationCode: false);
  }

  List<SeriesGroup> _buildSeriesGroups(List<StreamItem> items) {
    final seriesItems = items.where((i) => i.type == ContentType.series).toList();
    final Map<String, Map<int, List<StreamItem>>> grouped = {};
    final Map<String, Map<String, int>> logoVotes = {};
    final Map<String, String> groups = {};
    final Map<String, String> qualities = {};
    final Map<String, bool> adults = {};

    final regEp = RegExp(
      r'^(.*?)\s*(?:S(\d{1,2})\s*E(\d{1,3})|(\d{1,2})x(\d{1,3})|Temporada\s*(\d{1,2}).*?Ep(?:is[oó]dio)?\s*(\d{1,3}))',
      caseSensitive: false,
    );

    for (final ep in seriesItems) {
      String seriesTitle = ep.name;
      int seasonNum = 1;

      final match = regEp.firstMatch(ep.name);
      if (match != null) {
        final rawTitle = (match.group(1) ?? '').replaceAll(RegExp(r'[-:–]+$'), '').trim();
        if (rawTitle.isNotEmpty) seriesTitle = rawTitle;
        final sStr = match.group(2) ?? match.group(4) ?? match.group(6) ?? '1';
        seasonNum = int.tryParse(sStr) ?? 1;
      } else {
        seriesTitle = ep.name.replaceAll(RegExp(r'\s*Ep\.?\s*\d+.*$', caseSensitive: false), '').trim();
      }

      grouped.putIfAbsent(seriesTitle, () => {});
      grouped[seriesTitle]!.putIfAbsent(seasonNum, () => []).add(ep);

      if (ep.logo.isNotEmpty) {
        final votes = logoVotes.putIfAbsent(seriesTitle, () => <String, int>{});
        votes[ep.logo] = (votes[ep.logo] ?? 0) + 1;
      }
      groups.putIfAbsent(seriesTitle, () => ep.group);
      qualities.putIfAbsent(seriesTitle, () => ep.qualityTag);
      adults[seriesTitle] = (adults[seriesTitle] ?? false) || ep.isAdult;
    }

    return grouped.entries.map<SeriesGroup>((entry) {
      final sTitle = entry.key;
      return SeriesGroup(
        id: 'series_${sTitle.hashCode}',
        title: sTitle,
        logo: () {
          String best = '';
          int bestCount = 0;
          logoVotes[sTitle]?.forEach((l, c) {
            if (c > bestCount) {
              bestCount = c;
              best = l;
            }
          });
          return best;
        }(),
        group: groups[sTitle] ?? 'Séries',
        qualityTag: qualities[sTitle] ?? 'HD',
        isAdult: adults[sTitle] ?? false,
        seasons: entry.value,
      );
    }).toList();
  }

  List<String> get _currentCategories {
    if (_activeSection == 3) {
      return const ['Canais', 'Filmes', 'Séries'];
    }
    if (_activeSection == 4) {
      return const [];
    }

    final Set<String> cats = {'Todas'};
    if (_activeSection == 0) {
      for (final i in _allItems) {
        if (i.type == ContentType.live) cats.add(i.group);
      }
    } else if (_activeSection == 1) {
      for (final i in _allItems) {
        if (i.type == ContentType.movie) cats.add(i.group);
      }
    } else if (_activeSection == 2) {
      for (final s in _allSeriesGroups) {
        cats.add(s.group);
      }
    }
    return cats.toList();
  }

  List<StreamItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();

    if (_activeSection == 3) {
      if (_selectedCategory == 'Canais' || _selectedCategory == 'TV ao Vivo') {
        return _allItems.where((i) {
          if (i.type != ContentType.live || !_favorites.contains(i.id)) return false;
          if (query.isNotEmpty && !i.name.toLowerCase().contains(query)) return false;
          return true;
        }).toList();
      } else if (_selectedCategory == 'Filmes') {
        return _allItems.where((i) {
          if (i.type != ContentType.movie || !_favorites.contains(i.id)) return false;
          if (query.isNotEmpty && !i.name.toLowerCase().contains(query)) return false;
          return true;
        }).toList();
      } else {
        return const [];
      }
    }

    if (_activeSection == 4) {
      final Map<String, StreamItem> byId = {for (final i in _allItems) i.id: i};
      final List<StreamItem> hist = [];
      for (final id in _historyIds) {
        final item = byId[id];
        if (item != null) {
          if (query.isEmpty || item.name.toLowerCase().contains(query)) {
            hist.add(item);
          }
        }
      }
      return hist;
    }

    final targetType = _activeSection == 0 ? ContentType.live : ContentType.movie;
    return _allItems.where((i) {
      if (i.type != targetType) return false;
      if (_selectedCategory != 'Todas' && i.group != _selectedCategory) return false;
      if (query.isNotEmpty && !i.name.toLowerCase().contains(query)) return false;
      return true;
    }).toList();
  }

  List<SeriesGroup> get _filteredSeriesGroups {
    final query = _searchQuery.trim().toLowerCase();

    if (_activeSection == 3) {
      if (_selectedCategory != 'Séries') return const [];
      return _allSeriesGroups.where((s) {
        final isFav = _favorites.contains('series:${s.title}') ||
            s.seasons.values.any((eps) => eps.any((ep) => _favorites.contains(ep.id)));
        if (!isFav) return false;
        if (query.isNotEmpty && !s.title.toLowerCase().contains(query)) return false;
        return true;
      }).toList();
    }

    if (_activeSection != 2) return const [];

    return _allSeriesGroups.where((s) {
      if (_selectedCategory != 'Todas' && s.group != _selectedCategory) return false;
      if (query.isNotEmpty && !s.title.toLowerCase().contains(query)) return false;
      return true;
    }).toList();
  }

  void _onSectionChanged(int newSection) {
    setState(() {
      _activeSection = newSection;
      _searchController.clear();
      _searchQuery = '';
      if (newSection == 3) {
        _selectedCategory = 'Canais';
      } else {
        _selectedCategory = 'Todas';
      }
    });

    if (newSection == 0 || (newSection == 3 && _selectedCategory == 'Canais')) {
      final list = _filteredItems;
      if (list.isNotEmpty &&
          (_selectedLiveChannel == null || !list.any((c) => c.id == _selectedLiveChannel!.id))) {
        final first = list.first;
        setState(() => _selectedLiveChannel = first);
        if (!first.isAdult || _isAdultUnlocked) {
          SharedStreamEngine.instance.openStream(first);
        }
      }
    } else {
      SharedStreamEngine.instance.stopAndClear();
    }
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
    });

    if (_activeSection == 3) {
      if (category == 'Canais') {
        final favChannels = _filteredItems;
        if (favChannels.isNotEmpty) {
          final first = favChannels.first;
          setState(() => _selectedLiveChannel = first);
          if (!first.isAdult || _isAdultUnlocked) {
            SharedStreamEngine.instance.openStream(first);
          }
        }
      } else {
        SharedStreamEngine.instance.stopAndClear();
      }
    }
  }

  void _toggleFavorite(String id) async {
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
    });
    await LocalAppStorage.setStringList(_kPrefFavorites, _favorites.toList());
  }

  void _recordHistory(StreamItem item) async {
    setState(() {
      _historyIds.remove(item.id);
      _historyIds.insert(0, item.id);
      if (_historyIds.length > 60) {
        _historyIds = _historyIds.sublist(0, 60);
      }
    });
    await LocalAppStorage.setStringList(_kPrefHistory, _historyIds);
  }

  Future<void> _openFullScreen(
    StreamItem item,
    List<StreamItem> playlist, {
    Duration? startPosition,
  }) async {
    if (item.isAdult && !_isAdultUnlocked) {
      final unlocked = await showParentalPinPrompt(context, deviceMode: _deviceMode);
      if (!unlocked || !mounted) return;
      setState(() => _isAdultUnlocked = true);
    }

    _recordHistory(item);

    SharedStreamEngine.instance.setFullScreenActive(true);

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SmartAdaptivePlayerScreen(
            initialItem: item,
            playlist: playlist,
            deviceMode: _deviceMode,
            initialStartPosition: startPosition,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );

    if (!mounted) return;
    SharedStreamEngine.instance.setFullScreenActive(false);

    final activeEngineItem = SharedStreamEngine.instance.currentItem;
    if (activeEngineItem != null && activeEngineItem.type == ContentType.live) {
      setState(() => _selectedLiveChannel = activeEngineItem);
    }
  }

  void _openMovieDetails(StreamItem movie) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isFav = _favorites.contains(movie.id);

          return Dialog(
            backgroundColor: const Color(0xFF111520),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 140,
                        height: 205,
                        child: movie.logo.isNotEmpty
                            ? Image.network(
                                movie.logo,
                                fit: BoxFit.cover,
                                cacheWidth: 320,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFF1A2030),
                                  child: const Icon(Icons.movie, size: 48, color: Colors.white24),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF1A2030),
                                child: const Icon(Icons.movie, size: 48, color: Colors.white24),
                              ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              buildQualityBadge(movie.qualityTag),
                              const SizedBox(width: 8),
                              buildAudioOptionBadge('FILME VOD', isDual: false),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            movie.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            movie.group,
                            style: const TextStyle(fontSize: 12.5, color: Colors.white54),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: TVFocusableItem(
                                  autofocus: true,
                                  autoScroll: false,
                                  onSelect: () {
                                    Navigator.pop(ctx);
                                    _openFullScreen(movie, [movie]);
                                  },
                                  builder: (c, f) => Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: f ? Colors.white : const Color(0xFF00E5FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                                        SizedBox(width: 6),
                                        Text(
                                          'ASSISTIR AGORA',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              TVFocusableItem(
                                autoScroll: false,
                                onSelect: () {
                                  _toggleFavorite(movie.id);
                                  setModalState(() {});
                                },
                                builder: (c, f) => Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: f ? Colors.amber : Colors.white10,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isFav ? Colors.amber : Colors.white24,
                                    ),
                                  ),
                                  child: Icon(
                                    isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: f ? Colors.black : (isFav ? Colors.amber : Colors.white),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openSeriesDetails(SeriesGroup series) {
    final sortedSeasons = series.seasons.keys.toList()..sort();
    int selectedSeason = sortedSeasons.isNotEmpty ? sortedSeasons.first : 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final episodes = series.seasons[selectedSeason] ?? [];
          final allEps = series.seasons.values.expand((e) => e).toList();
          final isFav = _favorites.contains('series:${series.title}') ||
              allEps.any((ep) => _favorites.contains(ep.id));

          return Dialog(
            backgroundColor: const Color(0xFF111520),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650, maxHeight: 480),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        buildChannelLogo(series.logo, size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                series.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${sortedSeasons.length} Temporada(s) • ${allEps.length} Episódios',
                                style: const TextStyle(fontSize: 12, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        TVFocusableItem(
                          autoScroll: false,
                          onSelect: () {
                            if (isFav) {
                              for (final ep in allEps) {
                                if (_favorites.contains(ep.id)) _toggleFavorite(ep.id);
                              }
                              if (_favorites.contains('series:${series.title}')) {
                                _toggleFavorite('series:${series.title}');
                              }
                            } else if (allEps.isNotEmpty) {
                              _toggleFavorite(allEps.first.id);
                            }
                            setModalState(() {});
                          },
                          builder: (c, f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: f ? Colors.amber : Colors.white10,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isFav ? Colors.amber : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                                  color: f ? Colors.black : (isFav ? Colors.amber : Colors.white),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isFav ? 'Favorito' : 'Favoritar',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: f ? Colors.black : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TVIconButton(
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: sortedSeasons.length,
                        itemBuilder: (context, idx) {
                          final sNum = sortedSeasons[idx];
                          final isSelected = sNum == selectedSeason;
                          return TVFocusableItem(
                            autoScroll: false,
                            onSelect: () => setModalState(() => selectedSeason = sNum),
                            builder: (c, f) => Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: f
                                    ? const Color(0xFF00E5FF)
                                    : isSelected
                                        ? const Color(0xFF00E5FF).withOpacity(0.18)
                                        : Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: f || isSelected
                                      ? const Color(0xFF00E5FF)
                                      : Colors.white12,
                                ),
                              ),
                              child: Text(
                                'Temporada $sNum',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: f ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    Expanded(
                      child: ListView.builder(
                        itemCount: episodes.length,
                        itemBuilder: (context, idx) {
                          final ep = episodes[idx];
                          return TVFocusableItem(
                            autofocus: idx == 0,
                            onSelect: () {
                              Navigator.pop(ctx);
                              _openFullScreen(ep, episodes);
                            },
                            builder: (c, f) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: f
                                    ? const Color(0xFF00E5FF).withOpacity(0.2)
                                    : Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: f ? const Color(0xFF00E5FF) : Colors.white10,
                                  width: f ? 1.8 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: f ? const Color(0xFF00E5FF) : Colors.white70,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      ep.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: f ? FontWeight.w800 : FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  buildQualityBadge(ep.qualityTag),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _switchAccount() async {
    SharedStreamEngine.instance.stopAndClear();
    setState(() {
      _isLoggedIn = false;
      _allItems = [];
      _allSeriesGroups = [];
      _selectedLiveChannel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingBoot) {
      return const Scaffold(
        backgroundColor: Color(0xFF07090E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
        ),
      );
    }

    if (!_isLoggedIn) {
      if (!_forceTraditionalLogin) {
        return AtivacaoScreen(
          embedded: true,
          onUseTraditionalLogin: () {
            if (mounted) setState(() => _forceTraditionalLogin = true);
          },
          onM3uActivated: (m3uUrl) async {
            await _loadPlaylistFromUrl(m3uUrl, fromActivationCode: true);
          },
        );
      }
      return _buildLoginScreen();
    }

    if (_deviceMode == DeviceMode.mobile) {
      return MobileLayoutScreen(
        activeSection: _activeSection,
        onSectionChanged: _onSectionChanged,
        selectedCategory: _selectedCategory,
        categories: _currentCategories,
        onCategorySelected: _onCategorySelected,
        searchController: _searchController,
        searchQuery: _searchQuery,
        onSearchChanged: (v) => setState(() => _searchQuery = v),
        filteredItems: _filteredItems,
        groupedSeries: _filteredSeriesGroups,
        selectedLiveChannel: _selectedLiveChannel,
        onLiveChannelSelected: (ch) {
          setState(() => _selectedLiveChannel = ch);
          SharedStreamEngine.instance.openStream(ch);
        },
        onOpenFullScreen: (item, list) => _openFullScreen(item, list),
        onOpenMovieDetails: _openMovieDetails,
        onOpenSeriesDetails: _openSeriesDetails,
        favorites: _favorites,
        onToggleFavorite: _toggleFavorite,
        watchProgress: _watchProgress,
        isAdultUnlocked: _isAdultUnlocked,
        onUnlockAdult: () async {
          final ok = await showParentalPinPrompt(context, deviceMode: _deviceMode);
          if (ok && mounted) setState(() => _isAdultUnlocked = true);
          return ok;
        },
        onRefreshPlaylist: () async {
          final savedUrl = (await LocalAppStorage.getString(_kPrefM3uUrl)) ?? '';
          final byCode = (await LocalAppStorage.getBool(_kPrefActivatedByCode)) ?? false;
          if (savedUrl.isNotEmpty) {
            await _loadPlaylistFromUrl(savedUrl, fromActivationCode: byCode);
          }
        },
        onSwitchAccount: _switchAccount,
      );
    }

    return TVLayoutScreen(
      activeSection: _activeSection,
      onSectionChanged: _onSectionChanged,
      selectedCategory: _selectedCategory,
      categories: _currentCategories,
      onCategorySelected: _onCategorySelected,
      searchController: _searchController,
      searchQuery: _searchQuery,
      onSearchChanged: (v) => setState(() => _searchQuery = v),
      filteredItems: _filteredItems,
      groupedSeries: _filteredSeriesGroups,
      selectedLiveChannel: _selectedLiveChannel,
      onLiveChannelSelected: (ch) {
        setState(() => _selectedLiveChannel = ch);
        SharedStreamEngine.instance.openStream(ch);
      },
      onOpenFullScreen: (item, list) => _openFullScreen(item, list),
      onOpenMovieDetails: _openMovieDetails,
      onOpenSeriesDetails: _openSeriesDetails,
      favorites: _favorites,
      onToggleFavorite: _toggleFavorite,
      watchProgress: _watchProgress,
      isAdultUnlocked: _isAdultUnlocked,
      onUnlockAdult: () async {
        final ok = await showParentalPinPrompt(context, deviceMode: _deviceMode);
        if (ok && mounted) setState(() => _isAdultUnlocked = true);
        return ok;
      },
      onRefreshPlaylist: () async {
        final savedUrl = (await LocalAppStorage.getString(_kPrefM3uUrl)) ?? '';
        final byCode = (await LocalAppStorage.getBool(_kPrefActivatedByCode)) ?? false;
        if (savedUrl.isNotEmpty) {
          await _loadPlaylistFromUrl(savedUrl, fromActivationCode: byCode);
        }
      },
      onSwitchAccount: _switchAccount,
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF111520),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF0088FF)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'UNEX PLAY',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Modo Smart TV / Box'),
                        selected: _deviceMode == DeviceMode.tv,
                        onSelected: (_) => _setDeviceMode(DeviceMode.tv),
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Modo Celular'),
                        selected: _deviceMode == DeviceMode.mobile,
                        onSelected: (_) => _setDeviceMode(DeviceMode.mobile),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _useDirectM3uLink = false),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: !_useDirectM3uLink
                                ? const Color(0xFF00E5FF).withOpacity(0.16)
                                : Colors.transparent,
                            side: BorderSide(
                              color: !_useDirectM3uLink
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white24,
                            ),
                          ),
                          child: const Text('DNS + Usuário'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _useDirectM3uLink = true),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _useDirectM3uLink
                                ? const Color(0xFF00E5FF).withOpacity(0.16)
                                : Colors.transparent,
                            side: BorderSide(
                              color: _useDirectM3uLink
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white24,
                            ),
                          ),
                          child: const Text('Link M3U'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  if (!_useDirectM3uLink) ...[
                    TextField(
                      controller: _dnsController,
                      decoration: const InputDecoration(
                        labelText: 'Servidor / DNS (ex: http://servidor.com:80)',
                        prefixIcon: Icon(Icons.dns_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _userController,
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        prefixIcon: Icon(Icons.person_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: Icon(Icons.lock_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _m3uController,
                      decoration: const InputDecoration(
                        labelText: 'URL da Lista M3U',
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  if (_loginError != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _loginError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoadingPlaylist ? null : _handleTraditionalLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: _isLoadingPlaylist
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'ENTRAR',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Expanded(child: Divider(thickness: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text("ou", style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider(thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoadingPlaylist
                        ? null
                        : () async {
                            final activatedM3uUrl = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AtivacaoScreen(
                                  onM3uActivated: (m3uUrl) async {
                                    await _loadPlaylistFromUrl(
                                      m3uUrl,
                                      fromActivationCode: true,
                                    );
                                  },
                                ),
                              ),
                            );
                            if (activatedM3uUrl != null &&
                                activatedM3uUrl.isNotEmpty &&
                                mounted &&
                                !_isLoggedIn) {
                              await _loadPlaylistFromUrl(
                                activatedM3uUrl,
                                fromActivationCode: true,
                              );
                            }
                          },
                    icon: const Icon(Icons.key, size: 20),
                    label: const Text("Usar Código de Ativação"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
