import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';

// ===========================================================================
// COMPONENTE DE FOCO UNIVERSAL PARA CONTROLE REMOTO (CLIQUE CURTO + SEGURAR OK)
// ===========================================================================
class TVFocusableItem extends StatefulWidget {
  final Widget Function(BuildContext context, bool isFocused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final VoidCallback? onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool autoScroll;

  const TVFocusableItem({
    super.key,
    required this.builder,
    this.onSelect,
    this.onLongSelect,
    this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.autofocus = false,
    this.focusNode,
    this.autoScroll = true,
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
  bool _longSelectTriggered = false;

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
    if (widget.focusNode != oldWidget.focusNode) {
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
      _cancelHoldTimer();
    }
    if (_isFocused != hasFocus) {
      setState(() => _isFocused = hasFocus);
    }
    if (hasFocus) {
      widget.onFocus?.call();
      if (widget.autoScroll) {
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
  }

  void _cancelHoldTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _isSelectKeyDown = false;
    _longSelectTriggered = false;
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

    // Tratamento do botão OK (Clique rápido vs Segurar o botão OK para Favoritar)
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
          _longSelectTriggered = false;
          _longPressTimer?.cancel();
          _longPressTimer = Timer(const Duration(milliseconds: 520), () {
            if (mounted && _isSelectKeyDown && !_longSelectTriggered) {
              _longSelectTriggered = true;
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
        final wasLong = _longSelectTriggered;
        _isSelectKeyDown = false;
        _longSelectTriggered = false;
        if (!wasLong) {
          widget.onSelect?.call();
        }
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

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
        onTap: () {
          if (!_node.hasFocus && _node.canRequestFocus) {
            _node.requestFocus();
          }
          widget.onSelect?.call();
        },
        onLongPress: widget.onLongSelect != null
            ? () {
                HapticFeedback.mediumImpact();
                widget.onLongSelect?.call();
              }
            : null,
        child: widget.builder(context, _isFocused),
      ),
    );
  }
}

// ===========================================================================
// BOTÃO DE ÍCONE COM FOCO PARA TV E MOBILE
// ===========================================================================
class TVIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final double size;
  final String? tooltip;

  const TVIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
    this.size = 20,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      autoScroll: false,
      onSelect: onPressed,
      builder: (context, isFocused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: isFocused ? Colors.white : Colors.white12,
            width: isFocused ? 1.8 : 1,
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
// BADGES E COMPONENTES VISUAIS DE CATÁLOGO
// ===========================================================================
Widget buildQualityBadge(String qualityTag) {
  final tag = qualityTag.trim().toUpperCase();
  Color badgeColor = const Color(0xFF00E5FF);
  if (tag.contains('4K') || tag.contains('UHD')) {
    badgeColor = const Color(0xFFFFD740);
  } else if (tag.contains('FHD') || tag.contains('1080')) {
    badgeColor = const Color(0xFF00E5FF);
  } else if (tag.contains('SD')) {
    badgeColor = Colors.white54;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: badgeColor.withOpacity(0.16),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: badgeColor.withOpacity(0.6), width: 0.9),
    ),
    child: Text(
      tag.isEmpty ? 'HD' : tag,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        color: badgeColor,
        letterSpacing: 0.5,
      ),
    ),
  );
}

Widget buildAudioOptionBadge(String label, {bool isDual = false}) {
  final badgeColor = isDual ? const Color(0xFF00E676) : const Color(0xFFFFAB40);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
    decoration: BoxDecoration(
      color: badgeColor.withOpacity(0.18),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: badgeColor.withOpacity(0.65), width: 1),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        color: badgeColor,
        letterSpacing: 0.4,
      ),
    ),
  );
}

Widget buildChannelLogo(String? logoUrl, {double size = 44, bool isLocked = false}) {
  if (isLocked) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Icon(Icons.lock_rounded, color: Colors.redAccent, size: size * 0.48),
    );
  }

  final cleanUrl = (logoUrl ?? '').trim();
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF0B0E17),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    clipBehavior: Clip.antiAlias,
    child: cleanUrl.isEmpty
        ? Icon(Icons.tv_rounded, color: Colors.white30, size: size * 0.5)
        : Image.network(
            cleanUrl,
            fit: BoxFit.contain,
            cacheWidth: (size * 2).toInt(),
            errorBuilder: (_, __, ___) =>
                Icon(Icons.tv_rounded, color: Colors.white30, size: size * 0.5),
          ),
  );
}

