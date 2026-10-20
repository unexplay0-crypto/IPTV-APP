// ============================================================
//  Tela de Ativação por Código — UNEX Vision
//  Adicione em lib/ativacao_screen.dart e importe no main.dart
//  Uso: Navigator.push(context, MaterialPageRoute(builder: (_) =>
//        AtivacaoScreen(onSucesso: (m3uUrl) { /* carrega a lista */ })));
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// COLE AQUI a URL do seu Apps Script (terminada em /exec)
const String kAtivacaoUrl = 'https://script.google.com/macros/s/COLOQUE_SEU_ID_AQUI/exec';

class AtivacaoScreen extends StatefulWidget {
  final ValueChanged<String> onSucesso; // recebe a URL M3U ativada
  const AtivacaoScreen({super.key, required this.onSucesso});

  @override
  State<AtivacaoScreen> createState() => _AtivacaoScreenState();
}

class _AtivacaoScreenState extends State<AtivacaoScreen> {
  final List<TextEditingController> _ctrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _fcs = List.generate(6, (_) => FocusNode());
  bool _carregando = false;
  String? _erro;

  String get _codigo => _ctrls.map((c) => c.text).join().toUpperCase();

  @override
  void dispose() {
    for (final c in _ctrls) { c.dispose(); }
    for (final f in _fcs) { f.dispose(); }
    super.dispose();
  }

  Future<void> _ativar() async {
    if (_codigo.length != 6 || _carregando) return;
    setState(() { _carregando = true; _erro = null; });
    try {
      final res = await http
          .get(Uri.parse('$kAtivacaoUrl?acao=ativar&codigo=$_codigo'))
          .timeout(const Duration(seconds: 20));
      final dados = jsonDecode(res.body) as Map<String, dynamic>;
      if (dados['ok'] == true) {
        final m3u = dados['m3u_url'].toString();
        Navigator.pop(context);
        widget.onSucesso(m3u); // conecte aqui ao seu fluxo de login/carregar lista
      } else {
        setState(() => _erro = dados['erro']?.toString() ?? 'Erro ao ativar.');
      }
    } catch (e) {
      setState(() => _erro = 'Sem conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Ativar com código'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Digite o código de 6 caracteres',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) => _caixa(i)),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 18),
                Text(_erro!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _carregando ? null : _ativar,
                  child: _carregando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ativar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _caixa(int i) {
    return Container(
      width: 42,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: _ctrls[i],
        focusNode: _fcs[i],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF1A1D24),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.lightBlueAccent)),
        ),
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(1),
          UpperCaseTextFormatter(),
        ],
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _fcs[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _fcs[i - 1].requestFocus();
          if (_codigo.length == 6) _ativar(); // auto-ativa ao completar
        },
      ),
    );
  }
}

// Garante letras maiúsculas automaticamente
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
