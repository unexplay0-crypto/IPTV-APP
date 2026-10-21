import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'core.dart';

// ===========================================================================
// ARMAZENAMENTO LOCAL NATIVO (SEM DEPENDER DE PACOTES EXTERNOS)
// ===========================================================================
class LocalAppStorage {
  static Map<String, dynamic>? _cache;

  static Future<File> _getStorageFile() async {
    final dir = Directory.systemTemp;
    return File('${dir.path}/unex_play_local_store_v1.json');
  }

  static Future<Map<String, dynamic>> _loadMap() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _cache = decoded;
          return _cache!;
        }
      }
    } catch (_) {}
    _cache = <String, dynamic>{};
    return _cache!;
  }

  static Future<void> _saveMap() async {
    try {
      final file = await _getStorageFile();
      await file.writeAsString(jsonEncode(_cache ?? {}), flush: true);
    } catch (_) {}
  }

  static Future<String?> getString(String key) async {
    final map = await _loadMap();
    final val = map[key];
    return val is String ? val : null;
  }

  static Future<void> setString(String key, String value) async {
    final map = await _loadMap();
    map[key] = value;
    await _saveMap();
  }

  static Future<bool?> getBool(String key) async {
    final map = await _loadMap();
    final val = map[key];
    return val is bool ? val : null;
  }

  static Future<void> setBool(String key, bool value) async {
    final map = await _loadMap();
    map[key] = value;
    await _saveMap();
  }

  static Future<List<String>> getStringList(String key) async {
    final map = await _loadMap();
    final val = map[key];
    if (val is List) {
      return val.map((e) => e.toString()).toList();
    }
    return <String>[];
  }

  static Future<void> setStringList(String key, List<String> value) async {
    final map = await _loadMap();
    map[key] = value;
    await _saveMap();
  }
}

// ===========================================================================
// COMPONENTE DE FOCO PARA CONTROLE REMOTO DE TV E TOQUE
// ===========================================================================
class TVFocusableItem extends StatefulWidget {
  final Widget Function(BuildContext context, bool isFocused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool autofocus;
  final bool autoScroll;
  final FocusNode? focusNode;

  const TVFocusableItem({
    super.key,
    required this.builder,
    this.onSelect,
    this.onLongSelect,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.autofocus = false,
    this.autoScroll = true,
    this.focusNode,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  late FocusNode _node;
  bool _ownsNode = false;
  bool _isFocused = false;

  Timer? _longPressTimer;
  bool _isSelectKeyDown = false;
  bool _longPressTriggered = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode();
      _ownsNode = true;
    }
    _node.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant TVFocusableItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _node.removeListener(_onFocusChange);
      if (_ownsNode) {
        _node.dispose();
      }
      if (widget.focusNode != null) {
        _node = widget.focusNode!;
        _ownsNode = false;
      } else {
        _node = FocusNode();
        _ownsNode = true;
      }
      _node.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _node.removeListener(_onFocusChange);
    if (_ownsNode) {
      _node.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    final hasFocus = _node.hasFocus;
    if (!hasFocus) {
      _longPressTimer?.cancel();
      _isSelectKeyDown = false;
      _longPressTriggered = false;
    }
    if (_isFocused != hasFocus) {
      setState(() => _isFocused = hasFocus);
    }
    if (hasFocus && widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  bool _isConfirmKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (_isConfirmKey(key)) {
      if (widget.onLongSelect == null) {
        if (event is KeyDownEvent) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      if (event is KeyDownEvent) {
        if (!_isSelectKeyDown) {
          _isSelectKeyDown = true;
          _longPressTriggered = false;
          _longPressTimer?.cancel();
          _longPressTimer = Timer(const Duration(milliseconds: 550), () {
            if (mounted && _isSelectKeyDown && !_longPressTriggered) {
              _longPressTriggered = true;
              HapticFeedback.mediumImpact();
              widget.onLongSelect?.call();
            }
          });
        }
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _longPressTimer?.cancel();
        final wasLong = _longPressTriggered;
        final wasDown = _isSelectKeyDown;
        _isSelectKeyDown = false;
        _longPressTriggered = false;
        if (wasDown && !wasLong) {
          widget.onSelect?.call();
        }
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.arrowLeft && widget.onMoveLeft != null) {
        widget.onMoveLeft!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight && widget.onMoveRight != null) {
        widget.onMoveRight!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && widget.onMoveUp != null) {
        widget.onMoveUp!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && widget.onMoveDown != null) {
        widget.onMoveDown!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onLongPress: widget.onLongSelect,
        child: widget.builder(context, _isFocused),
      ),
    );
  }
}

// ===========================================================================
// BOTÃO DE ÍCONE FOCÁVEL PARA TV E MOBILE
// ===========================================================================
class TVIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final double size;
  final bool autofocus;

  const TVIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
    this.size = 20,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      autofocus: autofocus,
      autoScroll: false,
      onSelect: onPressed,
      builder: (context, isFocused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: isFocused ? Colors.white : Colors.white24,
            width: isFocused ? 1.8 : 1.0,
          ),
        ),
        child: Icon(
          icon,
          size: size,
          color: isFocused ? Colors.black : color,
        ),
      ),
    );
  }
}

