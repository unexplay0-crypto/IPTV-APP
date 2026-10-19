import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';
import 'widgets.dart';

enum VideoScaleMode { contain, cover, fill }

class SmartAdaptivePlayerScreen extends StatefulWidget {
  final StreamItem initialItem;
  final List<StreamItem> playlist;
  final DeviceMode deviceMode;
  final Duration? initialStartPosition;

  const SmartAdaptivePlayerScreen({
    super.key,
    required this.initialItem,
    required this.playlist,
    required this.deviceMode,
    this.initialStartPosition,
  });

  @override
  State<SmartAdaptivePlayerScreen> createState() => _SmartAdaptivePlayerScreenState();
}

class _SmartAdaptivePlayerScreenState extends State<SmartAdaptivePlayerScreen> {
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  late StreamItem currentItem;

  bool showOsd = true;
  bool showDrawer = false;
  Timer? _hideTimer;
  final FocusNode _playPauseNode = FocusNode();
  VideoScaleMode _scaleMode = VideoScaleMode.contain;

  // Variáveis para Gestos Táteis (Exclusivo Celular)
  double _gestureStartVolume = 0.5;
  double _gestureStartBrightness = 0.5;
  int _gestureSeekSeconds = 0;
  bool _isSeekingByGesture = false;
  String _gestureOverlayText = '';
  bool _adultUnlocked = false;

  @override
  void initState() {
    super.initState();
    // Isola a superfície de vídeo exclusivamente para a Tela Cheia
    _engine.setFullScreenActive(true);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    currentItem = widget.initialItem;
    if (currentItem.isAdult) _adultUnlocked = true;

    // Aguarda o frame inicial para garantir que o mini-player do painel já liberou a superfície
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_engine.currentItem?.id != currentItem.id || !_engine.isReady || _engine.hasError) {
        _engine.openStream(currentItem, startPosition: widget.initialStartPosition);
      } else if (widget.initialStartPosition != null && currentItem.type != ContentType.live) {
        _engine.controller?.seekTo(widget.initialStartPosition!);
        _engine.controller?.play();
      } else if (_engine.controller?.value.isPlaying == false) {
        _engine.controller?.play();
      }

