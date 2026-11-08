# Invest Show: app + robô de oportunidades

```
app/                        app Flutter (Oportunidades, Carteira, Minha lista, Comparar)
screener/screener.py        robô que varre a B3, calcula os indicadores e monta o ranking
screener/cvm.py             leitura dos balanços oficiais (dados abertos da CVM)
.github/workflows/          agenda o robô todo dia útil
dados/fundamentos.json      indicadores de todas as ações (telas Detalhe e Comparar)
dados/oportunidades.json    ranking (aba Oportunidades)
dados/analises.json         leitura do ranking pelo Gemini (detalhe da ação)
screener/analise_ia.py      chamada ao Gemini
```

## De onde vêm os dados

Tudo funciona no plano **gratuito** da brapi:

- **brapi**: só cotação, histórico de preços e a lista de ações com volume e valor de mercado.
- **CVM** (dados.cvm.gov.br): balanço, DRE e fluxo de caixa de todas as companhias abertas, gratuitos e oficiais. O robô baixa todo dia útil e calcula lucro, patrimônio, EBITDA, dívida e dividendos dos últimos 12 meses.

O app junta as duas fontes: os indicadores que dependem do preço (P/L, P/VP, DY, valor de mercado, preço justo) são recalculados com a cotação do dia. O ranking da aba Oportunidades também: ao abrir a aba (e a cada 5 minutos com ela aberta) o app baixa o preço de toda a bolsa numa chamada só da brapi e refaz filtros, nota e ordem. Os balanços mudam só a cada trimestre; o que move o ranking no dia a dia é o preço.

## 1. Subir para o GitHub

1. Crie um repositório **público** (ex.: `acoes`) e envie esta pasta inteira.
   Público porque o app baixa o ranking direto do GitHub sem login. O repositório só tem código e dados de mercado; o token fica protegido no passo 2.
2. (Opcional) Em **Settings → Secrets and variables → Actions → New repository secret**, crie `BRAPI_TOKEN` com o seu token da brapi. O robô funciona sem ele.
3. Se a primeira execução falhar no `git push`, vá em **Settings → Actions → General → Workflow permissions** e marque **Read and write permissions** (o robô precisa gravar os arquivos).
4. Em **Actions → Screener diário → Run workflow**, rode a primeira vez. Leva uns 2 minutos. Depois disso ele roda sozinho de segunda a sexta, às 18h (depois do fechamento da B3).

Para rodar no computador: `pip install requests` e `python screener/screener.py`.

### Leitura da IA (opcional)

Com uma chave do Gemini, o robô escreve para cada ação do ranking um resumo, pontos fortes, riscos e o que os fatos relevantes e comunicados dos últimos 120 dias à CVM sugerem. Grava em `dados/analises.json`, e o app mostra no detalhe da ação, no card "Leitura da IA".

1. Em **Settings → Secrets and variables → Actions → New repository secret**, crie `GEMINI_API_KEY` com a sua chave.
2. (Opcional) Para trocar o modelo, defina `GEMINI_MODEL` no workflow (padrão: `gemini-3.8-flash`).
3. (Opcional) `GEMINI_MODELO_RESERVA` (padrão: `gemini-3.5-flash-lite`) é usado quando o principal está sobrecarregado (HTTP 503), demora demais ou fica sem cota no dia; cada modelo tem a própria cota no plano gratuito. Deixe vazio para desligar. O detalhe da ação mostra qual modelo escreveu cada leitura.

Os números vêm do robô; a IA só comenta. Se a chamada falhar para uma ação, fica a leitura anterior.

No plano gratuito do Gemini há limite de chamadas por minuto e por dia. O robô faz uma chamada a cada 13 s (`IA_INTERVALO_S`), espera o tempo que o Google pede quando recebe "quota exceeded" (HTTP 429) e, se a cota do dia acabou, passa para o modelo reserva. Com os dois sem cota, ou com 3 ações seguidas sem resposta, para e tenta de novo na próxima execução. As leituras que já existem ficam até serem refeitas. Se o log mostrar `PerDay` em todas as execuções, a cota diária do modelo não cobre as 15 ações: troque `GEMINI_MODEL` por um modelo mais leve ou ative o faturamento no Google AI Studio.

## 2. Ajustar os critérios (opcional)

Os filtros ficam no topo de `screener/screener.py` (`CRITERIOS` e `PESOS`): ROE mínimo, P/L máximo, dívida máxima, taxa de Bazin, quantas ações analisar e quantas mostrar. Também dá para mudar por variável de ambiente no workflow, por exemplo `ROE_MIN: "15"`.

## 3. Montar o app

Dentro da pasta do repositório:

```bash
flutter create --project-name acoes_app --platforms=android app
cd app
rm test/widget_test.dart
flutter pub get
```

O `flutter create` só gera o que falta (pasta android etc.) e mantém os arquivos que já estão em `app/`.

Em `app/android/app/src/main/AndroidManifest.xml`, adicione antes de `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## 4. Rodar e gerar o APK

Troque `USUARIO` e `REPO` pelos seus:

```bash
flutter build apk --release \
  --dart-define=BRAPI_TOKEN=seu_token \
  --dart-define=OPORTUNIDADES_URL=https://raw.githubusercontent.com/USUARIO/REPO/main/dados/oportunidades.json
```

O APK sai em `app/build/app/outputs/flutter-apk/app-release.apk`. Para testar ligado ao PC, use `flutter run` com os mesmos `--dart-define`.

O app procura `fundamentos.json` na mesma pasta de `OPORTUNIDADES_URL`. O token da brapi no app serve só para as cotações; sem ele, apenas PETR4, VALE3, ITUB4 e MGLU3 respondem.

## Como o ranking funciona

1. Pega as 300 ações mais negociadas, uma classe por empresa.
2. Para cada empresa, soma os últimos 12 meses do último balanço entregue à CVM: acumulado do ITR + exercício anterior − mesmo período do ano anterior.
3. Elimina: valor de mercado abaixo de R$ 500 milhões, balanço com mais de 400 dias, lucro ou patrimônio negativos, ROE abaixo de 10%, margem líquida negativa, Dív. líquida/EBITDA acima de 3, P/L acima de 30, e preço acima do preço justo de Graham **e** de Bazin.
4. Preço justo de Graham = √(22,5 × LPA × VPA). Preço justo de Bazin = dividendos e JCP pagos em 12 meses (fluxo de caixa) ÷ 6%.
5. Nota de 0 a 100 por posição relativa: ROE 30%, margem líquida 20%, lucro/preço 25%, maior potencial (Graham ou Bazin) 25%. Bancos não têm margem líquida; para eles os outros fatores pesam mais.
6. As 15 melhores vão para `dados/oportunidades.json`, com quantas ações caíram em cada filtro.

Limitações conhecidas:

- **Dividendos** são os pagos no caixa, incluindo extraordinários; o DY pode estar inflado por um pagamento que não se repete.
- **Quantidade de ações** vem do balanço; se houve desdobramento ou emissão depois dele (diferença maior que 2x para o valor de mercado da brapi), o robô usa a quantidade implícita no valor de mercado.
- **EBITDA** = resultado operacional + depreciação e amortização do fluxo de caixa; não há EBITDA, margens nem dívida para bancos e seguradoras.

É um filtro para escolher o que analisar, não recomendação de compra.