// ===========================================================================
// BADGES DE QUALIDADE, ÁUDIO E LOGOS DE CANAIS
// ===========================================================================
Widget buildQualityBadge(String text) {
  final clean = text.trim().isEmpty ? 'HD' : text.trim().toUpperCase();
  Color badgeColor = const Color(0xFF00E5FF);
  if (clean.contains('4K') || clean.contains('UHD')) {
    badgeColor = const Color(0xFFFFD54F);
  } else if (clean.contains('FHD') || clean.contains('1080')) {
    badgeColor = const Color(0xFF00E5FF);
  } else if (clean.contains('SD')) {
    badgeColor = Colors.white70;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(
      color: badgeColor.withOpacity(0.16),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: badgeColor.withOpacity(0.6), width: 1),
    ),
    child: Text(
      clean,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        color: badgeColor,
        letterSpacing: 0.5,
      ),
    ),
  );
}

Widget buildAudioOptionBadge(String text, {bool isDual = false}) {
  final color = isDual ? const Color(0xFF00E676) : const Color(0xFFFFAB40);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.16),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withOpacity(0.65), width: 1),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 0.4,
      ),
    ),
  );
}

Widget buildChannelLogo(String url, {double size = 44, bool isLocked = false}) {
  if (isLocked) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Icon(Icons.lock_rounded, color: Colors.redAccent, size: size * 0.5),
    );
  }

  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF0B0E17),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10),
    ),
    clipBehavior: Clip.antiAlias,
    child: url.isNotEmpty
        ? Image.network(
            url,
            fit: BoxFit.contain,
            cacheWidth: (size * 2.5).toInt(),
            errorBuilder: (_, __, ___) => Icon(
              Icons.live_tv_rounded,
              color: Colors.white38,
              size: size * 0.5,
            ),
          )
        : Icon(
            Icons.live_tv_rounded,
            color: Colors.white38,
            size: size * 0.5,
          ),
  );
}

// ===========================================================================
// CARD DE PÔSTER DE STREAMING (COMPATÍVEL COM TV E MOBILE)
// ===========================================================================
Widget buildStreamingPosterCard({
  required String title,
  required String subtitle,
  required String logoUrl,
  String badgeText = 'HD',
  bool isFocused = false,
  bool isPlaying = false,
  bool isFavorite = false,
  bool isAdultLocked = false,
  bool hasDualAudio = false,
  bool isSubtitledOnly = false,
  double? progress,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) {
  final effectiveHighlight = isFocused || isPlaying;

  return AnimatedScale(
    scale: isFocused ? 1.06 : 1.0,
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFF141926),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: effectiveHighlight ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.08),
          width: effectiveHighlight ? 2.6 : 1.0,
        ),
        boxShadow: effectiveHighlight
            ? [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isAdultLocked)
            Container(
              color: const Color(0xFF0E121A),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, color: Colors.redAccent, size: 38),
                  SizedBox(height: 8),
                  Text(
                    'CONTEÚDO +18',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            )
          else if (logoUrl.isNotEmpty)
            Image.network(
              logoUrl,
              fit: BoxFit.cover,
              cacheWidth: 320,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF141926),
                child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 42),
              ),
            )
          else
            Container(
              color: const Color(0xFF141926),
              child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 42),
            ),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.transparent,
                    Colors.black.withOpacity(0.88),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                buildQualityBadge(badgeText),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasDualAudio)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DUB/LEG',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      )
                    else if (isSubtitledOnly)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LEG',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    if (isFavorite)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: effectiveHighlight ? const Color(0xFF00E5FF) : Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white60,
                  ),
                ),
                if (progress != null && progress > 0.02) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3.5,
                      backgroundColor: Colors.white24,
                      color: const Color(0xFF00E5FF),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ===========================================================================
