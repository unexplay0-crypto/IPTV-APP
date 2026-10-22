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

  // Os controles só aparecem após o conteúdo estar carregado (isReady == true)
  bool showOsd = false;
  bool showDrawer = false;
  bool _wasReady = false;

  Timer? _hideTimer;
  Timer? _seekFeedbackTimer;
  String _seekFeedbackText = '';
  // Aceleração exponencial ao segurar ← / → no controle da TV (10→20→40→80→160s)
  int _seekRepeatCount = 0;
  LogicalKeyboardKey? _lastSeekKey;
  DateTime _lastSeekTime = DateTime.now();

  final FocusNode _playPauseNode = FocusNode();
  final FocusNode _channelsBtnNode = FocusNode();
  final FocusNode _scaleBtnNode = FocusNode();
  final FocusNode _signalBtnNode = FocusNode();
  final FocusNode _backBtnNode = FocusNode();

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
    // BLINDAGEM DO PLAYER: Isola a superfície de vídeo exclusivamente para a Tela Cheia
    _engine.setFullScreenActive(true);
    _engine.addListener(_onEngineStateChanged);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    currentItem = widget.initialItem;
    if (currentItem.isAdult) _adultUnlocked = true;

    final alreadyPlayingThis = _engine.currentItem?.id == currentItem.id &&
        _engine.isReady &&
        !_engine.hasError &&
        (_engine.controller?.value.isInitialized ?? false);

    _wasReady = alreadyPlayingThis;
    showOsd = alreadyPlayingThis;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!alreadyPlayingThis) {
        _engine.openStream(currentItem, startPosition: widget.initialStartPosition);
      } else {
        if (widget.initialStartPosition != null && currentItem.type != ContentType.live) {
          _engine.controller?.seekTo(widget.initialStartPosition!);
        }
        if (_engine.controller?.value.isPlaying == false) {
          _engine.controller?.play();
        }
        _focusPlayPauseAndStartTimer();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _engine.removeListener(_onEngineStateChanged);

    _playPauseNode.dispose();
    _channelsBtnNode.dispose();
    _scaleBtnNode.dispose();
    _signalBtnNode.dispose();
    _backBtnNode.dispose();

    // BLINDAGEM DO PLAYER: Encerra VOD ao sair e devolve controle de superfície
    if (currentItem.type != ContentType.live) {
      _engine.stopAndClear();
    }
    _engine.setFullScreenActive(false);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    applyDeviceOrientation(widget.deviceMode);
    super.dispose();
  }

  /// Monitora o término do carregamento:
  /// - Enquanto carrega (!isReady): oculta todos os controles (mostra apenas o loading).
  /// - Assim que carrega (isReady == true): exibe os controles e inicia o timer de 3 segundos.
  void _onEngineStateChanged() {
    if (!mounted) return;
    final isNowReady = _engine.isReady &&
        _engine.controller != null &&
        _engine.controller!.value.isInitialized &&
        !_engine.hasError;

    if (!isNowReady) {
      if (_wasReady || showOsd) {
        setState(() {
          _wasReady = false;
          showOsd = false;
        });
      }
      _hideTimer?.cancel();
      return;
    }

    if (!_wasReady && isNowReady) {
      setState(() {
        _wasReady = true;
        showOsd = true;
      });
      _focusPlayPauseAndStartTimer();
    }
  }

  void _focusPlayPauseAndStartTimer() {
    _resetOsdTimer();
    if (widget.deviceMode == DeviceMode.tv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && showOsd && !showDrawer && _playPauseNode.canRequestFocus) {
          _playPauseNode.requestFocus();
        }
      });
    }
  }

  /// Oculta automaticamente os controles após exatos 3 segundos
  void _resetOsdTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !showDrawer && _engine.isReady) {
        setState(() => showOsd = false);
      }
    });
  }

  void _showControlsFromConfirmButton() {
    if (!_engine.isReady || _engine.hasError) return;
    setState(() => showOsd = true);
    _focusPlayPauseAndStartTimer();
  }

  void _toggleOsdByTouch() {
    if (!_engine.isReady || _engine.hasError) return;
    if (showDrawer) {
      setState(() => showDrawer = false);
      _resetOsdTimer();
      return;
    }
    setState(() => showOsd = !showOsd);
    if (showOsd) {
      _focusPlayPauseAndStartTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _handlePlayPause() {
    if (!_engine.isReady) return;
    _engine.togglePlayPause();
    setState(() => showOsd = true);
    _resetOsdTimer();
  }

  /// Avança (+10s) ou Retrocede (-10s) imediatamente em Filmes e Séries,
  /// funcionando mesmo quando os controles do player estão ocultos.
  void _triggerQuickSeek(int seconds) {
    if (currentItem.type == ContentType.live || !_engine.isReady) return;
    _engine.seekRelative(seconds);

    _seekFeedbackTimer?.cancel();
    setState(() {
      _seekFeedbackText = seconds > 0 ? '+${seconds}s  ▶▶' : '◀◀  ${seconds}s';
      showOsd = true;
    });

    if (widget.deviceMode == DeviceMode.tv && _playPauseNode.canRequestFocus) {
      _playPauseNode.requestFocus();
    }

    _seekFeedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _seekFeedbackText = '');
      }
    });

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

    _hideTimer?.cancel();
    setState(() {
      currentItem = item;
      _wasReady = false;
      showOsd = false;
      showDrawer = false;
    });
    await _engine.openStream(item);
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
    if (widget.deviceMode == DeviceMode.tv || !_engine.isReady) return;
    _isSeekingByGesture = false;
    _gestureSeekSeconds = 0;
    try {
      _gestureStartVolume = await nativeChannel.invokeMethod('getVolume') ?? 0.5;
      _gestureStartBrightness = await nativeChannel.invokeMethod('getBrightness') ?? 0.5;
    } catch (_) {}
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.deviceMode == DeviceMode.tv || !_engine.isReady) return;
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
          _gestureOverlayText = '☀ ${(_gestureStartBrightness * 100).toInt()}%';
        });
      } else {
        _gestureStartVolume = (_gestureStartVolume + delta).clamp(0.0, 1.0);
        nativeChannel.invokeMethod('setVolume', {'value': _gestureStartVolume});
        setState(() {
          _gestureOverlayText = '🔊 ${(_gestureStartVolume * 100).toInt()}%';
        });
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.deviceMode == DeviceMode.tv) return;
    if (_isSeekingByGesture && _gestureSeekSeconds != 0) {
      _triggerQuickSeek(_gestureSeekSeconds);
    }
    setState(() {
      _gestureOverlayText = '';
      _isSeekingByGesture = false;
    });
  }

  // ===========================================================================
  // SUPERFÍCIE DE VÍDEO BLINDADA (SURFACEVIEW NATIVA + TEXTUREVIEW)
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
  // GAVETA LATERAL MINIMALISTA DE CANAIS / EPISÓDIOS
  // ===========================================================================
  Widget _buildSideDrawer() {
    if (!showDrawer) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 330,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0D14).withOpacity(0.95),
          border: Border(left: BorderSide(color: Colors.white.withOpacity(0.08))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              blurRadius: 24,
              offset: const Offset(-6, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          currentItem.type == ContentType.live
                              ? Icons.live_tv_rounded
                              : Icons.video_library_rounded,
                          color: const Color(0xFF00E5FF),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currentItem.type == ContentType.series ? 'Episódios' : 'Canais',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    TVIconButton(
                      icon: Icons.close_rounded,
                      size: 18,
                      onPressed: () {
                        setState(() => showDrawer = false);
                        _focusPlayPauseAndStartTimer();
                      },
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.06), height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: widget.playlist.length,
                  itemBuilder: (context, idx) {
                    final item = widget.playlist[idx];
                    final isPlaying = item.id == currentItem.id;
                    final isLocked = item.isAdult && !_adultUnlocked;
                    return TVFocusableItem(
                      autofocus: isPlaying && showDrawer && widget.deviceMode == DeviceMode.tv,
                      onMoveLeft: () {
                        setState(() => showDrawer = false);
                        _focusPlayPauseAndStartTimer();
                      },
                      onSelect: () => _switchStream(item),
                      builder: (c, isFocused) => AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? const Color(0xFF00E5FF).withOpacity(0.14)
                              : isFocused
                                  ? Colors.white.withOpacity(0.09)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF00E5FF)
                                : (isPlaying
                                    ? const Color(0xFF00E5FF).withOpacity(0.35)
                                    : Colors.transparent),
                            width: isFocused ? 1.8 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            buildChannelLogo(item.logo, size: 36, isLocked: isLocked),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight:
                                          isPlaying || isFocused ? FontWeight.w800 : FontWeight.w500,
                                      color: isPlaying ? const Color(0xFF00E5FF) : Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.group,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                                  ),
                                ],
                              ),
                            ),
                            if (isPlaying)
                              const Icon(
                                Icons.equalizer_rounded,
                                color: Color(0xFF00E5FF),
                                size: 18,
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
  }

  // ===========================================================================
  // CONSTRUÇÃO PRINCIPAL DO PLAYER (CARREGAMENTO LIMPO + CONTROLE REMOTO)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final ctrl = _engine.controller;
        final isReady = _engine.isReady && ctrl != null && ctrl.value.isInitialized && !_engine.hasError;
        final isVod = currentItem.type != ContentType.live;

        return PopScope(
          canPop: !showDrawer && !showOsd,
          onPopInvoked: (didPop) {
            if (didPop) return;
            if (showDrawer) {
              setState(() => showDrawer = false);
              _focusPlayPauseAndStartTimer();
            } else if (showOsd) {
              // 1ª pressão de Voltar: apenas esconde os controles do player
              _hideTimer?.cancel();
              setState(() => showOsd = false);
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;

                // Se houver erro ou ainda estiver carregando, não exibe OSD nem processa atalhos de mídia
                if (_engine.hasError || !isReady) {
                  return KeyEventResult.ignored;
                }

                // Se a gaveta lateral de canais/episódios estiver aberta, deixa a lista navegar normalmente
                if (showDrawer) {
                  return KeyEventResult.ignored;
                }

                // Tecla dedicada de Play/Pause do controle
                if (key == LogicalKeyboardKey.mediaPlayPause) {
                  _handlePlayPause();
                  return KeyEventResult.handled;
                }

                // REGRA FILMES E SÉRIES: Setas Esquerda e Direita SEMPRE retrocedem/avançam 10s
                // (estejam os controles visíveis na tela ou ocultos, exceto quando navegando nos botões inferiores)
                final isBottomPillFocused = _channelsBtnNode.hasFocus ||
                    _scaleBtnNode.hasFocus ||
                    _signalBtnNode.hasFocus ||
                    _backBtnNode.hasFocus;

                if (isVod && !isBottomPillFocused) {
                  final now = DateTime.now();
                  final isRepeat = _lastSeekKey == key &&
                      now.difference(_lastSeekTime).inMilliseconds < 600;
                  _lastSeekKey = key;
                  _lastSeekTime = now;
                  if (isRepeat) {
                    _seekRepeatCount = (_seekRepeatCount + 1).clamp(0, 4);
                  } else {
                    _seekRepeatCount = 0;
                  }
                  final step = 10 * (1 << _seekRepeatCount); // 10, 20, 40, 80, 160s
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _triggerQuickSeek(-step);
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowRight) {
                    _triggerQuickSeek(step);
                    return KeyEventResult.handled;
                  }
                }

                // Quando os controles estão ocultos na tela cheia:
                if (!showOsd) {
                  // Botão do meio de confirmar (OK / Enter / Select) abre os controles para Play/Pause
                  if (key == LogicalKeyboardKey.select ||
                      key == LogicalKeyboardKey.enter ||
                      key == LogicalKeyboardKey.numpadEnter ||
                      key == LogicalKeyboardKey.gameButtonA) {
                    _showControlsFromConfirmButton();
                    return KeyEventResult.handled;
                  }
                  // Em TV ao Vivo, seta esquerda abre o menu de canais; demais direções apenas acordam o OSD
                  if (!isVod && key == LogicalKeyboardKey.arrowLeft && widget.playlist.isNotEmpty) {
                    setState(() => showDrawer = true);
                    _hideTimer?.cancel();
                    return KeyEventResult.handled;
                  }
                  // Zapping de canais para cima/baixo foi completamente removido conforme solicitado
                  if (key == LogicalKeyboardKey.arrowUp ||
                      key == LogicalKeyboardKey.arrowDown ||
                      key == LogicalKeyboardKey.channelUp ||
                      key == LogicalKeyboardKey.channelDown) {
                    return KeyEventResult.handled;
                  }
                } else {
                  // Controles visíveis: qualquer interação reinicia a contagem de 3 segundos
                  _resetOsdTimer();
                }

                return KeyEventResult.ignored;
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // CAMADA 1: VÍDEO OU INDICADOR DE CARREGAMENTO LIMPO (SEM BOTÕES DURANTE O LOADING)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleOsdByTouch,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: _engine.hasError
                        ? _buildMinimalErrorState()
                        : isReady
                            ? _buildVideoSurface(ctrl)
                            : _buildMinimalLoadingState(),
                  ),

                  // CAMADA 2: FEEDBACK DISCRETO DE AVANÇO/RETROCESSO (-10s / +10s) OU GESTOS
                  if (_seekFeedbackText.isNotEmpty || _gestureOverlayText.isNotEmpty)
                    Center(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 130),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0D14).withOpacity(0.82),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: const Color(0xFF00E5FF).withOpacity(0.6),
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            _seekFeedbackText.isNotEmpty ? _seekFeedbackText : _gestureOverlayText,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF00E5FF),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // CAMADA 3: CONTROLES MINIMALISTAS (SÓ APARECEM APÓS CARREGAR E SOMEM EM 3 SEGUNDOS)
                  if (isReady && !_engine.hasError)
                    AnimatedOpacity(
                      opacity: showOsd ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !showOsd,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _toggleOsdByTouch,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.72),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.82),
                                ],
                                stops: const [0.0, 0.22, 0.68, 1.0],
                              ),
                            ),
                            child: SafeArea(
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: ctrl,
                                builder: (context, val, _) =>
                                    _buildMinimalistOsdContent(val, isVod: isVod),
                              ),
                            ),
                          ),
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

  // ===========================================================================
  // ESTADO DE CARREGAMENTO LIMPO (EXIBE APENAS O ÍCONE DE CARREGAMENTO)
  // ===========================================================================
  Widget _buildMinimalLoadingState() {
    return const Center(
      child: SizedBox(
        width: 38,
        height: 38,
        child: CircularProgressIndicator(
          strokeWidth: 2.8,
          color: Color(0xFF00E5FF),
        ),
      ),
    );
  }

  // ===========================================================================
  // ESTADO DE ERRO MINIMALISTA E ELEGANTE
  // ===========================================================================
  Widget _buildMinimalErrorState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0E121C).withOpacity(0.95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_tethering_error_rounded, color: Colors.redAccent, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Transmissão Indisponível',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _engine.lastErrorDetails.isNotEmpty
                  ? _engine.lastErrorDetails
                  : 'Não foi possível reproduzir este conteúdo no momento.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: f ? Colors.white : const Color(0xFF00E5FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Tentar Novamente',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TVFocusableItem(
                  autoScroll: false,
                  onSelect: () => Navigator.pop(context),
                  builder: (c, f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: f ? Colors.white12 : Colors.transparent,
                      border: Border.all(color: f ? Colors.white : Colors.white24),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Voltar', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DESIGN MINIMALISTA, ELEGANTE E INTUITIVO DO PLAYER (OSD)
  // ===========================================================================
  Widget _buildMinimalistOsdContent(VideoPlayerValue val, {required bool isVod}) {
    final isPlaying = val.isPlaying;
    final isBuffering = val.isBuffering;
    final position = val.position;
    final duration = val.duration;
    final maxSeconds = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final curSeconds = position.inSeconds.toDouble().clamp(0.0, maxSeconds);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. TOPO MINIMALISTA: Botão Voltar Sutil + Título e Categoria + Tag Discreta
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Row(
            children: [
              TVFocusableItem(
                focusNode: _backBtnNode,
                autoScroll: false,
                onMoveDown: () {
                  if (_playPauseNode.canRequestFocus) _playPauseNode.requestFocus();
                },
                onSelect: () => Navigator.pop(context),
                builder: (c, f) => AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: f ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: f ? Colors.white : Colors.white24,
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 19,
                    color: f ? Colors.black : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentItem.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentItem.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white60,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              buildQualityBadge(currentItem.qualityTag),
            ],
          ),
        ),

        // 2. CENTRO MINIMALISTA: Play/Pause Elegante e Indicadores Intuitivos (-10s / +10s em VOD)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isVod) ...[
              GestureDetector(
                onTap: () => _triggerQuickSeek(-10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.38),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 22),
                ),
              ),
              const SizedBox(width: 28),
            ],

            // Botão Central Principal de Play / Pause
            TVFocusableItem(
              focusNode: _playPauseNode,
              autofocus: true,
              autoScroll: false,
              onMoveUp: () {
                if (_backBtnNode.canRequestFocus) _backBtnNode.requestFocus();
              },
              onMoveDown: () {
                if (widget.playlist.isNotEmpty && _channelsBtnNode.canRequestFocus) {
                  _channelsBtnNode.requestFocus();
                } else if (_scaleBtnNode.canRequestFocus) {
                  _scaleBtnNode.requestFocus();
                }
              },
              onSelect: _handlePlayPause,
              builder: (c, f) => AnimatedScale(
                scale: f ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: f
                        ? const Color(0xFF00E5FF)
                        : Colors.black.withOpacity(0.48),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: f ? Colors.white : Colors.white.withOpacity(0.28),
                      width: f ? 2.0 : 1.2,
                    ),
                    boxShadow: f
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withOpacity(0.35),
                              blurRadius: 18,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isBuffering
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: f ? Colors.black : const Color(0xFF00E5FF),
                            ),
                          )
                        : Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 32,
                            color: f ? Colors.black : Colors.white,
                          ),
                  ),
                ),
              ),
            ),

            if (isVod) ...[
              const SizedBox(width: 28),
              GestureDetector(
                onTap: () => _triggerQuickSeek(10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.38),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 22),
                ),
              ),
            ],
          ],
        ),

        // 3. DOCK INFERIOR FLUTUANTE MINIMALISTA
        Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1018).withOpacity(0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barra de tempo fina e elegante para Filmes e Séries
              if (isVod) ...[
                Row(
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.0,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                          activeTrackColor: const Color(0xFF00E5FF),
                          inactiveTrackColor: Colors.white.withOpacity(0.18),
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
                    const SizedBox(width: 10),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              // Linha de informações e pílulas de ação intuitivas
              Row(
                children: [
                  Expanded(
                    child: !isVod
                        ? Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, color: Colors.redAccent, size: 7),
                                    SizedBox(width: 5),
                                    Text(
                                      'AO VIVO',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (_engine.currentEpg != null)
                                Expanded(
                                  child: Text(
                                    _engine.currentEpg!.nowTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : const Row(
                            children: [
                              Icon(Icons.swap_horiz_rounded, size: 15, color: Colors.white38),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Use as setas ◀ / ▶ para voltar ou avançar 10s',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.white54),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 12),

                  // Pílula 1: Proporção de Tela
                  _buildMinimalActionPill(
                    focusNode: _scaleBtnNode,
                    icon: Icons.aspect_ratio_rounded,
                    label: _scaleModeLabel,
                    onTap: _cycleScaleMode,
                  ),
                  const SizedBox(width: 8),

                  // Pílula 2: Alternar Modo de Sinal (TS / HLS)
                  _buildMinimalActionPill(
                    focusNode: _signalBtnNode,
                    icon: Icons.tune_rounded,
                    label: 'Sinal',
                    onTap: () {
                      _engine.openStream(
                        currentItem,
                        forceReload: true,
                        tryHlsFallback: true,
                      );
                    },
                  ),

                  // Pílula 3: Lista de Canais ou Episódios
                  if (widget.playlist.isNotEmpty && currentItem.type != ContentType.movie) ...[
                    const SizedBox(width: 8),
                    _buildMinimalActionPill(
                      focusNode: _channelsBtnNode,
                      icon: isVod ? Icons.video_library_rounded : Icons.live_tv_rounded,
                      label: currentItem.type == ContentType.series ? 'Episódios' : 'Canais',
                      isPrimary: true,
                      onTap: () {
                        _hideTimer?.cancel();
                        setState(() => showDrawer = true);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalActionPill({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return TVFocusableItem(
      focusNode: focusNode,
      autoScroll: false,
      onMoveUp: () {
        if (_playPauseNode.canRequestFocus) _playPauseNode.requestFocus();
      },
      onSelect: onTap,
      builder: (c, f) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: f
              ? const Color(0xFF00E5FF)
              : isPrimary
                  ? const Color(0xFF00E5FF).withOpacity(0.14)
                  : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: f
                ? Colors.white
                : isPrimary
                    ? const Color(0xFF00E5FF).withOpacity(0.4)
                    : Colors.white12,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: f
                  ? Colors.black
                  : (isPrimary ? const Color(0xFF00E5FF) : Colors.white70),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: f ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
