import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'core.dart';
import 'widgets.dart';
import 'mobile_screen.dart';
import 'tv_screen.dart';
import 'player_screen.dart';

const String kAppVersion = '2.0.0';
const String kOtaCheckUrl = 'https://raw.githubusercontent.com/unexvision/ota/main/version.json';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = UnexHttpOverrides();
  ErrorWidget.builder = (_) => const SizedBox.shrink();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const UnexVisionApp());
}

class UnexVisionApp extends StatelessWidget {
  const UnexVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNEX Vision',
      debugShowCheckedModeBanner: false,
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090B10),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF111520),
        ),
      ),
      home: const BootRouterScreen(),
    );
  }
}

// =============================================================================
// 1. ROTEADOR DE BOOT (AUTO-DETECÇÃO DE DISPOSITIVO + SESSÃO VERIFICADA)
// =============================================================================
class BootRouterScreen extends StatefulWidget {
  const BootRouterScreen({super.key});

  @override
  State<BootRouterScreen> createState() => _BootRouterScreenState();
}

class _BootRouterScreenState extends State<BootRouterScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final mode = await AppStorage.getOrDetectDeviceMode();
    await AppStorage.saveDeviceMode(mode);
    await applyDeviceOrientation(mode);
    final session = await AppStorage.loadVerifiedSession();
    if (!mounted) return;

    if (session != null && session['verified'] == true) {
      Navigator.pushReplacement(
        context,
        createSmoothRoute(
          MainDashboard(
            deviceMode: mode,
            serverDns: session['dns']?.toString() ?? '',
            username: session['user']?.toString() ?? '',
            password: session['pass']?.toString() ?? '',
            directM3uUrl: session['m3uUrl']?.toString(),
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        createSmoothRoute(LoginGatewayScreen(deviceMode: mode)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090B10),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
      ),
    );
  }
}

// =============================================================================
// 2. TELA DE LOGIN INTELIGENTE (TECLADO VIRTUAL 2.0 NA TV + BLOQUEIO VENCIMENTO)
// =============================================================================
class LoginGatewayScreen extends StatefulWidget {
  final DeviceMode deviceMode;
  final String? errorBanner;

  const LoginGatewayScreen({
    super.key,
    required this.deviceMode,
    this.errorBanner,
  });

  @override
  State<LoginGatewayScreen> createState() => _LoginGatewayScreenState();
}

class _LoginGatewayScreenState extends State<LoginGatewayScreen> {
  final _dnsCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _m3uCtrl = TextEditingController();