// NOTIFICAÇÃO RÁPIDA AO FAVORITAR SEGURANDO O BOTÃO OK
// ===========================================================================
void showQuickFavoriteToast(
  BuildContext context, {
  required String title,
  required bool isAdded,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF141926),
      duration: const Duration(milliseconds: 1600),
      margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAdded ? Colors.amber : Colors.white24,
          width: 1.4,
        ),
      ),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdded ? Icons.star_rounded : Icons.star_outline_rounded,
            color: isAdded ? Colors.amber : Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isAdded
                  ? 'Adicionado aos Favoritos: $title'
                  : 'Removido dos Favoritos: $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ===========================================================================
// MODAL DE TESTE DE VELOCIDADE DA INTERNET COM SUGESTÃO DE RESOLUÇÃO
// ===========================================================================
Future<void> showSpeedTestDialog(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _SpeedTestModal(deviceMode: deviceMode),
  );
}

class _SpeedTestModal extends StatefulWidget {
  final DeviceMode deviceMode;

  const _SpeedTestModal({required this.deviceMode});

  @override
  State<_SpeedTestModal> createState() => _SpeedTestModalState();
}

class _SpeedTestModalState extends State<_SpeedTestModal> {
  bool _isTesting = false;
  double _mbps = 0.0;
  double _progress = 0.0;
  String _statusMessage = 'Iniciando medição da sua conexão...';
  bool _hasFinished = false;
  http.Client? _activeClient;

