"""
Screener semanal da B3.

Pega a lista de ações da brapi (preço, volume e valor de mercado, liberados no
plano gratuito), calcula os indicadores a partir dos balanços oficiais da CVM e
grava dois arquivos que o app lê:

  dados/fundamentos.json    indicadores de todas as ações (telas Detalhe e Comparar)
  dados/oportunidades.json  ranking das que passam nos filtros (aba Oportunidades)

Uso local:  python screener/screener.py   (o token da brapi é opcional)
"""
import bisect
import json
import math
import os
import sys
import time
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests

import cvm

BASE = "https://brapi.dev/api"
TOKEN = os.getenv("BRAPI_TOKEN", "")
DADOS = Path(__file__).resolve().parent.parent / "dados"
TIPOS_ACAO = {"stock", "unit"}
BRASILIA = timezone(timedelta(hours=-3))
BALANCO_MAX_DIAS = 400  # mais velho que isso, a empresa parou de publicar

# Critérios. Ajuste aqui (ou por variável de ambiente no workflow).
CRITERIOS = {
    "universo_por_liquidez": int(os.getenv("UNIVERSO", "300")),
    "valor_mercado_min": float(os.getenv("VALOR_MERCADO_MIN", "500000000")),
    "roe_min": float(os.getenv("ROE_MIN", "10")),
    "margem_liquida_min": float(os.getenv("MARGEM_LIQ_MIN", "0")),
    "div_liq_ebitda_max": float(os.getenv("DIV_LIQ_EBITDA_MAX", "3")),
    "pl_max": float(os.getenv("PL_MAX", "30")),
    "taxa_bazin": float(os.getenv("TAXA_BAZIN", "6")),
    "top": int(os.getenv("TOP", "15")),
}

# Peso de cada fator na nota final (soma 1).
PESOS = {"roe": 0.30, "margem_liquida": 0.20, "rendimento_lucro": 0.25, "potencial": 0.25}

sessao = requests.Session()
if TOKEN:
    sessao.headers["Authorization"] = f"Bearer {TOKEN}"


# ---------------------------------------------------------------- utilidades
def num(v):
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v) if math.isfinite(v) else None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def arred(v, casas=2):
    if v is None:
        return None
    return round(v) if abs(v) >= 1e5 else round(v, casas)


def div(a, b):
    return a / b if a is not None and b else None


def get(caminho, params=None, tentativas=4):
    erro = "falha desconhecida"
    for t in range(tentativas):
        try:
            r = sessao.get(f"{BASE}{caminho}", params=params, timeout=30)
        except requests.RequestException as e:
            erro = str(e)
        else:
            if r.status_code == 200:
                return r.json()
            if r.status_code in (401, 402, 403, 404):
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
            erro = f"HTTP {r.status_code}"
        time.sleep(2 * 2 ** t)  # 2s, 4s, 8s... (cobre o 429)
    raise RuntimeError(erro)


# ------------------------------------------------------------------- etapas
def cotacoes():
    """Ações e units da B3 com preço, volume e valor de mercado (uma chamada só)."""
    dados = get("/quote/list", {"sortBy": "volume", "sortOrder": "desc"})
    lista = []
    for a in dados.get("stocks", []):
        tk = (a.get("stock") or "").upper()
        tipo = (a.get("subType") or a.get("type") or "").lower()
        if tipo in TIPOS_ACAO and tk and not tk.endswith("F") and num(a.get("close")):
            lista.append(a)
    return lista


