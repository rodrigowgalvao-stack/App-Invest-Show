import 'package:shared_preferences/shared_preferences.dart';

/// Guarda a lista de tickers no próprio celular.
class WatchlistStorage {
  static const _chave = 'watchlist';

  /// Estes três funcionam mesmo sem token na brapi.
  static const padrao = ['PETR4', 'VALE3', 'ITUB4'];

  Future<List<String>> carregar() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_chave) ?? [...padrao];
  }

  Future<void> salvar(List<String> tickers) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_chave, tickers);
  }
}