  late DeviceMode _mode;
  bool _directM3u = false;
  bool _validating = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _mode = widget.deviceMode;
    _errorMsg = widget.errorBanner;
  }

  @override
  void dispose() {
    _dnsCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _m3uCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleDeviceMode() async {
    final next = _mode == DeviceMode.tv ? DeviceMode.mobile : DeviceMode.tv;
    await AppStorage.saveDeviceMode(next);
    await applyDeviceOrientation(next);
    if (mounted) setState(() => _mode = next);
  }

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _validating = true;
      _errorMsg = null;
    });

    if (_directM3u) {
      final rawUrl = _m3uCtrl.text.trim();
      if (rawUrl.isEmpty) {
        setState(() {
          _validating = false;
          _errorMsg = 'Informe o link M3U completo.';
        });
        return;
      }
      final cleanedUrl = XtreamCatalogService.cleanInputUrl(rawUrl);
      _proceed(directM3uUrl: cleanedUrl);
      return;
    }

    final rawDns = _dnsCtrl.text.trim();
    final user = _userCtrl.text.replaceAll(RegExp(r'\s+'), '').trim();
    final pass = _passCtrl.text.replaceAll(RegExp(r'\s+'), '').trim();

    if (rawDns.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() {
        _validating = false;
        _errorMsg = 'Preencha URL/DNS, Usuário e Senha.';
      });
      return;
    }

    final dns = XtreamCatalogService.cleanInputUrl(rawDns);

    // Validação de status e vencimento na API Xtream Codes
    try {
      final uri = Uri.parse(
        '$dns/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}',
      );
      final res = await http.get(uri, headers: kIptvHeaders).timeout(const Duration(seconds: 9));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final info = data['user_info'];
        if (info is Map) {
          final auth = info['auth']?.toString() ?? '1';
          if (auth == '0') {
            setState(() {
              _validating = false;
              _errorMsg = 'Usuário ou senha incorretos.';
            });
            return;
          }
          final status = info['status']?.toString().toLowerCase() ?? '';
          final expRaw = int.tryParse(info['exp_date']?.toString() ?? '');
          final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (status == 'expired' ||
              status == 'banned' ||
              status == 'disabled' ||
              (expRaw != null && expRaw > 0 && expRaw < nowSec)) {
            setState(() {
              _validating = false;
              _errorMsg = 'Sua assinatura está vencida ou inativa. Contate seu provedor para renovar.';
            });
            return;
          }
        }
      }
    } catch (_) {}

    _proceed(dns: dns, user: user, pass: pass);
  }

  void _proceed({
    String dns = '',
    String user = '',
    String pass = '',
    String? directM3uUrl,
  }) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      createSmoothRoute(
        MainDashboard(
          deviceMode: _mode,
          serverDns: dns,
          username: user,
          password: pass,
          directM3uUrl: directM3uUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _mode == DeviceMode.tv;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [Color(0xFF141D33), Color(0xFF090B10)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111520).withOpacity(0.96),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isTV ? '📺 Modo Android TV' : '📱 Modo Celular',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TVFocusableItem(
                            autoScroll: false,
                            onSelect: _toggleDeviceMode,
                            builder: (c, f) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: f ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: f ? Colors.white : Colors.white12,
                                ),
                              ),
                              child: Text(
                                'Alternar Modo',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: f ? Colors.black : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'UNEX VISION',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _directM3u
                            ? 'Insira o link M3U Plus da sua lista'
                            : 'Entre com os dados do seu servidor IPTV',
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            _errorMsg!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11.5, color: Colors.white),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (!_directM3u) ...[
                        _buildInput(
                          'URL / DNS do Servidor',
                          'http://servidor.com:8080',
                          _dnsCtrl,
                          Icons.dns_rounded,
                          autofocus: isTV,
                        ),
                        _buildInput(
                          'Usuário',
                          'Digite seu usuário',
                          _userCtrl,
                          Icons.person_outline_rounded,
                        ),
                        _buildInput(
                          'Senha',
                          'Digite sua senha',
                          _passCtrl,
                          Icons.lock_outline_rounded,
                          obscure: true,
                        ),
                      ] else ...[
                        _buildInput(
                          'Link M3U Completo',
                          'http://.../get.php?username=...',
                          _m3uCtrl,
                          Icons.link_rounded,
                          autofocus: isTV,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (_validating)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: _submitLogin,
                            builder: (c, f) => AnimatedScale(
                              scale: f ? 1.03 : 1.0,
                              duration: const Duration(milliseconds: 120),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: f ? Colors.white : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'CONECTAR AGORA',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => setState(() => _directM3u = !_directM3u),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: f ? const Color(0xFF00E5FF) : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            _directM3u ? 'Usar DNS, Usuário e Senha' : 'Usar Link M3U Direto',
                            style: TextStyle(
                              fontSize: 12,
                              color: f ? const Color(0xFF00E5FF) : Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(
    String label,
    String hint,
    TextEditingController ctrl,
    IconData icon, {
    bool obscure = false,
    bool autofocus = false,
  }) {
    if (_mode == DeviceMode.mobile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF00E5FF)),
            filled: true,
            fillColor: const Color(0xFF080A10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
            ),
          ),
        ),
      );
    }

    // Modo TV: usa exclusivamente o Teclado Virtual 2.0 (sem abrir o teclado do Android)
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: ctrl,
      builder: (context, val, _) {
        final txt = val.text.isEmpty ? hint : (obscure ? '•' * val.text.length : val.text);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TVFocusableItem(
            autofocus: autofocus,
            autoScroll: false,
            onSelect: () => showTVVirtualKeyboard(context, ctrl, label, isPassword: obscure),
            builder: (c, f) => AnimatedScale(
              scale: f ? 1.03 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF080A10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: f ? const Color(0xFF00E5FF) : Colors.white12,
                    width: f ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: f ? Colors.white : const Color(0xFF00E5FF), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            txt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: val.text.isEmpty ? Colors.white38 : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: f ? const Color(0xFF00E5FF) : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'DIGITAR',
                        style: TextStyle(
                          fontSize: 10,
                          color: f ? Colors.black : const Color(0xFF00E5FF),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// 3. PAINEL PRINCIPAL 2.0 (OFFLINE-FIRST + XTREAM API + METADADOS + SÉRIES)
// =============================================================================
class MainDashboard extends StatefulWidget {
  final DeviceMode deviceMode;
  final String serverDns;
  final String username;
  final String password;
  final String? directM3uUrl;

  const MainDashboard({
    super.key,
    required this.deviceMode,
    required this.serverDns,
    required this.username,
    required this.password,
    this.directM3uUrl,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  late DeviceMode _mode;
  bool isTVSideMenuOpen = false;
  bool isLoading = true;
  String loadingStatus = 'Conectando ao servidor...';
  String errorMessage = '';

  List<StreamItem> allItems = [], liveItems = [], movieItems = [], seriesItems = [];
  List<SeriesGroup> allSeriesGroups = [], displayedSeries = [];
  List<StreamItem> displayedItems = [], recentItems = [];
  Set<String> favoriteIds = {};
  Map<String, VodProgressEntry> vodProgressMap = {};
  Map<String, int> categoryCounts = {};
  List<String> sectionCategories = ['Todas'];

  MainSection activeSection = MainSection.live;
  String selectedCategory = 'Todas';
  String searchQuery = '';

  String get _cleanDns => XtreamCatalogService.cleanInputUrl(widget.serverDns);

  String get _m3uUrl {
    if (widget.directM3uUrl != null && widget.directM3uUrl!.isNotEmpty) {
      return XtreamCatalogService.cleanInputUrl(widget.directM3uUrl!);
    }
    final u = Uri.encodeComponent(widget.username.trim());
    final p = Uri.encodeComponent(widget.password.trim());
    return '$_cleanDns/get.php?username=$u&password=$p&type=m3u_plus&output=ts';
  }

  List<VodProgressEntry> get _sortedContinue =>
      vodProgressMap.values.toList()..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

  @override
  void initState() {
    super.initState();
    _mode = widget.deviceMode;
    // Limite rigoroso de cache de imagens na RAM para evitar OutOfMemory em TV Boxes de 1GB/2GB
    PaintingBinding.instance.imageCache.maximumSize = 120;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 35 << 20;

    _engine.addListener(_onEngineChange);
    _engine.onVodProgressSaved = (entry) {
      if (!mounted) return;
      setState(() {
        if (entry.progress >= 0.96) {
          vodProgressMap.remove(entry.item.id);
        } else {
          vodProgressMap[entry.item.id] = entry;
        }
      });
    };

    _bootOfflineFirstAndSync();
    _checkOtaUpdateSilently();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onEngineChange() {
    if (mounted) setState(() {});
  }

  Future<void> _switchDeviceMode(DeviceMode targetMode) async {
    await AppStorage.saveDeviceMode(targetMode);
    await applyDeviceOrientation(targetMode);
    if (mounted) setState(() => _mode = targetMode);
  }

  Future<void> _bootOfflineFirstAndSync() async {
    setState(() {
      isLoading = allItems.isEmpty;
      errorMessage = '';
      loadingStatus = 'Sincronizando canais e catálogo...';
    });

    favoriteIds = await AppStorage.loadFavorites();
    recentItems = await AppStorage.loadRecents();
    vodProgressMap = await AppStorage.loadVodProgressMap();

    // 1. Abertura instantânea pelo cache local (< 1 segundo)
    final cached = await AppStorage.loadOfflinePlaylist();
    if (cached.isNotEmpty && mounted) {
      await _applyCatalog(cached, null, startFirstChannel: true);
    }

    // 2. Prioridade 1: Carregamento rápido via Xtream Codes API JSON
    final creds = XtreamCatalogService.extractXtreamCredentials(
      serverDns: widget.serverDns,
      username: widget.username,
      password: widget.password,
      directM3uUrl: widget.directM3uUrl,
    );

    if (creds != null) {
      final bundle = await XtreamCatalogService.fetchViaXtreamApi(
        dns: creds['dns']!,
        user: creds['user']!,
        pass: creds['pass']!,
      );

      if (bundle != null && bundle.allItems.isNotEmpty) {
        await AppStorage.saveVerifiedSession({
          'dns': creds['dns'],
          'user': creds['user'],
          'pass': creds['pass'],
          'm3uUrl': widget.directM3uUrl,
        });
        if (mounted) {
          await _applyCatalog(
            bundle.allItems,
            bundle.seriesGroups,
            startFirstChannel: cached.isEmpty,
          );
        }
        Future.delayed(const Duration(seconds: 5), () {
          AppStorage.saveOfflinePlaylist(bundle.allItems);
        });
        return;
      }
    }

    // 3. Prioridade 2 (Fallback): Download da lista M3U completa
    try {
      if (mounted && cached.isEmpty) {
        setState(() => loadingStatus = 'Baixando lista M3U completa...');
      }
      final res = await http.get(Uri.parse(_m3uUrl), headers: kIptvHeaders).timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final parsed = await compute(parseM3UAdvanced, body);
        if (parsed.isNotEmpty) {
          await AppStorage.saveVerifiedSession({
            'dns': widget.serverDns,
            'user': widget.username,
            'pass': widget.password,
            'm3uUrl': widget.directM3uUrl,
          });
          if (mounted) {
            await _applyCatalog(parsed, null, startFirstChannel: cached.isEmpty);
          }
          Future.delayed(const Duration(seconds: 5), () {
            AppStorage.saveOfflinePlaylist(parsed);
          });
          return;
        }
      }
      if (cached.isEmpty && mounted) {
        setState(() {
          isLoading = false;
          errorMessage = 'Servidor respondeu sem conteúdos ativos. Verifique o Usuário e a Senha.';
        });
      }
    } catch (_) {
      if (cached.isEmpty && mounted) {
        setState(() {
          isLoading = false;
          errorMessage =
              'Não foi possível conectar ao servidor.\nVerifique sua conexão e os dados de acesso.';
        });
      }
    }
  }

  Future<void> _applyCatalog(
    List<StreamItem> items,
    List<SeriesGroup>? preGroupedSeries, {
    required bool startFirstChannel,
  }) async {
    final live = <StreamItem>[], movies = <StreamItem>[], series = <StreamItem>[];
    for (final i in items) {
      if (i.type == ContentType.live) {
        live.add(i);
      } else if (i.type == ContentType.movie) {
        movies.add(i);
      } else {
        series.add(i);
      }
    }

    final List<SeriesGroup> grouped = (preGroupedSeries != null && preGroupedSeries.isNotEmpty)
        ? preGroupedSeries
        : (allSeriesGroups.isNotEmpty && series.isEmpty
            ? allSeriesGroups
            : await compute(groupSeriesItems, series));

    if (!mounted) return;
    setState(() {
      allItems = items;
      liveItems = live;
      movieItems = movies;
      seriesItems = series;
      allSeriesGroups = grouped;
      isLoading = false;
      errorMessage = '';
      _rebuildCategories();
    });

    if (startFirstChannel && _engine.currentItem == null && items.isNotEmpty) {
      final safeRecent = recentItems.where((r) => !r.isAdult && r.type == ContentType.live).toList();
      final safeLive = live.where((c) => !c.isAdult).toList();
      final initial = safeRecent.isNotEmpty
          ? safeRecent.first
          : (safeLive.isNotEmpty ? safeLive.first : items.first);
      _engine.openStream(initial);
    }
  }

  Future<void> _checkOtaUpdateSilently() async {
    try {
      final res = await http.get(Uri.parse(kOtaCheckUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final latest = data['version']?.toString() ?? kAppVersion;
        final apkUrl = data['apk_url']?.toString() ?? '';
        if (latest != kAppVersion && apkUrl.isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF101422),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF00E5FF)),
              ),
              title: Text('Nova Atualização Disponível ($latest)'),
              content: Text(
                data['notes']?.toString() ??
                    'Uma nova versão otimizada do UNEX Vision está disponível para download.',
              ),
              actions: [
                TVFocusableItem(
                  autofocus: true,
                  autoScroll: false,
                  onSelect: () {
                    Navigator.pop(ctx);
                    nativeChannel.invokeMethod('openExternalUrl', {'url': apkUrl});
                  },
                  builder: (c, f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: f ? Colors.white : const Color(0xFF00E5FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Atualizar Agora',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                TVFocusableItem(
                  autoScroll: false,
                  onSelect: () => Navigator.pop(ctx),
                  builder: (c, f) => const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('Depois'),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {}
  }

  List<StreamItem> _baseList(MainSection sec) {
    switch (sec) {
      case MainSection.live:
        return liveItems;
      case MainSection.movie:
        return movieItems;
      case MainSection.series:
        return seriesItems;
      case MainSection.continueWatching:
        return _sortedContinue.map((e) => e.item).toList();
      case MainSection.favorites:
        return allItems.where((i) => favoriteIds.contains(i.id)).toList();
      case MainSection.recents:
        return recentItems;
    }
  }

  String _secTitle(MainSection sec) {
    switch (sec) {
      case MainSection.live:
        return 'TV ao Vivo';
      case MainSection.movie:
        return 'Filmes';
      case MainSection.series:
        return 'Séries';
      case MainSection.continueWatching:
        return 'Continuar Assistindo';
      case MainSection.favorites:
        return 'Meus Favoritos';
      case MainSection.recents:
        return 'Recentes';
    }
  }

  void _rebuildCategories() {
    if (activeSection == MainSection.series) {
      final counts = <String, int>{'Todas': allSeriesGroups.length};
      for (final s in allSeriesGroups) {
        counts[s.group] = (counts[s.group] ?? 0) + 1;
      }
      categoryCounts = counts;
      sectionCategories = counts.keys.toList();
    } else {
      final base = _baseList(activeSection);
      final counts = <String, int>{'Todas': base.length};
      for (final i in base) {
        counts[i.group] = (counts[i.group] ?? 0) + 1;
      }
      categoryCounts = counts;
      sectionCategories = counts.keys.toList();
    }
    if (!sectionCategories.contains(selectedCategory)) selectedCategory = 'Todas';
    _filterContent();
  }

  void _filterContent() {
    final q = searchQuery.trim().toLowerCase();
    if (activeSection == MainSection.series) {
      var list = selectedCategory == 'Todas'
          ? allSeriesGroups
          : allSeriesGroups.where((s) => s.group == selectedCategory).toList();
      if (q.isNotEmpty) {
        list = list.where((s) => s.title.toLowerCase().contains(q)).toList();
      }
      setState(() => displayedSeries = list);
    } else {
      var list = selectedCategory == 'Todas'
          ? _baseList(activeSection)
          : _baseList(activeSection).where((i) => i.group == selectedCategory).toList();
      if (q.isNotEmpty) {
        list = list.where((i) => i.name.toLowerCase().contains(q)).toList();
      }
      setState(() => displayedItems = list);
    }
  }

  void _toggleFavorite(StreamItem item) {
    setState(() {
      if (favoriteIds.contains(item.id)) {
        favoriteIds.remove(item.id);
      } else {
        favoriteIds.add(item.id);
      }
      AppStorage.saveFavorites(favoriteIds);
      if (activeSection == MainSection.favorites) _rebuildCategories();
    });
  }

  void _recordRecent(StreamItem item) {
    recentItems.removeWhere((r) => r.id == item.id);
    recentItems.insert(0, item);
    if (recentItems.length > 40) recentItems.removeLast();
    AppStorage.saveRecents(recentItems);
  }

  Future<void> _openFullScreen(StreamItem item, {List<StreamItem>? customList}) async {
    _recordRecent(item);
    Duration? startPos;
    final saved = vodProgressMap[item.id];
    if (item.type != ContentType.live && saved != null && _engine.currentItem?.id != item.id) {
      startPos = await showVodResumePrompt(context: context, entry: saved);
      if (startPos == null) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      createSmoothRoute(
        SmartAdaptivePlayerScreen(
          initialItem: item,
          playlist: customList ?? (displayedItems.isNotEmpty ? displayedItems : liveItems),
          deviceMode: _mode,
          initialStartPosition: startPos,
        ),
      ),
    );
  }

  void _handlePreviewOrPlay(StreamItem item) {
    _recordRecent(item);
    // Para Filmes, exibe a Ficha de Sinopse, Elenco, Ano e Nota antes de reproduzir
    if (item.type == ContentType.movie) {
      _showVodMetadataSheet(item);
      return;
    }
    // Para Canais ao Vivo: se já está sintonizado no preview, abre Tela Cheia; senão, sintoniza no preview
    if (_engine.currentItem?.id == item.id) {
      _openFullScreen(item);
      return;
    }
    _engine.openStream(item);
  }

  // ===========================================================================
  // FICHA COMPLETA DE METADADOS VOD (SINOPSE, ELENCO, ANO E AVALIAÇÃO)
  // ===========================================================================
  void _showVodMetadataSheet(StreamItem initialItem) {
    StreamItem detailedItem = initialItem;
    bool fetchingInfo = true;

    final creds = XtreamCatalogService.extractXtreamCredentials(
      serverDns: widget.serverDns,
      username: widget.username,
      password: widget.password,
      directM3uUrl: widget.directM3uUrl,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          if (fetchingInfo) {
            fetchingInfo = false;
            if (creds != null && initialItem.streamId.isNotEmpty) {
              XtreamCatalogService.fetchVodDetails(
                item: initialItem,
                dns: creds['dns']!,
                user: creds['user']!,
                pass: creds['pass']!,
              ).then((updated) {
                if (ctx.mounted) {
                  setModal(() => detailedItem = updated);
                }
              });
            }
          }

          final savedProg = vodProgressMap[detailedItem.id];
          final isFav = favoriteIds.contains(detailedItem.id);

          return Dialog(
            backgroundColor: const Color(0xFF0E121E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 110,
                            height: 160,
                            child: detailedItem.logo.isNotEmpty
                                ? Image.network(
                                    detailedItem.logo,
                                    fit: BoxFit.cover,
                                    cacheWidth: 220,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF161B2A),
                                      child: const Icon(Icons.movie, color: Color(0xFF00E5FF), size: 40),
                                    ),
                                  )
                                : Container(
                                    color: const Color(0xFF161B2A),
                                    child: const Icon(Icons.movie, color: Color(0xFF00E5FF), size: 40),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  buildQualityBadge(detailedItem.qualityTag),
                                  const SizedBox(width: 8),
                                  Text(
                                    '★ ${detailedItem.rating != "N/A" ? detailedItem.rating : "8.4"}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  if (detailedItem.year.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '• ${detailedItem.year}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                detailedItem.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                detailedItem.group,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                detailedItem.synopsis != 'Nenhuma sinopse disponível.'
                                    ? detailedItem.synopsis
                                    : 'Conteúdo sob demanda em alta definição (${detailedItem.qualityTag}) disponível no catálogo ${detailedItem.group}.',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.4),
                              ),
                              if (detailedItem.cast.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Elenco: ${detailedItem.cast}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (savedProg != null) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: savedProg.progress,
                          minHeight: 5,
                          color: const Color(0xFF00E5FF),
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Progresso salvo em ${savedProg.formattedPosition} (${savedProg.formattedRemaining})',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF)),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        TVFocusableItem(
                          autofocus: true,
                          autoScroll: false,
                          onSelect: () {
                            Navigator.pop(ctx);
                            _openFullScreen(detailedItem);
                          },
                          builder: (c, f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: f ? Colors.white : const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              savedProg != null ? '▶ Continuar / Assistir' : '▶ Assistir Agora',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        TVFocusableItem(
                          autoScroll: false,
                          onSelect: () {
                            _toggleFavorite(detailedItem);
                            setModal(() {});
                          },
                          builder: (c, f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: f ? Colors.white12 : Colors.transparent,
                              border: Border.all(
                                color: f ? const Color(0xFF00E5FF) : Colors.white24,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isFav ? '★ Nos Favoritos' : '☆ Favoritar',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ),
                        ),
                        TVFocusableItem(
                          autoScroll: false,
                          onSelect: () => Navigator.pop(ctx),
                          builder: (c, f) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: f ? Colors.white : Colors.white12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('Fechar', style: TextStyle(fontSize: 12.5)),
                          ),
                        ),
                      ],
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

  // ===========================================================================
  // MODAL COMPLETO DE TEMPORADAS E EPISÓDIOS DE SÉRIES
  // ===========================================================================
  Future<void> _openSeriesEpisodesModal(SeriesGroup series) async {
    Map<int, List<StreamItem>> seasonsMap = series.seasons;

    if (seasonsMap.isEmpty) {
      final creds = XtreamCatalogService.extractXtreamCredentials(
        serverDns: widget.serverDns,
        username: widget.username,
        password: widget.password,
        directM3uUrl: widget.directM3uUrl,
      );
      if (creds != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
          ),
        );
        seasonsMap = await XtreamCatalogService.fetchSeriesEpisodes(
          series: series,
          dns: creds['dns']!,
          user: creds['user']!,
          pass: creds['pass']!,
        );
        if (mounted) Navigator.pop(context);
      }
    }

    if (!mounted) return;
    final seasons = seasonsMap.keys.toList()..sort();
    int selSeason = seasons.isNotEmpty ? seasons.first : 1;
    final flatList = seasons.expand((k) => seasonsMap[k]!).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          final eps = seasonsMap[selSeason] ?? [];
          return Dialog(
            backgroundColor: const Color(0xFF0D111C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740, maxHeight: 540),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        buildChannelLogo(series.logo, size: 56),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                series.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${series.group} • ${seasons.length} Temporada(s) • ${flatList.length} Episódios',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TVIconButton(
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    if (series.synopsis.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        series.synopsis,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (seasons.isNotEmpty)
                      SizedBox(
                        height: 38,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: seasons.length,
                          itemBuilder: (c, i) {
                            final s = seasons[i];
                            final active = s == selSeason;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: TVFocusableItem(
                                autoScroll: false,
                                onSelect: () => setModal(() => selSeason = s),
                                builder: (c, f) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? const Color(0xFF00E5FF)
                                        : const Color(0xFF171C2B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: f ? Colors.white : Colors.white12,
                                      width: f ? 2 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    'Temporada $s',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: active ? Colors.black : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const Divider(color: Colors.white12, height: 18),
                    Expanded(
                      child: eps.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum episódio encontrado para esta série.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : ListView.builder(
                              itemCount: eps.length,
                              itemBuilder: (c, idx) {
                                final ep = eps[idx];
                                final prog = vodProgressMap[ep.id];
                                return TVFocusableItem(
                                  autofocus: idx == 0,
                                  onSelect: () {
                                    Navigator.pop(ctx);
                                    _openFullScreen(ep, customList: flatList);
                                  },
                                  builder: (c, f) => Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: f
                                          ? const Color(0xFF1A2842)
                                          : const Color(0xFF131724),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: f ? const Color(0xFF00E5FF) : Colors.white10,
                                        width: f ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00E5FF).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'E${ep.episodeNumber.toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF00E5FF),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            ep.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (prog != null)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: Text(
                                              prog.formattedPosition,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF00E5FF),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        const Icon(
                                          Icons.play_circle_fill_rounded,
                                          color: Color(0xFF00E5FF),
                                          size: 24,
                                        ),
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

  // ===========================================================================
  // SUPERFÍCIE 16:9 DE PRÉ-VISUALIZAÇÃO (NUNCA NASCE COM TAMANHO 0x0 NA TV)
  // ===========================================================================
  Widget _buildMiniVideo() {
    if (_engine.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering_error_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(height: 6),
            const Text(
              'Sinal indisponível',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 6),
            if (_engine.currentItem != null)
              TVFocusableItem(
                autoScroll: false,
                onSelect: () => _engine.openStream(
                  _engine.currentItem!,
                  forceReload: true,
                  tryHlsFallback: true,
                ),
                builder: (c, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: f ? Colors.white : const Color(0xFF00E5FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Alternar TS / HLS',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final c = _engine.controller;
    if (!_engine.isReady || c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
      );
    }

    final ratio = c.value.aspectRatio > 0 ? c.value.aspectRatio : (16 / 9);
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: VideoPlayer(c),
      ),
    );
  }

  Future<void> _logoutToLogin() async {
    await _engine.stopAndClear();
    await AppStorage.clearAllData();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      createSmoothRoute(LoginGatewayScreen(deviceMode: _mode)),
    );
  }

  Future<void> _confirmExitApp() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101422),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF00E5FF)),
        ),
        title: const Text('Sair do UNEX Vision?'),
        content: const Text(
          'Deseja fechar o aplicativo agora?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TVFocusableItem(
            autofocus: true,
            autoScroll: false,
            onSelect: () => Navigator.pop(ctx, false),
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: f ? Colors.white : const Color(0xFF00E5FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Continuar Assistindo',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TVFocusableItem(
            autoScroll: false,
            onSelect: () => Navigator.pop(ctx, true),
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: f ? Colors.redAccent : Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Sair', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      await _engine.stopAndClear();
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = _mode == DeviceMode.tv;

    final mobileView = MobileDashboardView(
      scaffoldKey: _scaffoldKey,
      activeSection: activeSection,
      sectionTitle: _secTitle(activeSection),
      selectedCategory: selectedCategory,
      sectionCategories: sectionCategories,
      categoryCounts: categoryCounts,
      displayedItems: displayedItems,
      displayedSeries: displayedSeries,
      continueWatchingEntries: _sortedContinue,
      vodProgressMap: vodProgressMap,
      favoriteIds: favoriteIds,
      activeItem: _engine.currentItem,
      activeEpg: _engine.currentEpg,
      miniVideoWidget: _buildMiniVideo(),
      searchController: _searchCtrl,
      searchQuery: searchQuery,
      onSelectSection: (s) => setState(() {
        activeSection = s;
        selectedCategory = 'Todas';
        _rebuildCategories();
      }),
      onSelectCategory: (c) => setState(() {
        selectedCategory = c;
        _filterContent();
      }),
      onSearchChanged: (v) {
        searchQuery = v;
        _filterContent();
      },
      onClearSearch: () {
        setState(() {
          _searchCtrl.clear();
          searchQuery = '';
          _filterContent();
        });
      },
      onStartPreview: _handlePreviewOrPlay,
      onOpenFullScreen: _openFullScreen,
      onSelectSeriesGroup: _openSeriesEpisodesModal,
      onToggleFavorite: _toggleFavorite,
      onRefreshPlaylist: _bootOfflineFirstAndSync,
      onLogout: _logoutToLogin,
      onSwitchToTVMode: () => _switchDeviceMode(DeviceMode.tv),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (isTV && !isTVSideMenuOpen) {
          setState(() => isTVSideMenuOpen = true);
        } else {
          _confirmExitApp();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: isTV
            ? null
            : Builder(
                builder: (ctx) => Drawer(
                  backgroundColor: const Color(0xFF090B10),
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'UNEX VISION 2.0',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00E5FF),
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(10),
                            children: [
                              _buildMobileDrawerTile(ctx, 'TV ao Vivo', MainSection.live, Icons.live_tv_rounded),
                              _buildMobileDrawerTile(ctx, 'Filmes', MainSection.movie, Icons.movie_creation_rounded),
                              _buildMobileDrawerTile(ctx, 'Séries', MainSection.series, Icons.video_library_rounded),
                              const Divider(color: Colors.white10, height: 20),
                              _buildMobileDrawerTile(
                                ctx,
                                'Continuar Assistindo',
                                MainSection.continueWatching,
                                Icons.play_circle_filled_rounded,
                              ),
                              _buildMobileDrawerTile(ctx, 'Meus Favoritos', MainSection.favorites, Icons.star_rounded),
                              _buildMobileDrawerTile(ctx, 'Recentes', MainSection.recents, Icons.history_rounded),
                              const Divider(color: Colors.white10, height: 20),
                              ListTile(
                                leading: const Icon(Icons.lock_person_rounded, color: Colors.white70),
                                title: const Text('Alterar Senha Parental (+18)'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  showChangeParentalPinDialog(context, deviceMode: DeviceMode.mobile);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.tv_rounded, color: Color(0xFF00E5FF)),
                                title: const Text('Alternar para Modo TV'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _switchDeviceMode(DeviceMode.tv);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.refresh_rounded, color: Colors.white70),
                                title: const Text('Atualizar Lista'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _bootOfflineFirstAndSync();
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                                title: const Text(
                                  'Trocar Conta / Sair',
                                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _logoutToLogin();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          child: isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF00E5FF)),
                      const SizedBox(height: 16),
                      Text(
                        loadingStatus,
                        style: const TextStyle(fontSize: 13.5, color: Colors.white70),
                      ),
                    ],
                  ),
                )
              : errorMessage.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.tv_off_rounded, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 14),
                            Text(
                              errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              children: [
                                TVFocusableItem(
                                  autofocus: true,
                                  autoScroll: false,
                                  onSelect: _bootOfflineFirstAndSync,
                                  builder: (c, f) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: f ? Colors.white : const Color(0xFF00E5FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Tentar Novamente',
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                TVFocusableItem(
                                  autoScroll: false,
                                  onSelect: _logoutToLogin,
                                  builder: (c, f) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: f ? Colors.white : Colors.white24),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Corrigir Dados de Login',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : isTV
                      ? TVDashboardView(
                          isSideMenuOpen: isTVSideMenuOpen,
                          onOpenSideMenu: () => setState(() => isTVSideMenuOpen = true),
                          onCloseSideMenu: () => setState(() => isTVSideMenuOpen = false),
                          activeSection: activeSection,
                          sectionTitle: _secTitle(activeSection),
                          selectedCategory: selectedCategory,
                          sectionCategories: sectionCategories,
                          categoryCounts: categoryCounts,
                          displayedItems: displayedItems,
                          displayedSeries: displayedSeries,
                          vodProgressMap: vodProgressMap,
                          favoriteIds: favoriteIds,
                          activeItem: _engine.currentItem,
                          activeEpg: _engine.currentEpg,
                          miniVideoWidget: _buildMiniVideo(),
                          searchController: _searchCtrl,
                          searchQuery: searchQuery,
                          onSearchChanged: (v) {
                            searchQuery = v;
                            _filterContent();
                          },
                          onClearSearch: () {
                            setState(() {
                              _searchCtrl.clear();
                              searchQuery = '';
                              _filterContent();
                            });
                          },
                          onRefreshPlaylist: _bootOfflineFirstAndSync,
                          onLogout: _logoutToLogin,
                          onSelectSection: (s) => setState(() {
                            activeSection = s;
                            selectedCategory = 'Todas';
                            isTVSideMenuOpen = false;
                            _rebuildCategories();
                          }),
                          onSelectCategory: (c) => setState(() {
                            selectedCategory = c;
                            isTVSideMenuOpen = false;
                            _filterContent();
                          }),
                          onStartPreview: _handlePreviewOrPlay,
                          onOpenFullScreen: _openFullScreen,
                          onSelectSeriesGroup: _openSeriesEpisodesModal,
                          onToggleFavorite: _toggleFavorite,
                        )
                      : mobileView,
        ),
      ),
    );
  }

  Widget _buildMobileDrawerTile(
    BuildContext ctx,
    String title,
    MainSection section,
    IconData icon,
  ) {
    final sel = activeSection == section;
    return ListTile(
      leading: Icon(icon, color: sel ? const Color(0xFF00E5FF) : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: sel ? const Color(0xFF00E5FF) : Colors.white,
          fontWeight: sel ? FontWeight.w900 : FontWeight.bold,
        ),
      ),
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          activeSection = section;
          selectedCategory = 'Todas';
          _rebuildCategories();
        });
      },
    );
  }
}
