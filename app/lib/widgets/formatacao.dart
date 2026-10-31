import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/acao.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _compacta = NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$');
final _decimal = NumberFormat('#,##0.00', 'pt_BR');
final _data = DateFormat('dd/MM/yyyy');

bool _valido(double? v) => v != null && v.isFinite;

String formatar(double? v, Formato f) {
  if (!_valido(v)) return '—';
  final x = v!;
  return switch (f) {
    Formato.multiplo => '${_decimal.format(x)}x',
    Formato.percentual => '${_decimal.format(x)}%',
    Formato.moeda => _moeda.format(x),
    Formato.moedaCompacta => _compacta.format(x),
  };
}

String fmtMoeda(double? v) => _valido(v) ? _moeda.format(v) : '—';

String fmtVariacao(double? v) {
  if (!_valido(v)) return '—';
  final x = v!;
  return '${x >= 0 ? '+' : ''}${_decimal.format(x)}%';
}

String fmtData(DateTime d) => _data.format(d);

Color corVariacao(BuildContext context, double? v) {
  if (!_valido(v) || v == 0) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  return v! > 0 ? Colors.green.shade600 : Colors.red.shade600;
}
