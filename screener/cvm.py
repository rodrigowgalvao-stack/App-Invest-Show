"""
Dados abertos da CVM (dados.cvm.gov.br): demonstrações anuais (DFP) e
trimestrais (ITR), composição do capital e o cadastro de tickers (FCA).

Para cada companhia (CNPJ), monta os números do último balanço e dos últimos
12 meses: lucro, receita, EBITDA, dividendos pagos, patrimônio, dívida etc.
"""
import csv
import io
import os
import re
import tempfile
import time
import unicodedata
import zipfile
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import requests

BASE = "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC"
CACHE = Path(os.getenv("CVM_CACHE") or Path(tempfile.gettempdir()) / "cvm")
VALIDADE_CACHE = 12 * 3600  # segundos

# Quantos níveis de conta guardar (3.11 = 1 nível, 6.01.01.04 = 3 níveis).
NIVEIS = {"DRE": 2, "BPA": 2, "BPP": 2, "DFC_MI": 3}

RE_LUCRO = re.compile(r"^lucro.*per[ií]odo", re.I)
RE_CONTROLADOR = re.compile(r"controlador", re.I)
RE_NAO_CONTROLADOR = re.compile(r"n[aã]o[\s-]*controlador", re.I)
RE_DA = re.compile(r"deprecia|amortiza|exaust|deple", re.I)
RE_DA_EXCLUIR = re.compile(r"juros|financ|empr[eé]st|deb[eê]nt|capta|transa[cç]|pr[eê]mio|des[aá]gio|valor presente", re.I)
RE_DIVIDENDOS = re.compile(r"dividend|juros sobre (o )?capital|\bjcp\b|distribui[cç][aã]o de (lucros|resultado)|lucros? distribu", re.I)
RE_DIVIDENDOS_EXCLUIR = re.compile(r"receb|n[aã]o[\s-]*control", re.I)


# ---------------------------------------------------------------- download
def baixar(tipo, ano):
    """Baixa (ou reaproveita do cache) o zip de DFP, ITR ou FCA. None se não existe."""
    nome = f"{tipo.lower()}_cia_aberta_{ano}.zip"
    destino = CACHE / nome
    if destino.exists() and time.time() - destino.stat().st_mtime < VALIDADE_CACHE:
        return destino
    r = requests.get(f"{BASE}/{tipo}/DADOS/{nome}", timeout=300)
    if r.status_code == 404:
        return None
    r.raise_for_status()
    CACHE.mkdir(parents=True, exist_ok=True)
    destino.write_bytes(r.content)
    return destino


def _linhas(zip_path, nome):
    with zipfile.ZipFile(zip_path) as z:
        if nome not in z.namelist():
            return
        with z.open(nome) as f:
            yield from csv.DictReader(io.TextIOWrapper(f, encoding="latin-1", newline=""), delimiter=";")


def _num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


# ------------------------------------------------------------------ tickers
RE_TICKER = re.compile(r"^[A-Z0-9]{4}\d{1,2}$")


def nome_normalizado(nome):
    """'Cia. Siderúrgica Nacional S/A' e 'CIA SIDERURGICA NACIONAL' ficam iguais."""
    s = unicodedata.normalize("NFKD", nome or "").encode("ascii", "ignore").decode().upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    s = re.sub(r"\b(S A|SA|S)\b", " ", s)
    return " ".join(s.split())


