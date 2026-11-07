import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/carteira.dart';

/// Operações da carteira e saldo em conta, guardados só no celular.
class CarteiraStorage extends ChangeNotifier {
  static const _chave = 'carteira_operacoes';
  static const _chaveSaldo = 'carteira_saldo';

  List<Operacao>? _cache;
  double? _saldo;
  bool _saldoLido = false;

  /// Dinheiro parado na corretora, disponível para aplicar.
  /// null enquanto o usuário não informou.
  Future<double?> saldo() async {
    if (_saldoLido) return _saldo;
    final p = await SharedPreferences.getInstance();
    _saldo = p.getDouble(_chaveSaldo);
    _saldoLido = true;
    return _saldo;
  }

  /// Informa o saldo atual da conta (substitui o anterior).
  Future<void> definirSaldo(double valor) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_chaveSaldo, _arredondar(valor));
    _saldo = _arredondar(valor);
    _saldoLido = true;
    notifyListeners();
  }

  /// Depósito (positivo) ou retirada (negativo). Sem saldo informado,
  /// parte de zero.
  Future<void> movimentarSaldo(double valor) async =>
      definirSaldo((await saldo() ?? 0) + valor);

  /// Esquece o saldo (a carteira volta a não mostrar a conta).
  Future<void> limparSaldo() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_chaveSaldo);
    _saldo = null;
    _saldoLido = true;
    notifyListeners();
  }

  static double _arredondar(double v) => (v * 100).roundToDouble() / 100;

  Future<List<Operacao>> carregar() async {
    if (_cache != null) return [..._cache!];
    final p = await SharedPreferences.getInstance();
    final texto = p.getString(_chave);
    final lista = <Operacao>[];
    if (texto != null) {
      try {
        for (final o in jsonDecode(texto) as List) {
          lista.add(Operacao.fromJson(Map<String, dynamic>.from(o as Map)));
        }
      } catch (_) {}
    }
    _cache = lista;
    return [...lista];
  }

  /// Inclui ou substitui (mesmo id). Recusa se deixar alguma venda maior
  /// que a posição. Com [ajustarSaldo], a compra sai do saldo em conta e a
  /// venda entra (numa edição, só a diferença); só vale com saldo informado.
  Future<void> salvar(Operacao op, {bool ajustarSaldo = false}) async {
    final lista = await carregar();
    final antiga = _achar(lista, op.id);
    lista.removeWhere((o) => o.id == op.id);
    lista.add(op);
    calcularPosicoes(lista); // lança ErroCarteira se ficar inconsistente
    await _gravar(lista);
    if (ajustarSaldo) {
      await _ajustar(op.efeitoNoSaldo - (antiga?.efeitoNoSaldo ?? 0));
    }
  }

  /// Apaga a operação. Com [ajustarSaldo], desfaz o efeito dela no saldo.
  Future<void> remover(String id, {bool ajustarSaldo = false}) async {
    final lista = await carregar();
    final antiga = _achar(lista, id);
    lista.removeWhere((o) => o.id == id);
    calcularPosicoes(lista); // apagar uma compra pode invalidar uma venda
    await _gravar(lista);
    if (ajustarSaldo && antiga != null) await _ajustar(-antiga.efeitoNoSaldo);
  }

  static Operacao? _achar(List<Operacao> lista, String id) {
    for (final o in lista) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<void> _ajustar(double valor) async {
    final atual = await saldo();
    if (atual == null || valor == 0) return;
    await definirSaldo(atual + valor);
  }

  Future<void> _gravar(List<Operacao> lista) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _chave, jsonEncode([for (final o in ordenar(lista)) o.toJson()]));
    _cache = lista;
    notifyListeners();
  }
}
