"""
Leitura em texto das ações do ranking, feita pelo Gemini.

Os números chegam prontos do screener: a IA só comenta, não calcula. Junto vão
os assuntos dos fatos relevantes e comunicados recentes entregues à CVM (IPE).
Grava dados/analises.json, que o app mostra na tela de detalhe.

Sem GEMINI_API_KEY, não faz nada. Se a chamada de uma ação falhar, mantém a
leitura da semana anterior dela.
"""
import json
import os
import re
import time
from datetime import date, timedelta

import requests

import cvm

CHAVE = os.getenv("GEMINI_API_KEY", "")
MODELO = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
URL = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent"
DIAS_FATOS = 120
MAX_FATOS = 10
CATEGORIAS_FATOS = {"Fato Relevante", "Comunicado ao Mercado"}
TIMEOUT = 90  # segundos por chamada
# Tempo total para as leituras: o que não couber fica com a leitura anterior,
# e o ranking é publicado de qualquer jeito.
PRAZO = float(os.getenv("IA_PRAZO_MIN", "20")) * 60
# Intervalo mínimo entre o início de duas chamadas. O plano gratuito do Gemini
# aceita poucas chamadas por minuto; disparar as 15 seguidas dá HTTP 429.
INTERVALO = float(os.getenv("IA_INTERVALO_S", "13"))
ESPERA_MAX = 90  # segundos, no máximo, esperando a cota por minuto liberar


class CotaDiaria(RuntimeError):
    """A cota do dia acabou: não adianta tentar as outras ações."""

INSTRUCOES = """Você é um analista de ações da B3 escrevendo para um investidor pessoa física.
Recebe os indicadores já calculados de uma empresa e a lista de fatos relevantes recentes.
Regras:
- Use só os dados recebidos. Não invente números, notícias nem eventos.
- Não refaça contas; cite os números como vieram.
- Não recomende comprar, vender ou manter. Descreva o que os dados mostram.
- Considere o setor: bancos e seguradoras não têm margem nem EBITDA; ciclo de commodities muda lucro de um ano para outro.
- Desconfie de números extremos (P/L muito baixo, DY muito alto, crescimento enorme): diga o que pode explicá-los,
  como lucro não recorrente ou dividendo extraordinário, e que vale conferir.
- Português do Brasil, frases curtas, sem jargão desnecessário."""

ESQUEMA = {
    "type": "OBJECT",
    "properties": {
        "resumo": {"type": "STRING", "description": "2 a 3 frases sobre a empresa segundo os indicadores"},
        "pontos_fortes": {"type": "ARRAY", "items": {"type": "STRING"}, "description": "até 3 itens curtos"},
        "riscos": {"type": "ARRAY", "items": {"type": "STRING"},
                   "description": "até 3 itens curtos: fragilidades ou números que pedem conferência"},
        "leitura_fatos": {"type": "STRING",
                          "description": "1 a 2 frases sobre o que os fatos recentes sugerem; vazio se não houver"},
    },
    "required": ["resumo", "pontos_fortes", "riscos", "leitura_fatos"],
}

# Nome e unidade de cada indicador no texto enviado à IA.
ROTULOS = {
    "preco": ("Preço", "R$"), "valor_mercado": ("Valor de mercado", "R$"),
    "pl": ("P/L", ""), "pvp": ("P/VP", ""), "dy": ("Dividend yield", "%"),
    "roe": ("ROE", "%"), "roa": ("ROA", "%"),
    "margem_bruta": ("Margem bruta", "%"), "margem_ebitda": ("Margem EBITDA", "%"),
    "margem_liquida": ("Margem líquida", "%"), "div_liq_ebitda": ("Dív. líquida/EBITDA", "x"),
    "liquidez_corrente": ("Liquidez corrente", "x"), "ev_ebitda": ("EV/EBITDA", "x"),
    "receita_12m": ("Receita 12m", "R$"), "ebitda_12m": ("EBITDA 12m", "R$"), "lucro_12m": ("Lucro 12m", "R$"),
    "cresc_receita": ("Crescimento da receita em 12m", "%"), "cresc_lucro": ("Crescimento do lucro em 12m", "%"),
    "preco_justo_graham": ("Preço justo de Graham", "R$"), "potencial_graham": ("Potencial até Graham", "%"),
    "preco_justo_bazin": ("Preço justo de Bazin", "R$"), "potencial_bazin": ("Potencial até Bazin", "%"),
    "nota": ("Nota no ranking (0 a 100)", ""),
}