def _acoes_corrigidas(qt, preco_acao, valor_mercado, pl):
    """Quantidade de ações coerente com o preço de hoje.

    Algumas companhias informam a quantidade em milhares, e desdobramentos ou
    emissões depois do balanço mudam o número. Escolhe a escala pelo valor de
    mercado (ou, sem ele, por um P/VP plausível); se ainda assim a diferença
    for maior que 2x, vale a quantidade implícita no valor de mercado. Até 2x é
    normal quando ON e PN têm preços diferentes.
    """
    if not qt or not preco_acao:
        return qt
    if valor_mercado:
        alvo = valor_mercado / preco_acao
    elif pl and pl > 0:
        alvo = pl / preco_acao  # P/VP = 1
    else:
        return qt
    qt = min((qt, qt * 1000), key=lambda q: abs(math.log(q / alvo)))
    if valor_mercado and not 0.5 <= alvo / qt <= 2:
        return alvo
    return qt


def indicadores(item, empresa, por_papel, valor_mercado_cia):
    """Indicadores de um ticker: os da empresa + os por papel (unit = várias ações)."""
    preco = num(item.get("close"))
    c = empresa
    preco_acao = preco / por_papel if por_papel else None
    acoes = _acoes_corrigidas(c["acoes"], preco_acao, valor_mercado_cia, c["pl"])
    valor_mercado = valor_mercado_cia or (acoes * preco_acao if acoes and preco_acao else None)

    def por_acao(v):
        return v / acoes * por_papel if v is not None and acoes and por_papel else None

    lucro, pl, receita, ebitda = c["lucro_12m"], c["pl"], c.get("receita_12m"), c.get("ebitda_12m")
    divida_liquida = None
    if c.get("divida") is not None and c.get("caixa") is not None:
        divida_liquida = c["divida"] - c["caixa"]

    lpa, vpa, dpa = por_acao(lucro), por_acao(pl), por_acao(c["dividendos_12m"])
    graham = math.sqrt(22.5 * lpa * vpa) if lpa and vpa and lpa > 0 and vpa > 0 else None
    bazin = dpa / (CRITERIOS["taxa_bazin"] / 100) if dpa else None

    def potencial(justo):
        return (justo / preco - 1) * 100 if justo and preco else None

    return {
        "ticker": item["stock"].upper(),
        "nome": item.get("name"),
        "setor": item.get("subsector") or item.get("sector"),
        "data_balanco": c["data_balanco"],
        "financeira": c["financeira"],
        "preco": preco,
        "volume": num(item.get("volume")),
        "valor_mercado": valor_mercado,
        "lpa": lpa,
        "vpa": vpa,
        "dpa": dpa,
        "pl": div(preco, lpa),
        "pvp": div(preco, vpa),
        "dy": div(dpa, preco) * 100 if dpa is not None and preco else None,
        "roe": div(lucro, pl) * 100 if lucro is not None and pl and pl > 0 else None,
        "roa": div(lucro, c["ativo_total"]) * 100 if lucro is not None and c["ativo_total"] else None,
        "margem_bruta": div(c.get("bruto_12m"), receita) * 100 if c.get("bruto_12m") is not None and receita else None,
        "margem_ebitda": div(ebitda, receita) * 100 if ebitda is not None and receita else None,
        "margem_liquida": div(lucro, receita) * 100 if lucro is not None and receita else None,
        "div_liq_ebitda": div(divida_liquida, ebitda) if ebitda and ebitda > 0 else None,
        "divida_liquida": divida_liquida,
        "liquidez_corrente": div(c.get("ativo_circulante"), c.get("passivo_circulante")),
        "ev_ebitda": div(valor_mercado + divida_liquida, ebitda)
        if valor_mercado and divida_liquida is not None and ebitda and ebitda > 0 else None,
        "receita_12m": receita,
        "ebitda_12m": ebitda,
        "lucro_12m": lucro,
        "cresc_receita": c.get("cresc_receita"),
        "cresc_lucro": c.get("cresc_lucro"),
        "preco_justo_graham": graham,
        "potencial_graham": potencial(graham),
        "preco_justo_bazin": bazin,
        "potencial_bazin": potencial(bazin),
    }


