import 'package:flutter/material.dart';

import 'screens/comparador_screen.dart';
import 'screens/oportunidades_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/brapi_service.dart';
import 'services/oportunidades_service.dart';
import 'services/watchlist_storage.dart';

void main() => runApp(const AcoesApp());

/// Azul-petróleo: sóbrio, legível em claro e escuro, e não compete
/// com o verde/vermelho das variações.
const _corBase = Color(0xFF0E4C5A);

class AcoesApp extends StatelessWidget {
  const AcoesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Análise de Ações',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: _corBase),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _corBase,
        brightness: Brightness.dark,
      ),
      home: const Inicio(),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  final _api = BrapiService();
  final _storage = WatchlistStorage();
  final _oportunidades = OportunidadesService();
  int _aba = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_aba) {
        0 => OportunidadesScreen(
            api: _api, storage: _storage, servico: _oportunidades),
        1 => WatchlistScreen(api: _api, storage: _storage),
        _ => ComparadorScreen(api: _api, storage: _storage),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (i) => setState(() => _aba = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.star_outline), label: 'Oportunidades'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Minha lista'),
          NavigationDestination(icon: Icon(Icons.compare_arrows), label: 'Comparar'),
        ],
      ),
    );
  }
}
