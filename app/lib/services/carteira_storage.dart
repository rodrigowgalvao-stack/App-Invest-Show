import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/carteira.dart';

/// Operações da carteira, guardadas só no celular.
class CarteiraStorage extends ChangeNotifier {
  static const _chave = 'carteira_operacoes';

  List<Operacao>? _cache;

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
  /// que a posição.
  Future<void> salvar(Operacao op) async {
    final lista = await carregar();
    lista.removeWhere((o) => o.id == op.id);
    lista.add(op);
    calcularPosicoes(lista); // lança ErroCarteira se ficar inconsistente
    await _gravar(lista);
  }

  Future<void> remover(String id) async {
    final lista = await carregar();
    lista.removeWhere((o) => o.id == id);
    calcularPosicoes(lista); // apagar uma compra pode invalidar uma venda
    await _gravar(lista);
  }

  Future<void> _gravar(List<Operacao> lista) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _chave, jsonEncode([for (final o in ordenar(lista)) o.toJson()]));
    _cache = lista;
    notifyListeners();
  }
}
