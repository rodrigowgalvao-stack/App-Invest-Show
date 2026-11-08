/// Leitura em texto que o Gemini faz das ações do ranking
/// (dados/analises.json). Os números são do robô; a IA só comenta.
class Analise {
  const Analise({
    required this.resumo,
    this.pontosFortes = const [],
    this.riscos = const [],
    this.leituraFatos = '',
    this.fatos = const [],
    this.modelo,
    this.geradoEm,
  });

  final String resumo;
  final List<String> pontosFortes;
  final List<String> riscos;
  final String leituraFatos;
  final List<FatoCvm> fatos;
  final String? modelo;
  final DateTime? geradoEm;

  factory Analise.fromJson(Map<String, dynamic> j,
      {String? modelo, DateTime? geradoEm}) {
    List<String> textos(Object? v) =>
        v is List ? [for (final s in v) if (s is String && s.isNotEmpty) s] : const [];
    final fatos = j['fatos'];
    return Analise(
      resumo: j['resumo'] as String? ?? '',
      pontosFortes: textos(j['pontos_fortes']),
      riscos: textos(j['riscos']),
      leituraFatos: j['leitura_fatos'] as String? ?? '',
      fatos: fatos is List
          ? [
              for (final f in fatos)
                if (f is Map) FatoCvm.fromJson(Map<String, dynamic>.from(f))
            ]
          : const [],
      // O robô grava o modelo de cada ação (pode ter sido o reserva).
      modelo: j['modelo'] as String? ?? modelo,
      geradoEm: geradoEm,
    );
  }
}

/// Fato relevante ou comunicado ao mercado entregue à CVM.
class FatoCvm {
  const FatoCvm({this.data, required this.categoria, required this.assunto});
  final DateTime? data;
  final String categoria;
  final String assunto;

  bool get relevante => categoria == 'Fato Relevante';

  factory FatoCvm.fromJson(Map<String, dynamic> j) => FatoCvm(
        data: DateTime.tryParse(j['data'] as String? ?? ''),
        categoria: j['categoria'] as String? ?? '',
        assunto: j['assunto'] as String? ?? '',
      );
}
