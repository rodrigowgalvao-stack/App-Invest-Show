# Ações: app + robô de oportunidades

```
app/                        app Flutter (Oportunidades, Minha lista, Comparar)
screener/screener.py        robô que varre a B3 e monta o ranking
.github/workflows/          agenda o robô toda semana
dados/oportunidades.json    ranking gerado pelo robô (o app lê este arquivo)
```

## 1. Subir para o GitHub

1. Crie um repositório **público** (ex.: `acoes`) e envie esta pasta inteira.
   Público porque o app baixa o ranking direto do GitHub sem login. O repositório só tem código e dados de mercado; o token fica protegido no passo 2.
2. Em **Settings → Secrets and variables → Actions → New repository secret**, crie `BRAPI_TOKEN` com o seu token da brapi.
3. Em **Settings → Actions → General → Workflow permissions**, marque **Read and write permissions** (o robô precisa gravar o ranking).
4. Em **Actions → Screener semanal → Run workflow**, rode a primeira vez. Leva alguns minutos. Depois disso ele roda sozinho todo domingo às 19h.

Se a execução falhar dizendo que a API não devolveu indicadores, o seu plano da brapi não inclui os módulos fundamentalistas.

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

## Como o ranking funciona

1. Pega as 300 ações mais negociadas, uma classe por empresa, com valor de mercado acima de R$ 500 milhões.
2. Elimina: lucro ou patrimônio negativos, ROE abaixo de 10%, margem líquida negativa, Dív. líquida/EBITDA acima de 3, P/L acima de 30, e preço acima do preço justo de Graham **e** de Bazin.
3. Preço justo de Graham = √(22,5 × LPA × VPA). Preço justo de Bazin = dividendos de 12 meses ÷ 6%.
4. Nota de 0 a 100 por posição relativa: ROE 30%, margem líquida 20%, lucro/preço 25%, maior potencial (Graham ou Bazin) 25%.
5. As 15 melhores vão para `dados/oportunidades.json`. O arquivo também registra quantas ações caíram em cada filtro.

É um filtro para escolher o que analisar, não recomendação de compra.