class Cadastro:
    """De ticker para CNPJ, a partir do formulário cadastral (FCA) da CVM.

    O FCA tem falhas (CSN aparece com o código "4030", a Klabin só cadastra a
    unit), então quem não está lá é procurado pelo prefixo do ticker e depois
    pelo nome da empresa.
    """

    def __init__(self, ano):
        self.papeis = {}  # ticker -> (cnpj, ações por papel)
        self.por_nome = {}
        self.por_prefixo = {}
        # Nem toda companhia reenvia o cadastro todo ano: junta os dois últimos.
        for a in (ano - 1, ano):
            z = baixar("FCA", a)
            if not z:
                continue
            for r in _linhas(z, f"fca_cia_aberta_valor_mobiliario_{a}.csv"):
                if r["Mercado"] != "Bolsa":
                    continue
                cnpj = r["CNPJ_Companhia"]
                self.por_nome[nome_normalizado(r["Nome_Empresarial"])] = cnpj
                tk = (r["Codigo_Negociacao"] or "").strip().upper()
                if not RE_TICKER.match(tk):
                    continue
                if r["Data_Fim_Negociacao"]:
                    self.papeis.pop(tk, None)
                    continue
                por_papel = 1
                if (r["Valor_Mobiliario"] or "").lower().startswith("unit"):
                    # "1 ON + 2 PN", "1 ON E 2 PNA", "1 KLBN3 + 4 KLBN4"
                    qts = re.findall(r"(\d+)\s*(?:ON|PN[A-Z]?|[A-Z]{4}\d{1,2})\b", r["Composicao_BDR_Unit"] or "", re.I)
                    por_papel = sum(int(q) for q in qts) or None
                self.papeis[tk] = (cnpj, por_papel)
                self.por_prefixo[tk[:4]] = cnpj
        if not self.papeis:
            raise RuntimeError("Cadastro FCA da CVM indisponível.")

    def localizar(self, ticker, nome, unit):
        """(cnpj, ações por papel) ou None. Unit fora do FCA fica sem composição."""
        if ticker in self.papeis:
            return self.papeis[ticker]
        cnpj = self.por_prefixo.get(ticker[:4]) or self.por_nome.get(nome_normalizado(nome))
        if not cnpj:
            return None
        return cnpj, (None if unit else 1)


# ------------------------------------------------------------- demonstrações
class _Documento:
    """Uma DFP ou ITR de uma companhia, na versão mais recente."""

    def __init__(self, tipo, data):
        self.tipo, self.data = tipo, data
        self.versao = -1
        self.linhas = []  # (demo, ordem, dt_ini, cd, ds, valor)
        self.acoes = None

    def _contas(self, demos, ordem, dt_ini=None):
        return {cd: (ds, v) for demo, o, ini, cd, ds, v in self.linhas
                if demo in demos and o == ordem and (dt_ini is None or ini == dt_ini)}

    def inicio(self, ordem):
        """Início do acumulado do exercício (a DRE do ITR traz também só o trimestre)."""
        datas = [ini for demo, o, ini, *_ in self.linhas if demo == "DRE" and o == ordem and ini]
        return min(datas) if datas else None

    def balanco(self):
        return self._contas(("BPA", "BPP"), "ÚLTIMO")

    def fluxo(self, ordem):
        ini = self.inicio(ordem)
        return self._contas(("DRE", "DFC_MI"), ordem, ini) if ini else {}


def _carregar(zips, cnpjs, sufixo, docs, so_estes=None):
    """Lê as demonstrações (consolidadas ou individuais) para dentro de docs."""
    for tipo, ano, z in zips:
        prefixo = f"{tipo.lower()}_cia_aberta"
        for demo, niveis in NIVEIS.items():
            for r in _linhas(z, f"{prefixo}_{demo}_{sufixo}_{ano}.csv"):
                cnpj = r["CNPJ_CIA"]
                if cnpj not in cnpjs or (so_estes is not None and cnpj not in so_estes):
                    continue
                cd = r["CD_CONTA"]
                if cd.count(".") > niveis or r["MOEDA"] != "REAL":
                    continue
                valor = _num(r["VL_CONTA"])
                if valor is None:
                    continue
                if r["ESCALA_MOEDA"] == "MIL":
                    valor *= 1000
                versao = int(r["VERSAO"])
                doc = docs[cnpj].setdefault((tipo, r["DT_REFER"]), _Documento(tipo, r["DT_REFER"]))
                if versao < doc.versao:
                    continue
                if versao > doc.versao:
                    doc.versao, doc.linhas = versao, []
                doc.linhas.append((demo, r["ORDEM_EXERC"], r.get("DT_INI_EXERC", ""), cd, r["DS_CONTA"], valor))