def reprovar(m):
    """Devolve o motivo da reprovação, ou None se a ação passou."""
    c = CRITERIOS
    if (date.today() - date.fromisoformat(m["data_balanco"])).days > BALANCO_MAX_DIAS:
        return "balanço desatualizado"
    if m["valor_mercado"] is not None and m["valor_mercado"] < c["valor_mercado_min"]:
        return "valor de mercado pequeno"
    if not m["lpa"] or m["lpa"] <= 0:
        return "lucro zero ou negativo"
    if not m["vpa"] or m["vpa"] <= 0:
        return "patrimônio zero ou negativo"
    if m["roe"] is None or m["roe"] < c["roe_min"]:
        return "ROE abaixo do mínimo"
    if m["margem_liquida"] is not None and m["margem_liquida"] <= c["margem_liquida_min"]:
        return "margem líquida baixa"
    if m["div_liq_ebitda"] is not None and m["div_liq_ebitda"] > c["div_liq_ebitda_max"]:
        return "dívida alta"
    if m["pl"] and m["pl"] > c["pl_max"]:
        return "P/L acima do máximo"
    if (m["potencial_graham"] or -1) <= 0 and (m["potencial_bazin"] or -1) <= 0:
        return "preço acima do preço justo (Graham e Bazin)"
    return None


def percentis(valores):
    """0 = pior, 1 = melhor (maior). None continua None."""
    validos = sorted(v for v in valores if v is not None)
    n = len(validos)
    return [None if v is None else (bisect.bisect_left(validos, v) / (n - 1) if n > 1 else 1.0)
            for v in valores]


def pontuar(aprovadas):
    """Nota 0-100. Fator sem dado (ex.: margem de banco) sai da conta e os outros pesam mais."""
    fatores = {
        "roe": [m["roe"] for m in aprovadas],
        "margem_liquida": [m["margem_liquida"] for m in aprovadas],
        "rendimento_lucro": [100 / m["pl"] if m["pl"] else None for m in aprovadas],
        "potencial": [max((d for d in (m["potencial_graham"], m["potencial_bazin"]) if d is not None), default=None)
                      for m in aprovadas],
    }
    soma = [0.0] * len(aprovadas)
    pesos = [0.0] * len(aprovadas)
    for nome, valores in fatores.items():
        for i, p in enumerate(percentis(valores)):
            if p is not None:
                soma[i] += PESOS[nome] * p
                pesos[i] += PESOS[nome]
    for m, s, w in zip(aprovadas, soma, pesos):
        m["nota"] = s / w * 100 if w else 0.0


def gravar(nome, conteudo, **kw):
    DADOS.mkdir(parents=True, exist_ok=True)
    # A brapi às vezes manda nomes com bytes quebrados ("A\udc81lcool"): troca por "?".
    (DADOS / nome).write_text(json.dumps(conteudo, ensure_ascii=False, **kw), encoding="utf-8", errors="replace")


