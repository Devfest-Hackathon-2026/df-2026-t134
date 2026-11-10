# ailearn（仮称）

中高生向けの AI リテラシー学習アプリ。短いレッスン形式で、AI の回答からハルシネーションを見抜く力、適切なプロンプトを書く力、AI エージェントを使ってプロダクトを作る力を身につける。

- 要件定義書: [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- 実装プラン: [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md)
- UI・モーション・表示確認: [docs/UI_DESIGN.md](docs/UI_DESIGN.md)
- プロダクト情報・開発原則: [docs/PRODUCT.md](docs/PRODUCT.md)
- 本番デプロイ・教材の本番投入: [docs/DEPLOY.md](docs/DEPLOY.md)（本番 URL: https://tokyo03-514216.web.app）
- 共通の約束事（API・教材・Firestore の型とルール）: [docs/CONTRACTS.md](docs/CONTRACTS.md)、API 仕様: [docs/openapi.json](docs/openapi.json)（起動中は http://localhost:8000/docs）

## 開発環境

開発環境はすべて Docker コンテナで動く。ホストに Flutter・Python・Java・Firebase CLI を入れる必要はない。

| サービス | 中身 | URL |
|---------|------|-----|
| `app` | Flutter Web（debug、ホットリロード） | http://localhost:3000 |
| `api` | FastAPI（自動リロード） | http://localhost:8000（API ドキュメント: http://localhost:8000/docs） |
| `firebase` | Firebase Emulator Suite（Auth / Firestore / Storage） | Emulator UI: http://localhost:4000 |
| `tools` | 教材の検証・投入ツール（Python）。`make up` では起動せず、`make content-validate` / `make seed` で使う | — |

Emulator は `demo-ailearn` というデモプロジェクトで動くため、実際の Firebase プロジェクトやログインは不要で、外部に通信しない。

### 必要なもの

- Docker（Docker Desktop、または Colima）と Docker Compose v2
- `make`（macOS は Xcode Command Line Tools に含まれる）

Colima を使う場合（macOS）:

```bash
brew install colima docker docker-compose docker-buildx
# docker compose / buildx をプラグインとして認識させる
mkdir -p ~/.docker && cat > ~/.docker/config.json <<'JSON'
{ "cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"] }
JSON
colima start --cpu 4 --memory 6 --vm-type vz --mount-type virtiofs
```

### 起動

```bash
make up      # 初回はイメージのビルドに数分かかる
```

別のターミナルで `make seed` を実行して Unit 1 の教材を投入する。ブラウザで http://localhost:3000 を開き、「ゲストではじめる」→ ニックネーム・学年の設定 → 学習パスまで進めば準備完了。API の接続状態は学習パス上部のドットで確認できる。

- 停止: `Ctrl+C` のあと `make down`
- Flutter のホットリロード: 別のターミナルで `docker compose attach app` を実行し、`r`（リロード）または `R`（再起動）。抜けるときは `Ctrl+P` → `Ctrl+Q`
- 設定を変えたいとき: `cp .env.example .env` で `.env` を作って編集する（`.env` はコミットしない）

### テスト・lint

```bash
make check       # CI と同じチェックをすべて実行
make check-api   # API: ruff（lint・format）+ pytest（ネットワーク不要）
make check-api-integration # 実際のUnit 1教材とFirestore Emulatorで回答・完了・同時実行を検証
make check-app   # Flutter: dart format + flutter analyze + flutter test
make check-rules # Firestore / Storage のセキュリティルールのテスト（Emulator）
make check-schemas # 書き出した型（openapi.json など）が最新か
make check-tools # 教材ツール: ruff（lint・format）+ pytest + content/ の検証
make schemas     # API・教材・Firestore の型を JSON に書き出す
make fix-api     # API の lint・format を自動修正
make fix-tools   # 教材ツールの lint・format を自動修正
```

### 教材（content/）

教材は `content/units/` の YAML で書く。ファイルの形式と検証内容は [content/README.md](content/README.md)。

```bash
make content-validate  # 教材を検証する（問題があればファイルのパスつきで全部表示して失敗）
make seed              # 検証してから Firestore Emulator に投入する（Emulator が止まっていれば起動する）
```

マスコットの固定セリフ（`intro`）と紙しばい（story）の場面のセリフの音声は `make speak` で、紙しばいの場面の絵は `make illustrate` で前もって作る（どちらも Google Cloud の認証が必要で、費用がかかる）。使い方と費用の上限は [content/README.md](content/README.md)。

```bash
make speak TTS_MODEL=gemini-2.5-flash-tts STORAGE_BUCKET=tokyo03-514216.firebasestorage.app FIREBASE_PROJECT_ID=tokyo03-514216
make illustrate IMAGE_MODEL=gemini-3.1-flash-lite-image VERTEX_PROJECT=tokyo03-514216 \
  STORAGE_BUCKET=tokyo03-514216.firebasestorage.app FIREBASE_PROJECT_ID=tokyo03-514216
```

ハルシネーション探しの問題は `make draft-hallucination` で Gemini に下書きを作らせられる（Google Cloud の認証が必要）。使い方と、人が確かめて公開するまでの手順は [content/drafts/README.md](content/drafts/README.md)。

`make seed` は `units` / `lessons` / `exercises` / `answerKeys` を content と同じ状態にする（何度実行してもよく、content から消したドキュメントは削除される）。投入先は Emulator だけで、`FIRESTORE_EMULATOR_HOST` がないと実行しない。投入した中身は Emulator UI（http://localhost:4000/firestore）で確認できる。

`make check-api-integration` はホストのポートを公開しない専用の Firestore Emulator を起動し、教材を投入して結合テストを実行したあと停止・削除する。`make up` と同時に実行でき、実際の Google Cloud プロジェクトや認証情報は不要。

Dart の整形は `docker compose run --rm --no-deps app dart format lib test` で行う。

### AI を使う機能（Gemini）

API は Vertex AI の Gemini を `api/app/ai/` のラッパー経由でだけ呼ぶ。認証は Application Default Credentials（Cloud Run ではサービスアカウント）で行い、API キーは使わない。設定は環境変数で渡す。

| 変数 | 内容 |
|------|------|
| `GEMINI_MODEL` | 使うモデル ID。コードには書かず、ここでだけ決める |
| `VERTEX_PROJECT` | Vertex AI を呼ぶ Google Cloud プロジェクト ID（`GEMINI_MODEL` とセットで指定） |
| `VERTEX_LOCATION` | Vertex AI のロケーション（省略時は `global`） |
| `TTS_MODEL` | フィードバックの読み上げに使う Gemini-TTS のモデル ID（Cloud Text-to-Speech API 経由。`STORAGE_BUCKET` とセットで指定） |
| `TTS_VOICE` | マスコットの声の名前（省略時は `Leda`）。Gemini-TTS が使えないときは、同じ名前の Chirp 3 HD の声（`ja-JP-Chirp3-HD-<名前>`）に切り替わる |
| `STORAGE_BUCKET` | 音声を保存する Cloud Storage（Firebase Storage）のバケット名 |
| `LIVE_CHECK_DAILY_LIMIT` | ライブ検証（Q10、`/v1/live-checks`）を 1 人が 1 日（Asia/Tokyo の日付）に始められる回数（省略時は `10`、1〜100）。超えると 429（`rate_limited`）を返し、モデルは呼ばない |

- `GEMINI_MODEL` と `VERTEX_PROJECT` が未設定なら AI の採点はオフになり、`/v1/prompt/evaluate` は 503（`upstream_unavailable`）を返す。`TTS_MODEL` と `STORAGE_BUCKET` が未設定なら読み上げがオフになり、`/v1/tts` が 503 を返す。`make up` はどちらもオフの状態で動く（個人情報を含むプロンプトのブロックは AI なしで動く）。
- 本番（`APP_ENV=prod`）では 4 つすべてがないと API が起動しない。Cloud Run のサービスアカウントには Vertex AI ユーザー（`roles/aiplatform.user`）と、バケットへの読み書き（`roles/storage.objectUser` など）のロールが必要。Cloud Text-to-Speech API も有効にしておく。
- ライブ検証は 1 回につき Gemini を 2 回（Google 検索つきの回答 1 回と、文の書きかえ 1 回）呼ぶ。出力が合わないときは時間内なら 1 回だけ作り直す。`GEMINI_MODEL` が未設定なら 503 を返し、アプリは理由を伝えてスキップできる。
- 読み上げた音声は `audio/feedback/<声と文章のハッシュ>.mp3` に保存し、同じ文章の 2 回目からは保存済みの音声を返す（解説文はすべての生徒で共通なので、合成は 1 回で済む）。

本物のモデルで採点のぶれを確かめるときは、`gcloud auth application-default login` を済ませてから次を実行する。見本のプロンプトを何回か採点して、観点別の点数と最小・最大を表示する（回数は `RUNS` で変えられ、省略時は 3 回）。

```bash
GEMINI_MODEL=<モデル ID> VERTEX_PROJECT=<プロジェクト ID> make try-prompt-grader
```

### 依存の追加

```bash
# API: api/pyproject.toml を編集してから
make lock-api && docker compose build api

# 教材ツール: tools/pyproject.toml を編集してから
make lock-tools && docker compose build tools

# Flutter
docker compose run --rm --no-deps app flutter pub add <package>
```

### ビルド

```bash
make build-api-prod                                  # Cloud Run 用イメージ
API_BASE_URL=https://<api の URL> make build-web     # app/build/web に Web のリリースビルド
```

## ディレクトリ構成

```
app/        Flutter アプリ
api/        バックエンド API（FastAPI、Cloud Run）
content/    教材データ（YAML。形式は content/README.md）
tools/      教材の検証・投入・生成ツール
firebase/   Firestore / Storage のセキュリティルール
docker/     開発用イメージ（Flutter、Firebase Emulator）
docs/       要件定義書・実装プランなど
```

## バージョン

ツールのバージョンは Dockerfile で固定している。上げるときは PR で変更する。

| ツール | バージョン | 定義場所 |
|-------|-----------|---------|
| Flutter | 3.47.9 | `docker/flutter/Dockerfile` |
| Python | 3.13 | `api/Dockerfile`、`tools/Dockerfile` |
| uv | 0.13.7 | `api/Dockerfile`、`tools/Dockerfile` |
| Node.js | 24 | `docker/firebase/Dockerfile` |
| Java | 21 | `docker/firebase/Dockerfile` |
| firebase-tools | 15.35.0 | `docker/firebase/Dockerfile` |