def _carregar_acoes(zips, cnpjs, docs):
    for tipo, ano, z in zips:
        melhor = {}
        for r in _linhas(z, f"{tipo.lower()}_cia_aberta_composicao_capital_{ano}.csv"):
            if r["CNPJ_CIA"] not in cnpjs:
                continue
            total, tesouraria = _num(r["QT_ACAO_TOTAL_CAP_INTEGR"]), _num(r["QT_ACAO_TOTAL_TESOURO"]) or 0
            chave = (r["CNPJ_CIA"], r["DT_REFER"])
            versao = int(r["VERSAO"])
            if total and (chave not in melhor or versao >= melhor[chave][0]):
                melhor[chave] = (versao, total - tesouraria)
        for (cnpj, data), (_, qt) in melhor.items():
            doc = docs.get(cnpj, {}).get((tipo, data))
            if doc and qt > 0:
                doc.acoes = qt


# ------------------------------------------------------------------ métricas
def _soma(*vs):
    vs = [v for v in vs if v is not None]
    return sum(vs) if vs else None


def _valor(contas, cd, comeca=None):
    ds, v = contas.get(cd, (None, None))
    if v is None or (comeca and not ds.lower().startswith(comeca)):
        return None
    return v


def _resultado(fl):
    """Itens de resultado de um período (DRE + DFC) já somados."""
    if not fl:
        return {}
    nivel1 = sorted(cd for cd in fl if re.fullmatch(r"3\.\d\d", cd))
    cd_lucro = next((cd for cd in reversed(nivel1) if RE_LUCRO.search(fl[cd][0])), None)
    lucro = None
    if cd_lucro:
        filhos = {cd: fl[cd] for cd in fl if cd.startswith(cd_lucro + ".") and cd.count(".") == 2}
        controlador = next((v for ds, v in filhos.values()
                            if RE_CONTROLADOR.search(ds) and not RE_NAO_CONTROLADOR.search(ds)), None)
        minoritarios = next((v for ds, v in filhos.values() if RE_NAO_CONTROLADOR.search(ds)), 0)
        lucro = controlador if controlador is not None else fl[cd_lucro][1] - minoritarios

    da = _soma(*(abs(v) for cd, (ds, v) in fl.items()
                 if cd.startswith("6.01.") and RE_DA.search(ds) and not RE_DA_EXCLUIR.search(ds)))
    dividendos = _soma(*(-v for cd, (ds, v) in fl.items()
                         if cd.startswith("6.03.") and cd.count(".") == 2
                         and RE_DIVIDENDOS.search(ds) and not RE_DIVIDENDOS_EXCLUIR.search(ds)))
    return {
        "receita": _valor(fl, "3.01", "receita de venda"),
        "bruto": _valor(fl, "3.03", "resultado bruto"),
        "ebit": _valor(fl, "3.05", "resultado antes do resultado financeiro"),
        "da": da,
        "lucro": lucro,
        # Sem DFC pelo método indireto não dá para saber; com DFC e sem a linha, é zero.
        "dividendos": dividendos if dividendos is not None
        else (0.0 if any(cd.startswith("6.") for cd in fl) else None),
    }


def _menos_um_dia(iso):
    return (date.fromisoformat(iso) - timedelta(days=1)).isoformat()


def _doze_meses(ultimo, anual):
    """Últimos 12 meses: acumulado do ITR + exercício anterior − mesmo período do ano anterior."""
    atual = _resultado(ultimo.fluxo("ÚLTIMO"))
    if ultimo.tipo == "DFP":
        return atual, True
    if not anual:
        return {}, False
    passado = _resultado(ultimo.fluxo("PENÚLTIMO"))
    ano = _resultado(anual.fluxo("ÚLTIMO"))
    ttm = {}
    for k in atual:
        a, b, c = atual.get(k), ano.get(k), passado.get(k)
        ttm[k] = None if None in (a, b, c) else a + b - c
    return ttm, True


def _crescimento(atual, anterior):
    if atual is None or not anterior or anterior <= 0:
        return None
    return (atual / anterior - 1) * 100