# --------------------------------------------------------------------- main
def main():
    cadastro = cvm.Cadastro(date.today().year)
    lista, mapa = [], {}
    for a in cotacoes():
        tk = a["stock"].upper()
        achou = cadastro.localizar(tk, a.get("name"), (a.get("subType") or "").lower() == "unit")
        if achou:
            mapa[tk] = achou
            lista.append(a)
    print(f"Ações na brapi com cadastro na CVM: {len(lista)}")
    if not lista:
        sys.exit("A lista de ações da brapi veio vazia.")

    cnpj_de = {tk: cnpj for tk, (cnpj, _) in mapa.items()}
    empresas = cvm.companhias(set(cnpj_de.values()))
    print(f"Empresas com balanço na CVM: {len(empresas)} de {len(set(cnpj_de.values()))}")
    if len(empresas) < 0.5 * len(set(cnpj_de.values())):
        sys.exit("A CVM devolveu balanço para menos da metade das empresas. Algo mudou no formato dos dados.")

    # Valor de mercado é da empresa; units vêm sem, então vale o de outra classe.
    valor_mercado, preco_acao = {}, {}
    for a in lista:
        tk = a["stock"].upper()
        vm = num(a.get("market_cap"))
        if vm:
            valor_mercado.setdefault(cnpj_de[tk], vm)
        if mapa[tk][1] == 1:
            preco_acao.setdefault(cnpj_de[tk], num(a.get("close")))

    # Unit sem composição no cadastro: deduz pelo preço (BPAC11 ≈ 3 × BPAC3).
    for a in lista:
        tk = a["stock"].upper()
        cnpj, por_papel = mapa[tk]
        if por_papel is None and preco_acao.get(cnpj):
            n = round(num(a.get("close")) / preco_acao[cnpj])
            if 2 <= n <= 10:
                mapa[tk] = (cnpj, n)

    todas = {}
    for a in lista:
        tk = a["stock"].upper()
        cnpj, por_papel = mapa[tk]
        if cnpj in empresas:
            todas[tk] = indicadores(a, empresas[cnpj], por_papel, valor_mercado.get(cnpj))

    # Ranking: uma classe por empresa (a mais negociada), entre as N mais líquidas.
    universo, vistos = [], set()
    for a in lista:  # já vem do maior volume para o menor
        tk = a["stock"].upper()
        if tk not in todas or cnpj_de[tk] in vistos:
            continue
        vistos.add(cnpj_de[tk])
        universo.append(todas[tk])
        if len(universo) >= CRITERIOS["universo_por_liquidez"]:
            break

    aprovadas, motivos = [], Counter()
    for m in universo:
        motivo = reprovar(m)
        if motivo:
            motivos[motivo] += 1
        else:
            aprovadas.append(m)
    pontuar(aprovadas)
    aprovadas.sort(key=lambda m: m["nota"], reverse=True)

    agora = datetime.now(BRASILIA).isoformat(timespec="minutes")
    # O app recalcula P/L, P/VP, DY e valor de mercado com o preço do dia;
    # preco_ref é o preço usado aqui, para essa conta.
    for m in todas.values():
        m["preco_ref"] = m["preco"]
    campos_fund = ["nome", "setor", "data_balanco", "financeira", "preco_ref", "lpa", "vpa", "dpa", "roe", "roa",
                   "margem_bruta", "margem_ebitda", "margem_liquida", "div_liq_ebitda", "divida_liquida",
                   "liquidez_corrente", "valor_mercado", "ev_ebitda", "receita_12m", "ebitda_12m",
                   "lucro_12m", "cresc_receita", "cresc_lucro"]
    gravar("fundamentos.json", {
        "gerado_em": agora,
        "fonte": "CVM (DFP/ITR) e brapi (cotações)",
        "acoes": {tk: {k: (arred(m[k], 4) if isinstance(m[k], float) else m[k]) for k in campos_fund}
                  for tk, m in sorted(todas.items())},
    }, separators=(",", ":"))

    campos = ["ticker", "nome", "setor", "preco", "preco_justo_graham", "potencial_graham",
              "preco_justo_bazin", "potencial_bazin", "pl", "pvp", "roe", "margem_liquida",
              "div_liq_ebitda", "dy", "nota"]
    gravar("oportunidades.json", {
        "gerado_em": agora,
        "analisadas": len(universo),
        "aprovadas": len(aprovadas),
        "criterios": CRITERIOS,
        "reprovacoes": dict(motivos.most_common()),
        "oportunidades": [{k: (arred(m[k]) if isinstance(m[k], float) else m[k]) for k in campos}
                          for m in aprovadas[:CRITERIOS["top"]]],
    }, indent=2)
    print(f"Indicadores: {len(todas)} ações | analisadas: {len(universo)} | aprovadas: {len(aprovadas)}")
    print("Reprovações:", dict(motivos.most_common()))
    print("Top:", ", ".join(m["ticker"] for m in aprovadas[:CRITERIOS["top"]]))


if __name__ == "__main__":
    main()
