"""
Screener semanal da B3.

Varre as ações mais líquidas, elimina as que não passam nos filtros de
qualidade, estima o preço justo (Graham e Bazin) e grava um ranking em
dados/oportunidades.json, que o app lê na aba "Oportunidades".

Uso local:  BRAPI_TOKEN=seu_token python screener/screener.py
"""
import bisect
import json
import math
import os
import sys
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

BASE = "https://brapi.dev/api"
TOKEN = os.getenv("BRAPI_TOKEN", "")
SAIDA = Path(__file__).resolve().parent.parent / "dados" / "oportunidades.json"
MODULOS = "summaryProfile,defaultKeyStatistics,financialData"
TIPOS_ACAO = {"stock", "unit"}
PAUSA = 0.25  # segundos entre requisições
BRASILIA = timezone(timedelta(hours=-3))

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
    if isinstance(v, dict):
        return num(v.get("raw"))
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def pct(v):
    return None if v is None else v * 100


def arred(v, casas=2):
    return None if v is None else round(v, casas)


def _data(s):
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


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
def universo():
    """As N ações mais líquidas, uma classe por empresa."""
    dados = get("/quote/list", {"sortBy": "volume", "sortOrder": "desc"})
    ativos = sorted(dados.get("stocks", []),
                    key=lambda a: num(a.get("volume")) or 0, reverse=True)
    vistos, lista = set(), []
    for a in ativos:
        tk = (a.get("stock") or "").upper()
        tipo = (a.get("subType") or a.get("type") or "").lower()
        if tipo not in TIPOS_ACAO or not tk or tk.endswith("F"):
            continue
        mc = num(a.get("market_cap"))
        if mc is not None and mc < CRITERIOS["valor_mercado_min"]:
            continue
        raiz = tk[:4]
        if raiz in vistos:  # PETR3 e PETR4: fica só a mais líquida
            continue
        vistos.add(raiz)
        lista.append(a)
        if len(lista) >= CRITERIOS["universo_por_liquidez"]:
            break
    return lista


def dividendos_12m(q):
    """Soma dos proventos por ação com data-com nos últimos 12 meses."""
    lista = (q.get("dividendsData") or {}).get("cashDividends") or []
    agora = datetime.now(timezone.utc)
    corte = agora - timedelta(days=365)
    soma, achou = 0.0, False
    for d in lista:
        data = _data(d.get("lastDatePrior") or d.get("paymentDate"))
        valor = num(d.get("rate"))
        if data and valor and corte < data <= agora:
            soma += valor
            achou = True
    return soma if achou else None


def metricas(q, item):
    dks = q.get("defaultKeyStatistics") or {}
    fd = q.get("financialData") or {}
    sp = q.get("summaryProfile") or {}

    preco = num(q.get("regularMarketPrice")) or num(fd.get("currentPrice"))
    lpa = num(q.get("earningsPerShare")) or num(dks.get("trailingEps"))
    vpa = num(dks.get("bookValue"))
    roe = pct(num(fd.get("returnOnEquity")))
    if roe is None and lpa and vpa and vpa > 0:
        roe = lpa / vpa * 100

    ebitda, divida, caixa = num(fd.get("ebitda")), num(fd.get("totalDebt")), num(fd.get("totalCash"))
    dl_ebitda = None
    if ebitda and ebitda > 0 and divida is not None and caixa is not None:
        dl_ebitda = (divida - caixa) / ebitda

    dps = dividendos_12m(q)
    graham = math.sqrt(22.5 * lpa * vpa) if lpa and vpa and lpa > 0 and vpa > 0 else None
    bazin = dps / (CRITERIOS["taxa_bazin"] / 100) if dps else None

    def potencial(justo):
        return (justo / preco - 1) * 100 if justo and preco else None

    pl = preco / lpa if preco and lpa else None
    return {
        "ticker": (q.get("symbol") or item.get("stock")).upper(),
        "nome": q.get("longName") or q.get("shortName") or item.get("name"),
        "setor": sp.get("sector") or item.get("sector"),
        "preco": preco,
        "lpa": lpa,
        "vpa": vpa,
        "pl": pl,
        "pvp": preco / vpa if preco and vpa else None,
        "roe": roe,
        "margem_liquida": pct(num(fd.get("profitMargins"))),
        "div_liq_ebitda": dl_ebitda,
        "dy": dps / preco * 100 if dps and preco else None,
        "preco_justo_graham": graham,
        "potencial_graham": potencial(graham),
        "preco_justo_bazin": bazin,
        "potencial_bazin": potencial(bazin),
        "_tem_fundamentos": bool(fd or dks),
    }