      if (widget.deviceMode == DeviceMode.tv && _playPauseNode.canRequestFocus) {
        _playPauseNode.requestFocus();
      }
    });

    _resetOsdTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playPauseNode.dispose();

    // Se estava reproduzindo Filme ou Série (VOD), libera o decodificador ao sair da tela cheia
    if (currentItem.type != ContentType.live) {
      _engine.stopAndClear();
    }
    _engine.setFullScreenActive(false);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    applyDeviceOrientation(widget.deviceMode);
    super.dispose();
  }

  void _resetOsdTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !showDrawer && (_engine.controller?.value.isPlaying ?? false)) {
        setState(() => showOsd = false);
      }
    });
  }

  void _showAndResetOsd() {
    if (!showOsd) {
      setState(() => showOsd = true);
      if (widget.deviceMode == DeviceMode.tv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playPauseNode.canRequestFocus) {
            _playPauseNode.requestFocus();
          }
        });
      }
    }
    _resetOsdTimer();
  }

  void _toggleOsd() {
    if (showDrawer) {
      setState(() => showDrawer = false);
      _resetOsdTimer();
      return;
    }
    setState(() => showOsd = !showOsd);
    if (showOsd) {
      _resetOsdTimer();
      if (widget.deviceMode == DeviceMode.tv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playPauseNode.canRequestFocus) {
            _playPauseNode.requestFocus();
          }
        });
      }
    } else {
      _hideTimer?.cancel();
    }
  }

  void _handlePlayPause() {
    _engine.togglePlayPause();
    setState(() => showOsd = true);
    _resetOsdTimer();
  }

  Future<void> _switchStream(StreamItem item) async {
    if (item.isAdult && !_adultUnlocked) {
      _hideTimer?.cancel();
      final unlocked = await showParentalPinPrompt(context, deviceMode: widget.deviceMode);
      if (!unlocked || !mounted) {
        _resetOsdTimer();
        return;
      }
      setState(() => _adultUnlocked = true);
    }

    setState(() {
      currentItem = item;
      showOsd = true;
      showDrawer = false;
    });
    await _engine.openStream(item);
    _resetOsdTimer();
    if (widget.deviceMode == DeviceMode.tv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playPauseNode.canRequestFocus) {
          _playPauseNode.requestFocus();
        }
      });
    }
  }

  void _stepChannel(int delta) {
    if (widget.playlist.isEmpty) return;
    final idx = widget.playlist.indexWhere((i) => i.id == currentItem.id);
    if (idx == -1) return;
    final next = (idx + delta + widget.playlist.length) % widget.playlist.length;
    _switchStream(widget.playlist[next]);
  }

  void _cycleScaleMode() {
    setState(() {
      if (_scaleMode == VideoScaleMode.contain) {
        _scaleMode = VideoScaleMode.cover;
      } else if (_scaleMode == VideoScaleMode.cover) {
        _scaleMode = VideoScaleMode.fill;
      } else {
        _scaleMode = VideoScaleMode.contain;
      }
    });
    _resetOsdTimer();
  }

  String get _scaleModeLabel {
    switch (_scaleMode) {
      case VideoScaleMode.contain:
        return 'Original';
      case VideoScaleMode.cover:
        return 'Zoom';
      case VideoScaleMode.fill:
        return 'Esticar';
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mins:$secs' : '$mins:$secs';
  }

  // ===========================================================================
  // GESTOS TÁTEIS DE BRILHO, VOLUME E TEMPO (EXCLUSIVO CELULAR)
  // ===========================================================================
  void _onPanStart(DragStartDetails details) async {
    if (widget.deviceMode == DeviceMode.tv) return;
    _isSeekingByGesture = false;
    _gestureSeekSeconds = 0;
    try {
      _gestureStartVolume = await nativeChannel.invokeMethod('getVolume') ?? 0.5;
      _gestureStartBrightness = await nativeChannel.invokeMethod('getBrightness') ?? 0.5;
    } catch (_) {}
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.deviceMode == DeviceMode.tv) return;
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    if (details.delta.dx.abs() > details.delta.dy.abs() && currentItem.type != ContentType.live) {
      _isSeekingByGesture = true;
      _gestureSeekSeconds += (details.delta.dx / width * 180).round();
      setState(() {
        _gestureOverlayText =
            _gestureSeekSeconds >= 0 ? '+${_gestureSeekSeconds}s' : '${_gestureSeekSeconds}s';
      });
      return;
    }

    if (!_isSeekingByGesture) {
      final isLeftSide = details.globalPosition.dx < width / 2;
      final delta = -(details.delta.dy / height);

      if (isLeftSide) {
        _gestureStartBrightness = (_gestureStartBrightness + delta).clamp(0.05, 1.0);
        nativeChannel.invokeMethod('setBrightness', {'value': _gestureStartBrightness});
        setState(() {
          _gestureOverlayText = '☀ Brilho: ${(_gestureStartBrightness * 100).toInt()}%';
        });
      } else {
        _gestureStartVolume = (_gestureStartVolume + delta).clamp(0.0, 1.0);
        nativeChannel.invokeMethod('setVolume', {'value': _gestureStartVolume});
        setState(() {
          _gestureOverlayText = '🔊 Volume: ${(_gestureStartVolume * 100).toInt()}%';
        });
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.deviceMode == DeviceMode.tv) return;
    if (_isSeekingByGesture && _gestureSeekSeconds != 0) {
      _engine.seekRelative(_gestureSeekSeconds);
    }
    setState(() {
      _gestureOverlayText = '';
      _isSeekingByGesture = false;
    });
  }

  // ===========================================================================
  // SUPERFÍCIE DE VÍDEO COMPATÍVEL COM SURFACEVIEW NATIVA E TEXTUREVIEW
  // ===========================================================================
  Widget _buildVideoSurface(VideoPlayerController ctrl) {
    final surfaceKey = ValueKey('full_${currentItem.id}_${_engine.activeFormatLabel}');
    final rawRatio = ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : (16 / 9);

    if (_scaleMode == VideoScaleMode.fill) {
      return SizedBox.expand(
        child: VideoPlayer(ctrl, key: surfaceKey),
      );
    }

    if (_scaleMode == VideoScaleMode.cover) {
      final screenSize = MediaQuery.of(context).size;
      final screenRatio = screenSize.width / (screenSize.height > 0 ? screenSize.height : 1.0);
      final scale = rawRatio > screenRatio ? (rawRatio / screenRatio) : (screenRatio / rawRatio);
      return Center(
        child: Transform.scale(
          scale: scale.clamp(1.0, 1.5),
          child: AspectRatio(
            aspectRatio: rawRatio,
            child: VideoPlayer(ctrl, key: surfaceKey),
          ),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: rawRatio,
        child: VideoPlayer(ctrl, key: surfaceKey),
      ),
    );
  }

  // ===========================================================================
  // GAVETA LATERAL DE CANAIS / EPISÓDIOS
  // ===========================================================================
  Widget _buildSideDrawer() {
    if (!showDrawer) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 320,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF090B10).withOpacity(0.96),
          border: const Border(left: BorderSide(color: Colors.white12)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      currentItem.type == ContentType.live ? 'Lista de Canais' : 'Lista de Episódios',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF00E5FF),
                        fontSize: 15,
                      ),
                    ),
                    TVIconButton(
                      icon: Icons.close_rounded,
                      onPressed: () {
                        setState(() => showDrawer = false);
                        _resetOsdTimer();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: widget.playlist.length,
                  itemBuilder: (context, idx) {
                    final item = widget.playlist[idx];
                    final isPlaying = item.id == currentItem.id;
                    final isLocked = item.isAdult && !_adultUnlocked;
                    return TVFocusableItem(
                      autofocus: isPlaying && showDrawer && widget.deviceMode == DeviceMode.tv,
                      onSelect: () => _switchStream(item),
                      builder: (c, isFocused) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? const Color(0xFF00E5FF).withOpacity(0.16)
                              : isFocused
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent,
                            width: isFocused ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          leading: buildChannelLogo(item.logo, size: 38, isLocked: isLocked),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isPlaying || isFocused ? FontWeight.bold : FontWeight.normal,
                              color: isPlaying ? const Color(0xFF00E5FF) : Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            item.group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                          ),
                          trailing: isPlaying
                              ? const Icon(Icons.play_circle_fill, color: Color(0xFF00E5FF), size: 20)
                              : null,
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
  }

  // ===========================================================================
  // CONSTRUÇÃO PRINCIPAL DO PLAYER (TV + CELULAR)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final ctrl = _engine.controller;
        final isReady = _engine.isReady && ctrl != null && ctrl.value.isInitialized;
        final isVod = currentItem.type != ContentType.live;

        return PopScope(
          canPop: !showDrawer,
          onPopInvoked: (didPop) {
            if (!didPop && showDrawer) {
              setState(() => showDrawer = false);
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.mediaPlayPause) {
                    _handlePlayPause();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.channelUp ||
                      (!showOsd && !showDrawer && key == LogicalKeyboardKey.arrowUp)) {
                    _stepChannel(-1);
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.channelDown ||
                      (!showOsd && !showDrawer && key == LogicalKeyboardKey.arrowDown)) {
                    _stepChannel(1);
                    return KeyEventResult.handled;
                  }

                  if (!showOsd && !showDrawer && !_engine.hasError) {
                    if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.numpadEnter ||
                        key == LogicalKeyboardKey.gameButtonA) {
                      _showAndResetOsd();
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isVod) {
                        _engine.seekRelative(-10);
                        _showAndResetOsd();
                      } else {
                        setState(() => showDrawer = true);
                      }
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowRight) {
                      if (isVod) {
                        _engine.seekRelative(10);
                        _showAndResetOsd();
                      } else {
                        _showAndResetOsd();
                      }
                      return KeyEventResult.handled;
                    }
                  } else {
                    _resetOsdTimer();
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // CAMADA 1: VÍDEO OU TELA DE ERRO LIMPA
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleOsd,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: _engine.hasError
                        ? Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 520),
                              padding: const EdgeInsets.all(24),
                              margin: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101420),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.redAccent, width: 1.5),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 46),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Sinal Indisponível no Momento',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _engine.lastErrorDetails.isNotEmpty
                                        ? 'Detalhe: ${_engine.lastErrorDetails}'
                                        : 'Não foi possível decodificar este fluxo no momento.',
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 18),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      TVFocusableItem(
                                        autofocus: true,
                                        autoScroll: false,
                                        onSelect: () => _engine.openStream(
                                          currentItem,
                                          forceReload: true,
                                          tryHlsFallback: true,
                                        ),
                                        builder: (c, f) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                          decoration: BoxDecoration(
                                            color: f ? Colors.white : const Color(0xFF00E5FF),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'Tentar Modo Alternativo',
                                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                      ),
                                      TVFocusableItem(
                                        autoScroll: false,
                                        onSelect: () => Navigator.pop(context),
                                        builder: (c, f) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: f ? Colors.white : Colors.white24),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text('Voltar'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        : isReady
                            ? _buildVideoSurface(ctrl)
                            : const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(color: Color(0xFF00E5FF)),
                                    SizedBox(height: 12),
                                    Text(
                                      'Inicializando reprodutor de vídeo...',
                                      style: TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                  ),

                  // CAMADA 2: OVERLAY DE GESTOS NO CELULAR
                  if (_gestureOverlayText.isNotEmpty)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                        ),
                        child: Text(
                          _gestureOverlayText,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                    ),

                  // CAMADA 3: OSD ESTILO NETFLIX (OCULTO QUANDO HÁ ERRO PARA NUNCA SOBREPOR)
                  if (showOsd && !_engine.hasError)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleOsd,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black87,
                              Colors.black38,
                              Colors.transparent,
                              Colors.black45,
                              Colors.black87,
                            ],
                            stops: [0.0, 0.22, 0.5, 0.78, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          child: isReady
                              ? ValueListenableBuilder<VideoPlayerValue>(
                                  valueListenable: ctrl,
                                  builder: (context, val, _) => _buildOsdContent(val, isVod: isVod),
                                )
                              : _buildOsdContent(null, isVod: isVod),
                        ),
                      ),
                    ),

                  // CAMADA 4: GAVETA LATERAL DE CANAIS / EPISÓDIOS
                  _buildSideDrawer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOsdContent(VideoPlayerValue? val, {required bool isVod}) {
    final isPlaying = val?.isPlaying ?? false;
    final isBuffering = val?.isBuffering ?? false;
    final position = val?.position ?? Duration.zero;
    final duration = val?.duration ?? Duration.zero;
    final maxSeconds = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final curSeconds = position.inSeconds.toDouble().clamp(0.0, maxSeconds);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. BARRA SUPERIOR
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              TVIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                size: 22,
                color: Colors.white,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentItem.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${currentItem.group} • ${_engine.activeFormatLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              buildQualityBadge(currentItem.qualityTag),
              const SizedBox(width: 10),
              TVFocusableItem(
                autoScroll: false,
                onSelect: () {
                  _engine.openStream(currentItem, forceReload: true, tryHlsFallback: true);
                  _resetOsdTimer();
                },
                builder: (c, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: f ? const Color(0xFF00E5FF) : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Modo Alt.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: f ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TVFocusableItem(
                autoScroll: false,
                onSelect: _cycleScaleMode,
                builder: (c, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: f ? const Color(0xFF00E5FF) : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.aspect_ratio_rounded, size: 14, color: f ? Colors.black : Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _scaleModeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: f ? Colors.black : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. CONTROLES CENTRAIS GIGANTES
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TVIconButton(
              icon: isVod ? Icons.replay_10_rounded : Icons.skip_previous_rounded,
              size: 40,
              color: Colors.white,
              onPressed: () {
                if (isVod) {
                  _engine.seekRelative(-10);
                } else {
                  _stepChannel(-1);
                }
                _resetOsdTimer();
              },
            ),
            const SizedBox(width: 42),
            TVFocusableItem(
              focusNode: _playPauseNode,
              autofocus: true,
              autoScroll: false,
              onSelect: _handlePlayPause,
              builder: (c, f) => AnimatedScale(
                scale: f ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 130),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: f ? const Color(0xFF00E5FF) : Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: f ? Colors.white : const Color(0xFF00E5FF),
                      width: 2.5,
                    ),
                  ),
                  child: isBuffering
                      ? SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: f ? Colors.black : const Color(0xFF00E5FF),
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 48,
                          color: f ? Colors.black : Colors.white,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 42),
            TVIconButton(
              icon: isVod ? Icons.forward_10_rounded : Icons.skip_next_rounded,
              size: 40,
              color: Colors.white,
              onPressed: () {
                if (isVod) {
                  _engine.seekRelative(10);
                } else {
                  _stepChannel(1);
                }
                _resetOsdTimer();
              },
            ),
          ],
        ),

        // 3. BARRA INFERIOR
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isVod && val != null)
                Row(
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          activeTrackColor: const Color(0xFF00E5FF),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: const Color(0xFF00E5FF),
                        ),
                        child: Slider(
                          value: curSeconds,
                          min: 0.0,
                          max: maxSeconds,
                          onChanged: (newVal) {
                            _engine.controller?.seekTo(Duration(seconds: newVal.toInt()));
                            _resetOsdTimer();
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isVod)
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'AO VIVO',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (_engine.currentEpg != null)
                            Expanded(
                              child: Text(
                                '${_engine.currentEpg!.nowTitle}  •  ${_engine.currentEpg!.nextTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    const Text(
                      'Use -10s / +10s ou a barra de tempo para avançar',
                      style: TextStyle(fontSize: 11.5, color: Colors.white54),
                    ),
                  const SizedBox(width: 16),
                  TVFocusableItem(
                    autoScroll: false,
                    onSelect: () {
                      setState(() => showDrawer = true);
                      _hideTimer?.cancel();
                    },
                    builder: (c, f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: f ? const Color(0xFF00E5FF) : Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: f ? Colors.white : Colors.white24,
                          width: f ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 18,
                            color: f ? Colors.black : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isVod ? 'Episódios / Lista' : 'Lista de Canais',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: f ? Colors.black : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
