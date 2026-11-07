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

final _volume = NumberFormat.compact(locale: 'pt_BR');

/// Quantidade de ações negociadas: 12,3 mi.
String fmtVolume(double? v) => _valido(v) ? _volume.format(v) : '—';

final _enxuto = NumberFormat('#,##0.##', 'pt_BR');

/// "≤ 15x (Graham)", "≥ 6% (Bazin)", "≥ preço atual (Graham)".
String fmtReferencia(Referencia r, Formato f) {
  final limite = r.rotuloLimite ??
      switch (f) {
        Formato.multiplo => '${_enxuto.format(r.limite)}x',
        Formato.percentual => '${_enxuto.format(r.limite)}%',
        Formato.moeda => fmtMoeda(r.limite),
        Formato.moedaCompacta => r.limite == 0 ? '0' : _compacta.format(r.limite),
      };
  return '${r.comparacao.simbolo} $limite (${r.fonte})';
}

/// Verde se atende à referência, laranja se não (vermelho fica para queda).
Widget? seloReferencia(Indicador i, {double tamanho = 16}) {
  final ok = i.atendeReferencia;
  if (ok == null) return null;
  return Icon(ok ? Icons.check_circle : Icons.error_outline,
      size: tamanho,
      color: ok ? Colors.green.shade600 : Colors.orange.shade700,
      semanticLabel: ok ? 'Dentro da referência' : 'Fora da referência');
}

/// Valor com sinal: +R$ 120,00 / -R$ 35,10.
String fmtMoedaSinal(double? v) {
  if (!_valido(v)) return '—';
  return '${v! > 0 ? '+' : v < 0 ? '-' : ''}${_moeda.format(v.abs())}';
}