def _valor(v, unidade):
    if unidade == "R$" and abs(v) >= 1e6:
        return f"R$ {v / 1e9:.2f} bi" if abs(v) >= 1e9 else f"R$ {v / 1e6:.1f} mi"
    if unidade == "R$":
        return f"R$ {v:.2f}"
    return f"{v:.2f}{unidade}"


def fatos_recentes(cnpjs, hoje=None):
    """{cnpj: [{data, categoria, assunto}]}, do mais novo para o mais velho."""
    hoje = hoje or date.today()
    corte = (hoje - timedelta(days=DIAS_FATOS)).isoformat()
    fatos = {c: [] for c in cnpjs}
    for ano in sorted({hoje.year, (hoje - timedelta(days=DIAS_FATOS)).year}):
        zip_path = cvm.baixar("IPE", ano)
        if not zip_path:
            continue
        for r in cvm._linhas(zip_path, f"ipe_cia_aberta_{ano}.csv"):
            cnpj = r["CNPJ_Companhia"]
            if cnpj in fatos and r["Categoria"] in CATEGORIAS_FATOS and r["Data_Entrega"] >= corte:
                fatos[cnpj].append({"data": r["Data_Entrega"], "categoria": r["Categoria"],
                                    "assunto": " ".join(r["Assunto"].split()).strip(" ,.;")})
    for lista in fatos.values():
        lista.sort(key=lambda f: f["data"], reverse=True)
        # Fatos relevantes primeiro; comunicados completam até o limite.
        fr = [f for f in lista if f["categoria"] == "Fato Relevante"]
        lista[:] = sorted((fr + [f for f in lista if f not in fr])[:MAX_FATOS], key=lambda f: f["data"], reverse=True)
    return fatos


def _pergunta(m, fatos, criterios):
    linhas = [f"Empresa: {m['nome']} ({m['ticker']})", f"Setor: {m.get('setor') or '—'}",
              f"Instituição financeira: {'sim' if m.get('financeira') else 'não'}",
              f"Data do último balanço: {m.get('data_balanco')}", "", "Indicadores (últimos 12 meses):"]
    for campo, (nome, unidade) in ROTULOS.items():
        if m.get(campo) is not None:
            linhas.append(f"- {nome}: {_valor(m[campo], unidade)}")
    linhas += ["", f"Passou nos filtros do ranking: ROE ≥ {criterios['roe_min']}%, "
               f"Dív. líquida/EBITDA ≤ {criterios['div_liq_ebitda_max']}, P/L ≤ {criterios['pl_max']}, "
               f"preço abaixo do justo de Graham ou de Bazin (Bazin com taxa de {criterios['taxa_bazin']}%).",
               "Graham = √(22,5 × LPA × VPA). Bazin = dividendos e JCP pagos em 12 meses ÷ taxa.", ""]
    if fatos:
        linhas.append(f"Fatos relevantes e comunicados entregues à CVM nos últimos {DIAS_FATOS} dias (só o assunto):")
        linhas += [f"- {f['data']} [{f['categoria']}] {f['assunto']}" for f in fatos]
    else:
        linhas.append(f"Nenhum fato relevante ou comunicado nos últimos {DIAS_FATOS} dias.")
    return "\n".join(linhas)


def _erro_429(r):
    """(mensagem curta, segundos sugeridos para esperar, se a cota é diária)."""
    try:
        erro = r.json()["error"]
    except (ValueError, KeyError, TypeError):
        return f"HTTP 429: {r.text[:200]}", None, False
    espera, cotas = None, []
    for d in erro.get("details") or []:
        tipo = d.get("@type", "")
        if tipo.endswith("RetryInfo"):
            m = re.match(r"([\d.]+)s", d.get("retryDelay", ""))
            espera = float(m.group(1)) if m else None
        elif tipo.endswith("QuotaFailure"):
            cotas += [v.get("quotaId", "") for v in d.get("violations") or []]
    diaria = any("PerDay" in c for c in cotas)
    msg = (erro.get("message") or "").split("\n")[0][:120]
    return f"HTTP 429 ({', '.join(cotas) or 'cota'}): {msg}", espera, diaria


