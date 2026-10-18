import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';

// =============================================================================
// 1. CONTROLE DE FOCO CIRÚRGICO PARA D-PAD (10-FOOT UI)
// =============================================================================
class TVFocusableItem extends StatefulWidget {
  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final bool autoScroll;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const TVFocusableItem({
    super.key,
    required this.onSelect,
    required this.builder,
    this.autoScroll = true,
    this.autofocus = false,
    this.focusNode,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<TVFocusableItem> createState() => _TVFocusableItemState();
}

class _TVFocusableItemState extends State<TVFocusableItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f && widget.autoScroll && mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 140),
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.gameButtonA) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (widget.onMoveLeft != null && key == LogicalKeyboardKey.arrowLeft) {
            widget.onMoveLeft!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveRight != null && key == LogicalKeyboardKey.arrowRight) {
            widget.onMoveRight!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveUp != null && key == LogicalKeyboardKey.arrowUp) {
            widget.onMoveUp!();
            return KeyEventResult.handled;
          }
          if (widget.onMoveDown != null && key == LogicalKeyboardKey.arrowDown) {
            widget.onMoveDown!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _isFocused),
      ),
    );
  }
}

class TVIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final double size;
  final bool autofocus;
  final FocusNode? focusNode;

  const TVIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white70,
    this.size = 20,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TVFocusableItem(
      focusNode: focusNode,
      autofocus: autofocus,
      autoScroll: false,
      onSelect: onPressed,
      builder: (context, isFocused) => AnimatedScale(
        scale: isFocused ? 1.14 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isFocused ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(
              color: isFocused ? Colors.white : Colors.white12,
              width: isFocused ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            color: isFocused ? Colors.black : color,
            size: size,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 2. TECLADO VIRTUAL DE TV 2.0
// - Sem botão de menu web separado
// - 'http://' e '.' integrados na última fileira de letras
// - 3 botões iguais embaixo: MAIÚSCULA, ESPAÇO e APAGAR
// - Foco inicial sempre cravado na letra 'q' ao abrir ou alternar página
// =============================================================================
Future<void> showTVVirtualKeyboard(
  BuildContext context,
  TextEditingController ctrl,
  String title, {
  bool isPassword = false,
  ValueChanged<String>? onChanged,
}) async {
  const row1 = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  const row2 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  const row3 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  const row4 = ['z', 'x', 'c', 'v', 'b', 'n', 'm', 'http://', '.'];

  bool isUpper = false;
  final FocusNode qFocusNode = FocusNode();

  void focusQKey() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (qFocusNode.canRequestFocus) {
        qFocusNode.requestFocus();
      }
    });
  }

  focusQKey();

  await showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) {
        final displayText = ctrl.text.isEmpty
            ? 'Use o controle para digitar...'
            : (isPassword ? '•' * ctrl.text.length : ctrl.text);

        void insertText(String value) {
          setModal(() {
            ctrl.text += value;
          });
          onChanged?.call(ctrl.text);
        }

        void backspace() {
          if (ctrl.text.isNotEmpty) {
            setModal(() {
              ctrl.text = ctrl.text.substring(0, ctrl.text.length - 1);
            });
            onChanged?.call(ctrl.text);
          }
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 690,
              margin: const EdgeInsets.only(bottom: 18, left: 16, right: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E17).withOpacity(0.98),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00E5FF), width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.85),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // VISOR ESPELHADO NO TOPO DO TECLADO + BOTÃO CONCLUÍR
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141826),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            '$displayText▌',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: ctrl.text.isEmpty ? Colors.white38 : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => Navigator.pop(ctx),
                        builder: (c, f) => AnimatedScale(
                          scale: f ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            decoration: BoxDecoration(
                              color: f ? Colors.white : const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // FILEIRA 1: NÚMEROS
                  Wrap(
                    spacing: 6,
                    children: row1
                        .map(
                          (k) => _buildKeyboardKey(
                            label: k,
                            width: 56,
                            onTap: () => insertText(k),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 6),

                  // FILEIRA 2: QWERTYUIOP (Foco automático na tecla 'q')
                  Wrap(
                    spacing: 6,
                    children: row2.map((k) {
                      final isQ = k == 'q';
                      final label = isUpper ? k.toUpperCase() : k;
                      return _buildKeyboardKey(
                        label: label,
                        width: 56,
                        focusNode: isQ ? qFocusNode : null,
                        autofocus: isQ,
                        onTap: () => insertText(label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),

                  // FILEIRA 3: ASDFGHJKL
                  Wrap(
                    spacing: 6,
                    children: row3.map((k) {
                      final label = isUpper ? k.toUpperCase() : k;
                      return _buildKeyboardKey(
                        label: label,
                        width: 56,
                        onTap: () => insertText(label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),

                  // FILEIRA 4: ZXCVBNM + 'http://' + '.'
                  Wrap(
                    spacing: 6,
                    children: row4.map((k) {
                      final isSpecial = k == 'http://' || k == '.';
                      final label = isSpecial ? k : (isUpper ? k.toUpperCase() : k);
                      return _buildKeyboardKey(
                        label: label,
                        width: k == 'http://' ? 96 : 56,
                        color: isSpecial ? const Color(0xFF1A253B) : const Color(0xFF151928),
                        textColor: isSpecial ? const Color(0xFF00E5FF) : Colors.white,
                        onTap: () => insertText(label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // BARRA INFERIOR: 3 BOTÕES IGUAIS (MAIÚSCULA, ESPAÇO, APAGAR)
                  Row(
                    children: [
                      Expanded(
                        child: _buildKeyboardKey(
                          label: isUpper ? '⇧ MAIÚSCULA (ON)' : '⇧ MAIÚSCULA',
                          color: isUpper ? const Color(0xFF2979FF) : const Color(0xFF181C2C),
                          onTap: () {
                            setModal(() => isUpper = !isUpper);
                            focusQKey();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKeyboardKey(
                          label: 'ESPAÇO',
                          color: const Color(0xFF181C2C),
                          onTap: () => insertText(' '),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildKeyboardKey(
                          label: '⌫ APAGAR',
                          color: const Color(0xFF2B1B24),
                          textColor: Colors.orangeAccent,
                          onTap: backspace,
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

Widget _buildKeyboardKey({
  required String label,
  required VoidCallback onTap,
  double? width,
  FocusNode? focusNode,
  bool autofocus = false,
  Color color = const Color(0xFF151928),
  Color textColor = Colors.white,
}) {
  return TVFocusableItem(
    focusNode: focusNode,
    autofocus: autofocus,
    autoScroll: false,
    onSelect: onTap,
    builder: (c, f) => AnimatedScale(
      scale: f ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: width,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: f ? const Color(0xFF00E5FF) : color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: f ? Colors.white : Colors.white24,
            width: f ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: f ? Colors.black : textColor,
          ),
        ),
      ),
    ),
  );
}

// =============================================================================
// 3. CONTROLE PARENTAL (+18) — DESBLOQUEIO E ALTERAÇÃO DE SENHA (PADRÃO 0000)
// =============================================================================
Future<bool> showParentalPinPrompt(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) async {
  bool unlocked = false;
  final pinCtrl = TextEditingController();
  final correctPin = await AppStorage.loadParentalPin();
  String errorText = '';

  if (!context.mounted) return false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) => AlertDialog(
        backgroundColor: const Color(0xFF101422),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.redAccent, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conteúdo Adulto (+18)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Digite a senha de Controle Parental para liberar o acesso (Padrão: 0000):',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (deviceMode == DeviceMode.mobile)
              TextField(
                controller: pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '0000',
                  filled: true,
                  fillColor: const Color(0xFF090B10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim() == correctPin) {
                    unlocked = true;
                    Navigator.pop(ctx);
                  } else {
                    setModal(() {
                      errorText = 'Senha incorreta. Tente novamente.';
                      pinCtrl.clear();
                    });
                  }
                },
              )
            else
              TVFocusableItem(
                autofocus: true,
                autoScroll: false,
                onSelect: () async {
                  await showTVVirtualKeyboard(context, pinCtrl, 'SENHA PIN', isPassword: true);
                  setModal(() {});
                },
                builder: (c, f) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: f ? const Color(0xFF00E5FF) : Colors.white24,
                      width: f ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    pinCtrl.text.isEmpty ? 'Aperte OK para digitar o PIN...' : '•' * pinCtrl.text.length,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      letterSpacing: pinCtrl.text.isEmpty ? 0 : 8,
                      fontWeight: FontWeight.bold,
                      color: pinCtrl.text.isEmpty ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
              ),
            if (errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  errorText,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TVFocusableItem(
            autoScroll: false,
            onSelect: () => Navigator.pop(ctx),
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: f ? Colors.white : Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white)),
            ),
          ),
          TVFocusableItem(
            autoScroll: false,
            onSelect: () {
              if (pinCtrl.text.trim() == correctPin) {
                unlocked = true;
                Navigator.pop(ctx);
              } else {
                setModal(() {
                  errorText = 'Senha incorreta. Tente novamente.';
                  pinCtrl.clear();
                });
              }
            },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: f ? Colors.white : Colors.redAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Desbloquear',
                style: TextStyle(
                  color: f ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return unlocked;
}

Future<void> showChangeParentalPinDialog(
  BuildContext context, {
  DeviceMode deviceMode = DeviceMode.tv,
}) async {
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final savedPin = await AppStorage.loadParentalPin();
  String statusMsg = '';

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) => AlertDialog(
        backgroundColor: const Color(0xFF101422),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Alterar Senha Parental (+18)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (deviceMode == DeviceMode.mobile) ...[
              TextField(
                controller: currentCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Senha Atual (Padrão: 0000)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nova Senha'),
              ),
            ] else ...[
              TVFocusableItem(
                autofocus: true,
                autoScroll: false,
                onSelect: () async {
                  await showTVVirtualKeyboard(context, currentCtrl, 'SENHA ATUAL', isPassword: true);
                  setModal(() {});
                },
                builder: (c, f) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24),
                  ),
                  child: Text(
                    currentCtrl.text.isEmpty ? 'Senha Atual (OK p/ digitar)' : '•' * currentCtrl.text.length,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TVFocusableItem(
                autoScroll: false,
                onSelect: () async {
                  await showTVVirtualKeyboard(context, newCtrl, 'NOVA SENHA', isPassword: true);
                  setModal(() {});
                },
                builder: (c, f) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24),
                  ),
                  child: Text(
                    newCtrl.text.isEmpty ? 'Nova Senha (OK p/ digitar)' : '•' * newCtrl.text.length,
                  ),
                ),
              ),
            ],
            if (statusMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  statusMsg,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TVFocusableItem(
            autoScroll: false,
            onSelect: () => Navigator.pop(ctx),
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: f ? Colors.white : Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Fechar'),
            ),
          ),
          TVFocusableItem(
            autoScroll: false,
            onSelect: () async {
              if (currentCtrl.text.trim() != savedPin) {
                setModal(() => statusMsg = 'A senha atual está incorreta.');
                return;
              }
              if (newCtrl.text.trim().length < 4) {
                setModal(() => statusMsg = 'A nova senha deve ter pelo menos 4 dígitos.');
                return;
              }
              await AppStorage.saveParentalPin(newCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            builder: (c, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: f ? Colors.white : const Color(0xFF00E5FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Salvar Senha',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// =============================================================================
// 4. CARDS VISUAIS OTIMIZADOS COM CACHE CONTROL (ANTI-OUTOFMEMORY)
// =============================================================================
Widget buildStreamingPosterCard({
  required String title,
  required String subtitle,
  required String logoUrl,
  required String badgeText,
  required VoidCallback onTap,
  bool isFocused = false,
  bool isPlaying = false,
  bool isFavorite = false,
  bool isAdultLocked = false,
  double? progress,
  VoidCallback? onFavoriteTap,
}) {
  return AnimatedScale(
    scale: isFocused ? 1.06 : 1.0,
    duration: const Duration(milliseconds: 140),
    curve: Curves.easeOutCubic,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151928),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused
              ? const Color(0xFF00E5FF)
              : isPlaying
                  ? const Color(0xFF7C4DFF)
                  : Colors.white12,
          width: isFocused ? 2.6 : 1.2,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(0.32),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isAdultLocked)
              Container(
                color: const Color(0xFF14101C),
                child: const Center(
                  child: Icon(Icons.lock_outline_rounded, color: Colors.redAccent, size: 42),
                ),
              )
            else if (logoUrl.isNotEmpty)
              Image.network(
                logoUrl,
                fit: BoxFit.cover,
                cacheWidth: 220,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.movie_creation_rounded,
                  color: Color(0xFF00E5FF),
                  size: 38,
                ),
              )
            else
              const Icon(Icons.movie_creation_rounded, color: Color(0xFF00E5FF), size: 38),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black26, Colors.transparent, Colors.black87],
                  stops: [0.0, 0.42, 1.0],
                ),
              ),
            ),
            Positioned(top: 8, left: 8, child: buildQualityBadge(badgeText)),
            if (onFavoriteTap != null)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onFavoriteTap,
                  child: Icon(
                    isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isFavorite ? Colors.amber : Colors.white70,
                    size: 22,
                  ),
                ),
              ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (progress != null && progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          color: const Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildQualityBadge(String tag) {
  final isHigh = tag == '4K' || tag == 'FHD';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    decoration: BoxDecoration(
      color: isHigh ? const Color(0xFF00E5FF).withOpacity(0.22) : Colors.black87,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: isHigh ? const Color(0xFF00E5FF) : Colors.white24,
        width: 1,
      ),
    ),
    child: Text(
      tag,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
        color: isHigh ? const Color(0xFF00E5FF) : Colors.white,
      ),
    ),
  );
}

Widget buildChannelLogo(String url, {double size = 48, bool isLocked = false}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF090B10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white10),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: isLocked
          ? const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 22)
          : url.isNotEmpty
              ? Image.network(
                  url,
                  fit: BoxFit.contain,
                  cacheWidth: 120,
                  errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
                )
              : const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
    ),
  );
}

Future<Duration?> showVodResumePrompt({
  required BuildContext context,
  required VodProgressEntry entry,
}) async {
  return showDialog<Duration?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF121622),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF00E5FF)),
      ),
      title: Text(
        entry.item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Você parou em ${entry.formattedPosition} (${entry.formattedRemaining}).',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 6,
              color: const Color(0xFF00E5FF),
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
      actions: [
        TVFocusableItem(
          autofocus: true,
          autoScroll: false,
          onSelect: () => Navigator.pop(ctx, Duration(seconds: entry.positionSeconds)),
          builder: (c, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: f ? Colors.white : const Color(0xFF00E5FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Continuar',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        TVFocusableItem(
          autoScroll: false,
          onSelect: () => Navigator.pop(ctx, Duration.zero),
          builder: (c, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: f ? const Color(0xFF00E5FF) : Colors.white24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Do Início'),
          ),
        ),
      ],
    ),
  );
}
