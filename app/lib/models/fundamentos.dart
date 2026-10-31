import 'acao.dart';

/// Indicadores que o robô calcula a partir dos balanços da CVM
/// (dados/fundamentos.json). Os que dependem do preço são recalculados
/// aqui com a cotação do dia.
class Fundamentos {
  const Fundamentos({
    this.setor,
    this.dataBalanco,
    this.financeira = false,
    this.precoRef,
    this.lpa,
    this.vpa,
    this.dpa,
    this.roe,
    this.roa,
    this.margemBruta,
    this.margemEbitda,
    this.margemLiquida,
    this.divLiqEbitda,
    this.dividaLiquida,
    this.liquidezCorrente,
    this.valorMercado,
    this.receita,
    this.ebitda,
    this.lucro,
    this.crescReceita,
    this.crescLucro,
  });

  final String? setor;
  final DateTime? dataBalanco;
  final bool financeira;
  final double? precoRef;
  final double? lpa;
  final double? vpa;
  final double? dpa;
  final double? roe;
  final double? roa;
  final double? margemBruta;
  final double? margemEbitda;
  final double? margemLiquida;
  final double? divLiqEbitda;
  final double? dividaLiquida;
  final double? liquidezCorrente;
  final double? valorMercado;
  final double? receita;
  final double? ebitda;
  final double? lucro;
  final double? crescReceita;
  final double? crescLucro;

  factory Fundamentos.fromJson(Map<String, dynamic> j) => Fundamentos(
        setor: j['setor'] as String?,
        dataBalanco: DateTime.tryParse('${j['data_balanco'] ?? ''}'),
        financeira: j['financeira'] == true,
        precoRef: numero(j['preco_ref']),
        lpa: numero(j['lpa']),
        vpa: numero(j['vpa']),
        dpa: numero(j['dpa']),
        roe: numero(j['roe']),
        roa: numero(j['roa']),
        margemBruta: numero(j['margem_bruta']),
        margemEbitda: numero(j['margem_ebitda']),
        margemLiquida: numero(j['margem_liquida']),
        divLiqEbitda: numero(j['div_liq_ebitda']),
        dividaLiquida: numero(j['divida_liquida']),
        liquidezCorrente: numero(j['liquidez_corrente']),
        valorMercado: numero(j['valor_mercado']),
        receita: numero(j['receita_12m']),
        ebitda: numero(j['ebitda_12m']),
        lucro: numero(j['lucro_12m']),
        crescReceita: numero(j['cresc_receita']),
        crescLucro: numero(j['cresc_lucro']),
      );
}

/// Sempre a mesma estrutura (com valores vazios quando falta dado), para o
/// comparador poder alinhar as linhas entre ações.
List<GrupoIndicadores> gruposIndicadores(Fundamentos? f, double? preco) {
  // Valor de mercado acompanha o preço desde a data do relatório do robô.
  final vm = (f?.valorMercado != null && preco != null && (f?.precoRef ?? 0) > 0)
      ? f!.valorMercado! * preco / f.precoRef!
      : f?.valorMercado;
  final ev = (vm != null && f?.dividaLiquida != null) ? vm + f!.dividaLiquida! : null;
  final ebitda = f?.ebitda;

  return [
    GrupoIndicadores('Valuation', [
      Indicador('P/L', dividir(preco, f?.lpa), Formato.multiplo,
          'Preço ÷ lucro por ação dos últimos 12 meses. Quantos anos de lucro atual “pagam” a ação.',
          melhor: Melhor.menor, soPositivos: true),
      Indicador('P/VP', dividir(preco, f?.vpa), Formato.multiplo,
          'Preço ÷ valor patrimonial por ação. Abaixo de 1, a ação vale menos que o patrimônio.',
          melhor: Melhor.menor, soPositivos: true),
      Indicador('EV/EBITDA',
          (ebitda != null && ebitda > 0) ? dividir(ev, ebitda) : null,
          Formato.multiplo,
          'Valor da firma (valor de mercado + dívida líquida) ÷ EBITDA dos últimos 12 meses.',
          melhor: Melhor.menor, soPositivos: true),
      Indicador('Dividend yield (12m)',
          (f?.dpa != null && preco != null && preco > 0) ? f!.dpa! / preco * 100 : null,
          Formato.percentual,
          'Dividendos e JCP pagos nos últimos 12 meses (fluxo de caixa) ÷ preço atual. '
          'Inclui pagamentos extraordinários, que podem não se repetir.',
          melhor: Melhor.maior),
      Indicador('LPA', f?.lpa, Formato.moeda,
          'Lucro líquido dos últimos 12 meses ÷ número de ações.',
          melhor: Melhor.maior),
      Indicador('VPA', f?.vpa, Formato.moeda,
          'Patrimônio líquido ÷ número de ações.'),
    ]),
    GrupoIndicadores('Rentabilidade', [
      Indicador('ROE', f?.roe, Formato.percentual,
          'Lucro líquido ÷ patrimônio líquido. Quanto a empresa rende sobre o capital dos acionistas.',
          melhor: Melhor.maior),
      Indicador('ROA', f?.roa, Formato.percentual, 'Lucro ÷ ativos totais.',
          melhor: Melhor.maior),
      Indicador('Margem bruta', f?.margemBruta, Formato.percentual,
          'Lucro bruto ÷ receita. Não se aplica a bancos e seguradoras.',
          melhor: Melhor.maior),
      Indicador('Margem EBITDA', f?.margemEbitda, Formato.percentual,
          'EBITDA ÷ receita. Não se aplica a bancos e seguradoras.',
          melhor: Melhor.maior),
      Indicador('Margem líquida', f?.margemLiquida, Formato.percentual,
          'Lucro líquido ÷ receita. Não se aplica a bancos e seguradoras.',
          melhor: Melhor.maior),
    ]),
    GrupoIndicadores('Endividamento e liquidez', [
      Indicador('Dív. líquida/EBITDA', f?.divLiqEbitda, Formato.multiplo,
          'Quantos anos de EBITDA pagariam a dívida líquida. Negativo = caixa maior que a dívida.',
          melhor: Melhor.menor),
      Indicador('Dívida líquida', f?.dividaLiquida, Formato.moedaCompacta,
          'Empréstimos, financiamentos e debêntures − caixa e aplicações.'),
      Indicador('Liquidez corrente', f?.liquidezCorrente, Formato.multiplo,
          'Ativo circulante ÷ passivo circulante. Acima de 1, cobre as obrigações de curto prazo.',
          melhor: Melhor.maior),
    ]),
    GrupoIndicadores('Tamanho e crescimento', [
      Indicador('Valor de mercado', vm, Formato.moedaCompacta,
          'Preço × total de ações.'),
      Indicador('Receita (12m)', f?.receita, Formato.moedaCompacta,
          'Receita líquida dos últimos 12 meses.'),
      Indicador('EBITDA (12m)', ebitda, Formato.moedaCompacta,
          'Lucro antes de juros, impostos, depreciação e amortização.'),
      Indicador('Lucro líquido (12m)', f?.lucro, Formato.moedaCompacta,
          'Lucro atribuído aos acionistas da empresa nos últimos 12 meses.'),
      Indicador('Crescimento da receita', f?.crescReceita, Formato.percentual,
          'Receita acumulada no ano até o último balanço contra o mesmo período do ano anterior.',
          melhor: Melhor.maior),
      Indicador('Crescimento do lucro', f?.crescLucro, Formato.percentual,
          'Lucro acumulado no ano até o último balanço contra o mesmo período do ano anterior.',
          melhor: Melhor.maior),
    ]),
  ];
}