def _gemini(texto, tentativas=4):
    corpo = {
        "systemInstruction": {"parts": [{"text": INSTRUCOES}]},
        "contents": [{"role": "user", "parts": [{"text": texto}]}],
        "generationConfig": {"temperature": 0.3, "responseMimeType": "application/json", "responseSchema": ESQUEMA},
    }
    erro = "falha desconhecida"
    for t in range(tentativas):
        espera = 5 * 2 ** t
        try:
            r = requests.post(URL.format(MODELO), json=corpo, headers={"x-goog-api-key": CHAVE},
                              timeout=TIMEOUT)
        except requests.RequestException as e:
            erro = str(e)
        else:
            if r.status_code == 200:
                partes = r.json()["candidates"][0]["content"]["parts"]
                return json.loads("".join(p.get("text", "") for p in partes))
            if r.status_code == 429:
                erro, sugerida, diaria = _erro_429(r)
                if diaria:
                    raise CotaDiaria(erro)
                # O Google diz quanto esperar até a cota por minuto liberar.
                espera = min(ESPERA_MAX, (sugerida or 30) + 2)
            else:
                # A mensagem do Google não traz a chave; 400/403 não melhoram tentando de novo.
                erro = f"HTTP {r.status_code}: {r.text[:300]}"
                if r.status_code in (400, 401, 403, 404):
                    break
        if t + 1 < tentativas:
            print(f"    {erro[:160]} | nova tentativa em {espera:.0f}s", flush=True)
            time.sleep(espera)
    raise RuntimeError(erro)


def gerar(acoes, cnpj_de, criterios, anterior=None):
    """Leitura de cada ação de `acoes` (dicts do screener). Devolve o conteúdo de analises.json."""
    anterior = (anterior or {}).get("acoes", {})
    inicio = time.monotonic()
    print(f"IA: {len(acoes)} ações com {MODELO}", flush=True)
    try:
        fatos = fatos_recentes({cnpj_de[m["ticker"]] for m in acoes if m["ticker"] in cnpj_de})
    except Exception as e:  # sem os fatos, a leitura sai só com os indicadores
        print(f"  fatos da CVM indisponíveis: {e}", flush=True)
        fatos = {}
    print(f"  fatos da CVM em {time.monotonic() - inicio:.0f}s", flush=True)
    saida = {}
    ultima = None
    for i, m in enumerate(acoes, 1):
        tk = m["ticker"]
        if time.monotonic() - inicio > PRAZO:
            print(f"  prazo de {PRAZO / 60:.0f} min esgotado: {tk} e as seguintes ficam com a leitura anterior",
                  flush=True)
            _manter(acoes[i - 1:], anterior, saida)
            break
        if ultima is not None:
            time.sleep(max(0.0, INTERVALO - (time.monotonic() - ultima)))
        ultima = time.monotonic()
        f = fatos.get(cnpj_de.get(tk), [])
        t0 = time.monotonic()
        try:
            leitura = _gemini(_pergunta(m, f, criterios))
        except CotaDiaria as e:
            print(f"  [{i}/{len(acoes)}] {tk}: cota diária do Gemini esgotada ({e}). "
                  f"{tk} e as seguintes ficam com a leitura anterior; a cota volta no dia seguinte.", flush=True)
            _manter(acoes[i - 1:], anterior, saida)
            break
        except Exception as e:  # uma ação com problema não derruba as outras
            print(f"  [{i}/{len(acoes)}] {tk}: IA falhou em {time.monotonic() - t0:.0f}s: {e}", flush=True)
            if tk in anterior:
                saida[tk] = anterior[tk]
            continue
        print(f"  [{i}/{len(acoes)}] {tk}: ok em {time.monotonic() - t0:.0f}s", flush=True)
        saida[tk] = {
            "resumo": (leitura.get("resumo") or "").strip(),
            "pontos_fortes": [s.strip() for s in leitura.get("pontos_fortes") or [] if s.strip()][:3],
            "riscos": [s.strip() for s in leitura.get("riscos") or [] if s.strip()][:3],
            "leitura_fatos": (leitura.get("leitura_fatos") or "").strip(),
            "fatos": [{"data": x["data"], "categoria": x["categoria"], "assunto": x["assunto"]} for x in f],
        }
    return {"modelo": MODELO, "acoes": saida}


def _manter(acoes, anterior, saida):
    for m in acoes:
        if m["ticker"] in anterior:
            saida[m["ticker"]] = anterior[m["ticker"]]
