import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String URL_BASE_DO_APPS_SCRIPT =
    "https://script.google.com/macros/s/AKfycbxo7zTUHl33zdsiae0uGFz-AqnRN6oPlFSjQ0M_HNYbUR3NLi4WXJFB1ApxbcTfFKUT/exec";

const String ENDPOINT_ATIVACAO = "$URL_BASE_DO_APPS_SCRIPT?acao=ativar&codigo=";

/// Formatador que converte para MAIÚSCULAS e permite apenas:
/// A B C D E F G H J K L M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9
/// Bloqueia: 0, 1, O, I e caracteres especiais.
class _ActivationCharFormatter extends TextInputFormatter {
  static final RegExp _allowedRegex = RegExp(r'[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final upper = newValue.text.toUpperCase();
    final filtered = upper.split('').where((ch) => _allowedRegex.hasMatch(ch)).join();

    if (filtered.isEmpty) {
      return oldValue;
    }

    // Mantém apenas o último caractere válido digitado no campo
    final char = filtered.substring(filtered.length - 1);
    return TextEditingValue(
      text: char,
      selection: const TextSelection.collapsed(offset: 1),
    );
  }
}

class AtivacaoScreen extends StatefulWidget {
  final Future<void> Function(String m3uUrl)? onM3uActivated;

  const AtivacaoScreen({
    super.key,
    this.onM3uActivated,
  });

  @override
  State<AtivacaoScreen> createState() => _AtivacaoScreenState();
}

class _AtivacaoScreenState extends State<AtivacaoScreen> {
  static const int _codeLength = 6;
  static final RegExp _validCharRegex = RegExp(r'[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]');

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _fieldFocusNodes;
  late final List<FocusNode> _keyListenerFocusNodes;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_codeLength, (_) => TextEditingController());
    _fieldFocusNodes = List.generate(_codeLength, (_) => FocusNode());
    _keyListenerFocusNodes = List.generate(_codeLength, (_) => FocusNode());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fieldFocusNodes.first.canRequestFocus) {
        _fieldFocusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _fieldFocusNodes) {
      f.dispose();
    }
    for (final k in _keyListenerFocusNodes) {
      k.dispose();
    }
    super.dispose();
  }

  String get _currentCode =>
      _controllers.map((c) => c.text.trim().toUpperCase()).join();

  bool get _isCodeComplete =>
      _controllers.every((c) => c.text.trim().length == 1);

  void _onFieldChanged(int index, String value) {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    } else {
      setState(() {});
    }

    final clean = value.toUpperCase().replaceAll(RegExp(r'[^ABCDEFGHJKLMNPQRSTUVWXYZ23456789]'), '');

    if (clean.isEmpty) {
      _controllers[index].clear();
      setState(() {});
      return;
    }

    // Caso o usuário cole o código inteiro de uma vez
    if (clean.length > 1) {
      for (int i = 0; i < clean.length && (index + i) < _codeLength; i++) {
        _controllers[index + i].text = clean[i];
        _controllers[index + i].selection = const TextSelection.collapsed(offset: 1);
      }
      final nextIndex = (index + clean.length).clamp(0, _codeLength - 1);
      _fieldFocusNodes[nextIndex].requestFocus();
      setState(() {});
      return;
    }

    // Auto-avanço: pula automaticamente para o próximo campo
    if (index < _codeLength - 1) {
      _fieldFocusNodes[index + 1].requestFocus();
    } else {
      _fieldFocusNodes[index].unfocus();
    }
    setState(() {});
  }

  KeyEventResult _handleKeyPress(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Auto-retorno: ao apertar Backspace, volta para o campo anterior
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isNotEmpty) {
        _controllers[index].clear();
        if (index > 0) {
          _fieldFocusNodes[index - 1].requestFocus();
        }
        setState(() {});
        return KeyEventResult.handled;
      } else if (index > 0) {
        _controllers[index - 1].clear();
        _fieldFocusNodes[index - 1].requestFocus();
        setState(() {});
        return KeyEventResult.handled;
      }
    }

    // Navegação lateral por setas do controle remoto entre as 6 caixas
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index > 0) {
      _fieldFocusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && index < _codeLength - 1) {
      _fieldFocusNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }

    // Captura direta de teclas alfanuméricas físicas/controle remoto
    final label = event.logicalKey.keyLabel.toUpperCase();
    if (label.length == 1 && _validCharRegex.hasMatch(label)) {
      _controllers[index].text = label;
      _controllers[index].selection = const TextSelection.collapsed(offset: 1);
      _onFieldChanged(index, label);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _ativarCodigo() async {
    if (!_isCodeComplete || _isLoading) return;

    final codigoDigitado = _currentCode.toUpperCase();
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('$ENDPOINT_ATIVACAO$codigoDigitado');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException();
        }

        final bool ok = decoded['ok'] == true;
        final String m3uUrl = (decoded['m3u_url'] ?? '').toString().trim();

        if (ok && m3uUrl.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lista carregada com sucesso'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Aciona a função já existente no app para carregar e salvar a lista M3U
          if (widget.onM3uActivated != null) {
            await widget.onM3uActivated!(m3uUrl);
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context, m3uUrl);
            }
          } else {
            Navigator.pop(context, m3uUrl);
          }
          return;
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Código inválido ou já utilizado. Verifique e tente novamente.';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível conectar. Verifique sua internet e tente novamente.';
        });
      }
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível conectar. Verifique sua internet e tente novamente.';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível conectar. Verifique sua internet e tente novamente.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível conectar. Verifique sua internet e tente novamente.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível conectar. Verifique sua internet e tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: const Color(0xFF090B10),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  color: const Color(0xFF111520),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withOpacity(0.28),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.65),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.vpn_key_rounded,
                        color: Color(0xFF00E5FF),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Ativação por Código',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Digite seu código de 6 dígitos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 6 CAMPOS INDEPENDENTES
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_codeLength, (index) {
                        return SizedBox(
                          width: 48,
                          height: 58,
                          child: Focus(
                            focusNode: _keyListenerFocusNodes[index],
                            onKeyEvent: (_, event) => _handleKeyPress(index, event),
                            child: TextField(
                              controller: _controllers[index],
                              focusNode: _fieldFocusNodes[index],
                              enabled: !_isLoading,
                              textAlign: TextAlign.center,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 1,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF00E5FF),
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                filled: true,
                                fillColor: const Color(0xFF090B10),
                                contentPadding: EdgeInsets.zero,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _controllers[index].text.isNotEmpty
                                        ? const Color(0xFF00E5FF).withOpacity(0.6)
                                        : Colors.white24,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00E5FF),
                                    width: 2.2,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Colors.white12),
                                ),
                              ),
                              inputFormatters: [
                                _ActivationCharFormatter(),
                              ],
                              onChanged: (val) => _onFieldChanged(index, val),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '✅ Letras A-Z e números 2-9 (exceto 0, 1, O, I)',
                            style: TextStyle(fontSize: 11.5, color: Colors.white60),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '✅ Não diferencia maiúsculas de minúsculas',
                            style: TextStyle(fontSize: 11.5, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // BOTÃO ATIVAR
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: (_isCodeComplete && !_isLoading) ? _ativarCodigo : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          disabledBackgroundColor: Colors.white12,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Color(0xFF00E5FF),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Conectando...',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'ATIVAR',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 1.0,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // BOTÃO VOLTAR
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'VOLTAR',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
    );
  }
}