  static const List<String> _testUrls = [
    'https://speed.cloudflare.com/__down?bytes=8000000',
    'https://speed.cloudflare.com/__down?bytes=4000000',
    'https://proof.ovh.net/files/1Mb.dat',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSpeedTest());
  }

  @override
  void dispose() {
    _activeClient?.close();
    super.dispose();
  }

  Future<void> _runSpeedTest() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _hasFinished = false;
      _mbps = 0.0;
      _progress = 0.05;
      _statusMessage = 'Conectando ao servidor de teste...';
    });

    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;

    int totalBytes = 0;
    final stopwatch = Stopwatch();
    bool success = false;

    try {
      for (final url in _testUrls) {
        if (!mounted) return;
        try {
          final request = http.Request('GET', Uri.parse(url));
          request.headers['Cache-Control'] = 'no-cache';
          final response = await client.send(request).timeout(const Duration(seconds: 6));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            if (!stopwatch.isRunning) stopwatch.start();
            setState(() => _statusMessage = 'Medindo taxa de download em tempo real...');

            await for (final chunk in response.stream) {
              if (!mounted) return;
              totalBytes += chunk.length;
              final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
              if (elapsedSec > 0.15) {
                final currentMbps = (totalBytes * 8) / (elapsedSec * 1000000.0);
                setState(() {
                  _mbps = currentMbps;
                  _progress = (elapsedSec / 4.5).clamp(0.1, 0.95);
                });
              }
              if (stopwatch.elapsedMilliseconds >= 4500) {
                break;
              }
            }

            if (totalBytes > 64 * 1024) {
              success = true;
              break;
            }
          }
        } catch (_) {}
      }
    } finally {
      stopwatch.stop();
      client.close();
    }

    if (!mounted) return;

    if (success && stopwatch.elapsedMilliseconds > 0) {
      final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
      final finalMbps = (totalBytes * 8) / (elapsedSec * 1000000.0);
      setState(() {
        _mbps = finalMbps;
        _progress = 1.0;
        _isTesting = false;
        _hasFinished = true;
        _statusMessage = 'Teste concluído com sucesso!';
      });
    } else {
      setState(() {
        _mbps = 0.0;
        _progress = 0.0;
        _isTesting = false;
        _hasFinished = true;
        _statusMessage = 'Não foi possível medir a conexão no momento.';
      });
    }
  }

  Map<String, dynamic> _getResolutionSuggestion() {
    if (_mbps <= 0.1) {
      return {
        'badge': 'SEM MEDIÇÃO',
        'title': 'Verifique sua conexão com a internet',
        'desc': 'Não foi possível concluir a leitura. Verifique seu Wi-Fi ou cabo de rede.',
        'color': Colors.redAccent,
      };
    } else if (_mbps < 5.0) {
      return {
        'badge': 'RECOMENDADO: CANAIS SD',
        'title': 'Conexão Básica (Ideal para Resolução SD)',
        'desc':
            'Para evitar travamentos, dê preferência aos canais SD (480p). Canais FHD ou 4K podem apresentar pausas.',
        'color': Colors.orangeAccent,
      };
    } else if (_mbps < 15.0) {
      return {
        'badge': 'RECOMENDADO: CANAIS HD (720p)',
        'title': 'Boa Conexão (Ideal para Resolução HD)',
        'desc':
            'Sua velocidade permite assistir canais e filmes em qualidade HD (720p) com boa estabilidade.',
        'color': const Color(0xFF00E5FF),
      };
    } else if (_mbps < 30.0) {
      return {
        'badge': 'RECOMENDADO: FULL HD (1080p)',
        'title': 'Ótima Conexão (Pronta para Full HD)',
        'desc':
            'Você pode assistir canais ao vivo, filmes e séries em Full HD (1080p) com excelente fluidez.',
        'color': const Color(0xFF00E676),
      };
    } else {
      return {
        'badge': 'RECOMENDADO: 4K / ULTRA HD & FHD',
        'title': 'Velocidade Máxima (Suporta 4K e Full HD)',
        'desc':
            'Sua internet tem folga para reproduzir qualquer canal ou filme em 4K / Ultra HD e Full HD sem engasgos!',
        'color': const Color(0xFFFFD54F),
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _getResolutionSuggestion();
    final Color tierColor = suggestion['color'] as Color;

    return Dialog(
      backgroundColor: const Color(0xFF111520),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.speed_rounded, color: Color(0xFF00E5FF), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Teste de Velocidade',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Diagnóstico de rede e resolução recomendada',
                          style: TextStyle(fontSize: 11.5, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF090B10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _mbps.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Mbps',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _isTesting ? _progress : (_hasFinished ? 1.0 : 0.0),
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        color: const Color(0xFF00E5FF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              if (_hasFinished) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tierColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tierColor.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tierColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          suggestion['badge'] as String,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        suggestion['title'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        suggestion['desc'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isTesting)
                    TVFocusableItem(
                      autoScroll: false,
                      onSelect: _runSpeedTest,
                      builder: (c, f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: f ? Colors.white.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: f ? const Color(0xFF00E5FF) : Colors.white24,
                            width: f ? 1.8 : 1,
                          ),
                        ),
                        child: const Text(
                          'Refazer Teste',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  TVFocusableItem(
                    autofocus: true,
                    autoScroll: false,
                    onSelect: () => Navigator.pop(context),
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: f ? Colors.white : const Color(0xFF00E5FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Fechar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// CONTROLE PARENTAL (SUPORTA AMBOS OS NOMES DE FUNÇÃO)
// ===========================================================================
const String _kParentalPinPrefKey = 'unex_parental_pin_v1';

Future<String> _getSavedPin() async {
  return (await LocalAppStorage.getString(_kParentalPinPrefKey)) ?? '0000';
}

Future<void> _saveNewPin(String pin) async {
  await LocalAppStorage.setString(_kParentalPinPrefKey, pin);
}

Future<bool> showParentalPinPrompt(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) async {
  final savedPin = await _getSavedPin();
  if (!context.mounted) return false;

  String entered = '';
  String? errorText;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        void onDigit(String digit) {
          if (entered.length < 4) {
            setModalState(() {
              entered += digit;
              errorText = null;
            });
            if (entered.length == 4) {
              if (entered == savedPin) {
                Navigator.pop(ctx, true);
              } else {
                setModalState(() {
                  entered = '';
                  errorText = 'Senha incorreta! Padrão: 0000';
                });
              }
            }
          }
        }

        return Dialog(
          backgroundColor: const Color(0xFF111520),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_person_rounded, color: Colors.redAccent, size: 34),
                  const SizedBox(height: 10),
                  const Text(
                    'Controle Parental',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Digite o PIN de 4 dígitos (Padrão: 0000)',
                    style: TextStyle(fontSize: 11.5, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < entered.length;
                      return Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? const Color(0xFF00E5FF) : Colors.white12,
                          border: Border.all(color: Colors.white30),
                        ),
                      );
                    }),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
                        TVFocusableItem(
                          autofocus: d == '1',
                          autoScroll: false,
                          onSelect: () => onDigit(d),
                          builder: (c, f) => Container(
                            width: 58,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: f ? const Color(0xFF00E5FF) : const Color(0xFF1A2030),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: f ? Colors.white : Colors.white12),
                            ),
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: f ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => Navigator.pop(ctx, false),
                        builder: (c, f) => Container(
                          width: 126,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: f ? Colors.redAccent : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
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

  return result ?? false;
}

Future<void> showChangeParentalPinDialog(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) async {
  final unlocked = await showParentalPinPrompt(context, deviceMode: deviceMode);
  if (!unlocked || !context.mounted) return;

  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF111520),
      title: const Text('Nova Senha Parental (4 dígitos)'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        decoration: const InputDecoration(
          hintText: 'Ex: 1234',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () async {
            final text = controller.text.trim();
            if (text.length == 4) {
              await _saveNewPin(text);
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

/// Alias compatível com chamadas legadas em `tv_screen.dart` ou `mobile_screen.dart`
Future<void> showParentalControlSettingsDialog(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) {
  return showChangeParentalPinDialog(context, deviceMode: deviceMode);
}

// ===========================================================================
// TECLADO VIRTUAL OTIMIZADO PARA CONTROLE REMOTO DE TV
// ===========================================================================
Future<void> showTVVirtualKeyboard(
  BuildContext context,
  TextEditingController controller,
  String title, {
  ValueChanged<String>? onChanged,
}) async {
  const keys = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9',
  ];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        void updateText(String newText) {
          controller.text = newText;
          onChanged?.call(newText);
          setModalState(() {});
        }

        return Dialog(
          backgroundColor: const Color(0xFF111520),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090B10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00E5FF)),
                    ),
                    child: Text(
                      controller.text.isEmpty ? 'Digite usando o controle...' : controller.text,
                      style: TextStyle(
                        fontSize: 15,
                        color: controller.text.isEmpty ? Colors.white38 : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (int i = 0; i < keys.length; i++)
                        TVFocusableItem(
                          autofocus: i == 0,
                          autoScroll: false,
                          onSelect: () => updateText(controller.text + keys[i]),
                          builder: (c, f) => Container(
                            width: 42,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: f ? const Color(0xFF00E5FF) : const Color(0xFF1A2030),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              keys[i],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: f ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => updateText('${controller.text} '),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: f ? const Color(0xFF00E5FF) : const Color(0xFF1A2030),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ESPAÇO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: f ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () {
                          if (controller.text.isNotEmpty) {
                            updateText(controller.text.substring(0, controller.text.length - 1));
                          }
                        },
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: f ? Colors.orangeAccent : const Color(0xFF1A2030),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'APAGAR',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: f ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => updateText(''),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: f ? Colors.redAccent : const Color(0xFF1A2030),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'LIMPAR',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => Navigator.pop(ctx),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: f ? Colors.white : const Color(0xFF00E5FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'CONCLUIR',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
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