Widget buildStreamingPosterCard({
  required String title,
  required String subtitle,
  String? logoUrl,
  String? badgeText,
  bool isFocused = false,
  bool isFavorite = false,
  bool isAdultLocked = false,
  bool hasDualAudio = false,
  bool isSubtitledOnly = false,
  double? progress,
  VoidCallback? onTap,
}) {
  final cleanLogo = (logoUrl ?? '').trim();

  return AnimatedScale(
    scale: isFocused ? 1.06 : 1.0,
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFF151A28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFocused ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.08),
          width: isFocused ? 2.6 : 1.0,
        ),
        boxShadow: isFocused
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
              color: const Color(0xFF10131D),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, color: Colors.redAccent, size: 38),
                  SizedBox(height: 6),
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
          else if (cleanLogo.isNotEmpty)
            Image.network(
              cleanLogo,
              fit: BoxFit.cover,
              cacheWidth: 300,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF151A28),
                child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 42),
              ),
            )
          else
            Container(
              color: const Color(0xFF151A28),
              child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 42),
            ),

          // Gradiente escuro para leitura do título na base do card
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.25),
                  Colors.transparent,
                  Colors.black.withOpacity(0.92),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),

          // Badges no topo do card
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (badgeText != null && badgeText.isNotEmpty)
                  buildQualityBadge(badgeText)
                else
                  const SizedBox.shrink(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasDualAudio)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withOpacity(0.88),
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
                    if (isFavorite) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Rodapé com título, categoria e barra de progresso
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isFocused ? const Color(0xFF00E5FF) : Colors.white54,
                    fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
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
// MODAL DE TESTE DE VELOCIDADE DA INTERNET COM RECOMENDAÇÃO DE RESOLUÇÃO
// ===========================================================================
Future<void> showSpeedTestDialog(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) async {
  await showDialog(
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
  bool _isRunning = false;
  bool _isCompleted = false;
  String? _errorMsg;
  double _currentMbps = 0.0;
  double _progress = 0.0;

  static const List<String> _testUrls = [
    'https://speed.cloudflare.com/__down?bytes=15000000',
    'https://proof.ovh.net/files/10Mb.dat',
    'https://ash-speed.hetzner.com/10MB.bin',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startSpeedTest();
    });
  }

  Future<void> _startSpeedTest() async {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _isCompleted = false;
      _errorMsg = null;
      _currentMbps = 0.0;
      _progress = 0.05;
    });

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      HttpClientResponse? response;

      for (final url in _testUrls) {
        try {
          final request = await client.getUrl(Uri.parse(url));
          request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
          response = await request.close().timeout(const Duration(seconds: 8));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            break;
          }
        } catch (_) {
          response = null;
        }
      }

      if (response == null) {
        throw const SocketException('Sem resposta dos servidores de teste');
      }

      int totalBytes = 0;
      final stopwatch = Stopwatch()..start();
      const int maxDurationMs = 5500;

      await for (final chunk in response) {
        if (!mounted) break;
        totalBytes += chunk.length;
        final elapsedMs = stopwatch.elapsedMilliseconds;

        if (elapsedMs > 150) {
          final seconds = elapsedMs / 1000.0;
          final bits = totalBytes * 8.0;
          final mbps = (bits / seconds) / 1000000.0;

          setState(() {
            _currentMbps = mbps;
            _progress = (elapsedMs / maxDurationMs).clamp(0.08, 0.98);
          });
        }

        if (elapsedMs >= maxDurationMs) {
          break;
        }
      }

      stopwatch.stop();
      if (!mounted) return;

      if (totalBytes == 0) {
        throw const SocketException('Dados insuficientes');
      }

      final totalSeconds = (stopwatch.elapsedMilliseconds / 1000.0).clamp(0.5, 20.0);
      final finalMbps = ((totalBytes * 8.0) / totalSeconds) / 1000000.0;

      setState(() {
        _currentMbps = finalMbps;
        _progress = 1.0;
        _isRunning = false;
        _isCompleted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _isCompleted = false;
        _errorMsg = 'Não foi possível medir a velocidade. Verifique sua conexão com a internet.';
      });
    } finally {
      client?.close(force: true);
    }
  }

  Map<String, dynamic> _getResolutionSuggestion(double mbps) {
    if (mbps >= 25.0) {
      return {
        'badge': '4K / ULTRA HD & FULL HD',
        'color': const Color(0xFF00E676),
        'description':
            'Excelente velocidade! Sua internet suporta canais e filmes em 4K, Full HD (1080p) e HD com máxima estabilidade.',
      };
    } else if (mbps >= 12.0) {
      return {
        'badge': 'FULL HD (1080p) & HD',
        'color': const Color(0xFF00E5FF),
        'description':
            'Ótima conexão! Recomendamos assistir canais e filmes em Full HD (FHD) ou HD para reprodução fluida e sem travamentos.',
      };
    } else if (mbps >= 5.0) {
      return {
        'badge': 'HD (720p)',
        'color': Colors.amber,
        'description':
            'Conexão moderada. Recomendamos dar preferência aos canais em qualidade HD ou SD para evitar pausas de carregamento.',
      };
    } else {
      return {
        'badge': 'SD (DEFINIÇÃO PADRÃO)',
        'color': Colors.orangeAccent,
        'description':
            'Velocidade baixa no momento. Recomendamos selecionar canais em resolução SD para assistir sem congelamentos.',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _getResolutionSuggestion(_currentMbps);
    final Color accentColor = suggestion['color'] as Color;

    return Dialog(
      backgroundColor: const Color(0xFF111520),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
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
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Diagnóstico de conexão e sugestão de resolução',
                          style: TextStyle(fontSize: 11.5, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Medidor Principal em Mbps
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
                    Text(
                      _currentMbps.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: _isCompleted ? accentColor : const Color(0xFF00E5FF),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mbps (Megabits por segundo)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _isRunning ? _progress : (_isCompleted ? 1.0 : 0.0),
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        color: _isCompleted ? accentColor : const Color(0xFF00E5FF),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRunning
                          ? 'Medindo estabilidade e taxa de download...'
                          : _isCompleted
                              ? 'Teste concluído com sucesso'
                              : 'Aguardando início',
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],

              // Card de Recomendação de Resolução
              if (_isCompleted && _errorMsg == null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withOpacity(0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_rounded, color: accentColor, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'RESOLUÇÃO RECOMENDADA:',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white70,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        suggestion['badge'] as String,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        suggestion['description'] as String,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Botões de Ação (Refazer / Fechar)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isRunning)
                    TVFocusableItem(
                      autoScroll: false,
                      onSelect: _startSpeedTest,
                      builder: (c, f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: f ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Refazer Teste',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
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
  }
}

// ===========================================================================
// CONTROLE PARENTAL E TECLADO VIRTUAL DA TV
// ===========================================================================
Future<bool> showParentalPinPrompt(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.mobile,
}) async {
  final savedPin = await ParentalControlManager.getPin();
  if (!context.mounted) return false;

  String typedPin = '';
  String? errorText;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          void addDigit(String d) {
            if (typedPin.length < 4) {
              setModalState(() {
                typedPin += d;
                errorText = null;
              });
              if (typedPin.length == 4) {
                if (typedPin == savedPin) {
                  Navigator.pop(ctx, true);
                } else {
                  setModalState(() {
                    typedPin = '';
                    errorText = 'Senha incorreta. Tente novamente.';
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
                    const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 34),
                    const SizedBox(height: 10),
                    const Text(
                      'Controle Parental (+18)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Digite a senha de 4 dígitos (Padrão: 0000)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final filled = i < typedPin.length;
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
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
                           SizedBox(
                            width: 68,
                            height: 42,
                            child: TVFocusableItem(
                              autofocus: d == '1',
                              autoScroll: false,
                              onSelect: () => addDigit(d),
                              builder: (c, f) => Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: f ? const Color(0xFF00E5FF) : const Color(0xFF1A2030),
                                  borderRadius: BorderRadius.circular(10),
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
                          ),
                        SizedBox(
                          width: 68,
                          height: 42,
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: () => Navigator.pop(ctx, false),
                            builder: (c, f) => Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: f ? Colors.redAccent : Colors.white10,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.close, size: 18, color: Colors.white),
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
      );
    },
  );

  return result ?? false;
}

Future<void> showChangeParentalPinDialog(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.mobile,
}) async {
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  String? errorMsg;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => AlertDialog(
        backgroundColor: const Color(0xFF111520),
        title: const Text(
          'Alterar Senha Parental',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Senha Atual (Padrão: 0000)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Nova Senha (4 dígitos)',
                counterText: '',
              ),
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 10),
              Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final saved = await ParentalControlManager.getPin();
              if (currentCtrl.text.trim() != saved) {
                setModalState(() => errorMsg = 'A senha atual está incorreta.');
                return;
              }
              if (newCtrl.text.trim().length != 4) {
                setModalState(() => errorMsg = 'A nova senha deve ter 4 dígitos.');
                return;
              }
              await ParentalControlManager.setPin(newCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

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

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        void updateText(String newText) {
          controller.text = newText;
          setModalState(() {});
          onChanged?.call(newText);
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
              padding: const EdgeInsets.all(20),
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
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (int i = 0; i < keys.length; i++)
                        SizedBox(
                          width: 42,
                          height: 38,
                          child: TVFocusableItem(
                            autofocus: i == 0,
                            autoScroll: false,
                            onSelect: () => updateText(controller.text + keys[i]),
                            builder: (c, f) => Container(
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
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildKeyboardActionBtn('ESPAÇO', () => updateText('${controller.text} ')),
                      const SizedBox(width: 8),
                      _buildKeyboardActionBtn('APAGAR', () {
                        if (controller.text.isNotEmpty) {
                          updateText(controller.text.substring(0, controller.text.length - 1));
                        }
                      }),
                      const SizedBox(width: 8),
                      _buildKeyboardActionBtn('LIMPAR', () => updateText('')),
                      const SizedBox(width: 8),
                      _buildKeyboardActionBtn(
                        'CONCLUIR',
                        () => Navigator.pop(ctx),
                        isPrimary: true,
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

Widget _buildKeyboardActionBtn(
  String label,
  VoidCallback onTap, {
  bool isPrimary = false,
}) {
  return TVFocusableItem(
    autoScroll: false,
    onSelect: onTap,
    builder: (c, f) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: f
            ? Colors.white
            : isPrimary
                ? const Color(0xFF00E5FF)
                : const Color(0xFF1A2030),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: (f || isPrimary) ? Colors.black : Colors.white,
        ),
      ),
    ),
  );
}