def _metricas(docs_cnpj):
    if not docs_cnpj:
        return None
    ultimo = max(docs_cnpj.values(), key=lambda d: (d.data, d.tipo == "DFP"))
    ini = ultimo.inicio("ÚLTIMO")
    anual = docs_cnpj.get(("DFP", _menos_um_dia(ini))) if ini else None
    ttm, ok = _doze_meses(ultimo, anual)
    if not ok:
        return None

    bal = ultimo.balanco()
    financeira = (bal.get("1.01", ("",))[0] or "").lower() != "ativo circulante"
    cd_pl = next((cd for cd in sorted(bal) if re.fullmatch(r"2\.\d\d", cd)
                  and bal[cd][0].lower().startswith("patrimônio líquido")), None)
    pl = None
    if cd_pl:
        filhos = [(ds, v) for cd, (ds, v) in bal.items() if cd.startswith(cd_pl + ".") and cd.count(".") == 2]
        controlador = next((v for ds, v in filhos
                            if RE_CONTROLADOR.search(ds) and not RE_NAO_CONTROLADOR.search(ds)), None)
        minoritarios = next((v for ds, v in filhos if RE_NAO_CONTROLADOR.search(ds)), 0)
        pl = controlador if controlador is not None else bal[cd_pl][1] - minoritarios

    acoes = ultimo.acoes or next((d.acoes for d in sorted(docs_cnpj.values(), key=lambda d: d.data, reverse=True)
                                  if d.acoes), None)

    # Crescimento: acumulado do ano contra o mesmo período do ano anterior.
    agora, antes = _resultado(ultimo.fluxo("ÚLTIMO")), _resultado(ultimo.fluxo("PENÚLTIMO"))

    m = {
        "data_balanco": ultimo.data,
        "documento": ultimo.tipo,
        "financeira": financeira,
        "acoes": acoes,
        "lucro_12m": ttm.get("lucro"),
        "dividendos_12m": ttm.get("dividendos"),
        "pl": pl,
        "ativo_total": _valor(bal, "1"),
        "cresc_lucro": _crescimento(agora.get("lucro"), antes.get("lucro")),
    }
    if not financeira:
        ebitda = None
        if ttm.get("ebit") is not None and ttm.get("da") is not None:
            ebitda = ttm["ebit"] + ttm["da"]
        m.update({
            "receita_12m": ttm.get("receita"),
            "bruto_12m": ttm.get("bruto"),
            "ebitda_12m": ebitda,
            "ativo_circulante": _valor(bal, "1.01", "ativo circulante"),
            "passivo_circulante": _valor(bal, "2.01", "passivo circulante"),
            "caixa": _soma(_valor(bal, "1.01.01", "caixa"), _valor(bal, "1.01.02", "aplica")),
            "divida": _soma(_valor(bal, "2.01.04", "empréstimos"), _valor(bal, "2.02.01", "empréstimos")),
            "cresc_receita": _crescimento(agora.get("receita"), antes.get("receita")),
        })
    return m


def companhias(cnpjs, hoje=None):
    """{cnpj: métricas} para os CNPJs pedidos, a partir das últimas DFP e ITR."""
    ano = (hoje or date.today()).year
    zips = []
    # A DFP do ano corrente existe para quem fecha o exercício antes de dezembro.
    for tipo, anos in (("DFP", (ano, ano - 1, ano - 2)), ("ITR", (ano, ano - 1))):
        for a in anos:
            z = baixar(tipo, a)
            if z:
                zips.append((tipo, a, z))
    if not zips:
        raise RuntimeError("Demonstrações da CVM indisponíveis.")

    cnpjs = set(cnpjs)
    docs = defaultdict(dict)
    _carregar(zips, cnpjs, "con", docs)
    sem_consolidado = cnpjs - set(docs)
    if sem_consolidado:  # quem não tem controladas publica só o individual
        _carregar(zips, cnpjs, "ind", docs, so_estes=sem_consolidado)
    _carregar_acoes(zips, cnpjs, docs)
    return {cnpj: m for cnpj in cnpjs if (m := _metricas(docs.get(cnpj)))}
