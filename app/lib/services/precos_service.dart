import 'package:flutter/foundation.dart';

class PrecoAtual {
  const PrecoAtual(this.preco, this.quando);
  final double preco;

  /// Quando o app recebeu o preço (não o horário do pregão).
  final DateTime quando;
}

/// Último preço conhecido de cada ativo, venha de onde vier: da lista
/// completa da brapi (uma chamada para a bolsa toda) ou de uma consulta
/// individual (tela de detalhe, Minha lista). Quem mostra preços escuta
/// este objeto; o ranking se recalcula sozinho quando algo muda.
class PrecosService extends ChangeNotifier {
  final Map<String, PrecoAtual> _precos = {};
  DateTime? _ultimaLista;

  PrecoAtual? de(String ticker) => _precos[ticker.toUpperCase()];

  /// Horário da atualização completa mais recente (null se nunca houve).
  DateTime? get ultimaLista => _ultimaLista;

  Map<String, double> get mapa =>
      {for (final e in _precos.entries) e.key: e.value.preco};

  void registrar(String ticker, double? preco, {DateTime? quando}) {
    if (preco == null || !preco.isFinite || preco <= 0) return;
    final t = ticker.toUpperCase();
    final anterior = _precos[t];
    _precos[t] = PrecoAtual(preco, quando ?? DateTime.now());
    if (anterior?.preco != preco) notifyListeners();
  }

  void registrarLista(Map<String, double> precos, {DateTime? quando}) {
    final agora = quando ?? DateTime.now();
    for (final e in precos.entries) {
      if (e.value.isFinite && e.value > 0) {
        _precos[e.key.toUpperCase()] = PrecoAtual(e.value, agora);
      }
    }
    _ultimaLista = agora;
    notifyListeners();
  }
}