def reprovar(m):
    """Devolve o motivo da reprovação, ou None se a ação passou."""
    c = CRITERIOS
    if not m["_tem_fundamentos"]:
        return "sem dados fundamentalistas"
    if not m["preco"]:
        return "sem preço"
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
    """0 = pior, 1 = melhor (maior). None vira 0."""
    validos = sorted(v for v in valores if v is not None)
    n = len(validos)
    if n == 0:
        return [0.0] * len(valores)
    return [0.0 if v is None else (bisect.bisect_left(validos, v) / (n - 1) if n > 1 else 1.0)
            for v in valores]


def pontuar(aprovadas):
    fatores = {
        "roe": [m["roe"] for m in aprovadas],
        "margem_liquida": [m["margem_liquida"] for m in aprovadas],
        "rendimento_lucro": [100 / m["pl"] if m["pl"] else None for m in aprovadas],
        "potencial": [max((d for d in (m["potencial_graham"], m["potencial_bazin"]) if d is not None), default=None)
                     for m in aprovadas],
    }
    notas = [0.0] * len(aprovadas)
    for nome, valores in fatores.items():
        for i, p in enumerate(percentis(valores)):
            notas[i] += PESOS[nome] * p
    for m, nota in zip(aprovadas, notas):
        m["nota"] = nota * 100


# --------------------------------------------------------------------- main
def main():
    univ = universo()
    print(f"Universo: {len(univ)} ações")
    aprovadas, motivos, erros = [], Counter(), 0

    for i, item in enumerate(univ, 1):
        tk = item["stock"]
        try:
            dados = get(f"/quote/{tk}", {"modules": MODULOS, "dividends": "true"})
            resultados = dados.get("results") or []
            if not resultados:
                raise RuntimeError("resposta vazia")
            m = metricas(resultados[0], item)
        except Exception as e:  # um ticker com erro não para o robô
            erros += 1
            print(f"[{i}/{len(univ)}] {tk}: erro: {e}")
            continue
        finally:
            time.sleep(PAUSA)

        motivo = reprovar(m)
        if motivo:
            motivos[motivo] += 1
        else:
            aprovadas.append(m)

    analisadas = len(univ) - erros
    if analisadas == 0:
        sys.exit("Nenhuma ação consultada. Verifique o token BRAPI_TOKEN.")
    if motivos["sem dados fundamentalistas"] > 0.8 * analisadas:
        sys.exit("A API não devolveu indicadores para a maioria das ações. "
                 "O plano da brapi provavelmente não inclui os módulos fundamentalistas.")

    pontuar(aprovadas)
    aprovadas.sort(key=lambda m: m["nota"], reverse=True)

    campos = ["ticker", "nome", "setor", "preco", "preco_justo_graham", "potencial_graham",
              "preco_justo_bazin", "potencial_bazin", "pl", "pvp", "roe", "margem_liquida",
              "div_liq_ebitda", "dy", "nota"]
    saida = {
        "gerado_em": datetime.now(BRASILIA).isoformat(timespec="minutes"),
        "analisadas": analisadas,
        "erros": erros,
        "aprovadas": len(aprovadas),
        "criterios": CRITERIOS,
        "reprovacoes": dict(motivos.most_common()),
        "oportunidades": [{k: (arred(m[k]) if isinstance(m[k], float) else m[k]) for k in campos}
                          for m in aprovadas[:CRITERIOS["top"]]],
    }
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps(saida, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Analisadas: {analisadas} | erros: {erros} | aprovadas: {len(aprovadas)}")
    print("Top:", ", ".join(o["ticker"] for o in saida["oportunidades"]))


if __name__ == "__main__":
    main()
