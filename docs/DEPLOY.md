# 本番デプロイ

本番の構成と、デプロイ・教材投入の手順。設定値は `deploy/production.mk` にまとめている（秘密情報は含まない）。

## 構成

| 役割 | サービス | 場所 |
|------|---------|------|
| Web アプリ | Firebase Hosting | `https://tokyo03-514216.web.app` |
| API | Cloud Run `ailearn-api`（サービスアカウント `ailearn-api@…`） | asia-northeast1 |
| データ | Firestore（native） | asia-northeast1 |
| 音声 | Cloud Storage `tokyo03-514216.firebasestorage.app` | asia-northeast1 |
| 認証 | Firebase Authentication（Google・匿名） | — |
| 不正利用対策 | App Check（reCAPTCHA Enterprise）。API は `APP_CHECK_MODE=enforce` | — |
| AI | Vertex AI `gemini-3.8-flash`（global）、Cloud Text-to-Speech `gemini-2.5-flash-tts` | — |
| イメージ | Artifact Registry `ailearn` | asia-northeast1 |

## 費用の上限（ハッカソン予算：約 3,000 円）

- 予算アラート「ailearn hackathon tokyo03 (3000 JPY)」を、33% / 67% / 90% / 100% で通知するよう設定済み（このプロジェクトだけが対象。通知のみで、自動停止はしない）。
- Cloud Run は最小 0 台・最大 2 台、CPU はリクエスト処理中だけ使う（`--cpu-throttling`）。
- イメージは手元でビルドする（Cloud Build は使わない）。
- 読み上げた音声は Cloud Storage にキャッシュし、同じ文章は二度生成しない。セリフの事前生成（`make speak`）は件数を確認してから実行する。
- 紙しばいの絵（`make illustrate`、`gemini-3.1-flash-lite-image`）も Cloud Storage の `images/scenes/` にキャッシュし、1 回の実行で新しく頼むのは最大 30 枚。絵を表示するには `images/` を読めるルールの反映（`make deploy-rules`）と、対応表を埋めた教材の投入（`make seed-production`）が必要。
- 使った額の確認: Cloud コンソールの「お支払い」→「レポート」。

## 初回だけ必要な準備

済んでいるもの（2026-11-10）:
- 請求先アカウント k-ayato（紐付け済み）、予算アラート、API の有効化
- Firebase の追加、Web アプリ `ailearn-web` の登録
- Firestore・Storage バケット・Artifact Registry の作成
- サービスアカウントとロールの付与（`datastore.user`、`aiplatform.user`、`firebaseappcheck.tokenVerifier`、`logging.logWriter`、バケットへの `storage.objectUser`）
- App Check の reCAPTCHA Enterprise キーの登録

- Firebase コンソールでの Authentication の開始と、「匿名」「Google」ログインの有効化

## ログイン（各自 1 回）

ホストに gcloud は不要。ログイン情報は Docker ボリューム `ailearn-gcloud-config` に保存され、Makefile のコマンドがそれを使う（ホストの `~/.config/gcloud` に ADC があれば、そちらを優先する）。

対話が必要なため、Claude Code の `!` ではなく、普通のターミナルで実行する。

```bash
docker run -it --rm -v ailearn-gcloud-config:/root/.config/gcloud gcr.io/google.com/cloudsdktool/google-cloud-cli:592.0.0-slim gcloud auth login --no-launch-browser
docker run -it --rm -v ailearn-gcloud-config:/root/.config/gcloud gcr.io/google.com/cloudsdktool/google-cloud-cli:592.0.0-slim gcloud auth application-default login --no-launch-browser
docker run --rm -v ailearn-gcloud-config:/root/.config/gcloud gcr.io/google.com/cloudsdktool/google-cloud-cli:592.0.0-slim gcloud config set project tokyo03-514216
docker run --rm -v ailearn-gcloud-config:/root/.config/gcloud gcr.io/google.com/cloudsdktool/google-cloud-cli:592.0.0-slim gcloud auth application-default set-quota-project tokyo03-514216
```

## デプロイ

main にマージ済みのコミットをデプロイする（`deploy-api` と `deploy-web` は、`api/`・`app/` に未コミットの変更があると止まる）。

```bash
make deploy-rules   # Firestore / Storage のルールとインデックス
make deploy-api     # API を linux/amd64 でビルド → Artifact Registry → Cloud Run
make deploy-web     # 本番設定で Web をビルド → Firebase Hosting
make deploy         # 上の 3 つを順に
make deploy-status  # URL と API のリビジョン
```

- `deploy-web` は、Web アプリの設定（API キーを含む）をビルドのたびに Firebase から取得する。API の URL は Cloud Run から取得するため、先に `deploy-api` が必要。
- API は `APP_ENV=prod` で動き、App Check の無効化・Emulator の設定・AI の設定漏れがあると起動しない。

## 教材の投入

```bash
make seed-production CONFIRM_PROJECT=tokyo03-514216
```

`content/` を検証してから、本番の `units`・`lessons`・`exercises`・`answerKeys` を `content/` と同じ状態にする（`content/` にないドキュメントは消える）。`CONFIRM_PROJECT` にプロジェクト ID を書いたときだけ実行する。

## 動作確認

- `https://tokyo03-514216.web.app` を開き、ゲストでログイン → ニックネーム登録 → レッスンを最後まで遊ぶ。
- API のログ: Cloud コンソールの Cloud Run →「ailearn-api」→「ログ」（JSON 形式で、`severity`・リクエストのパス・ステータスが出る）。

## GitHub Actionsから再デプロイ

`.github/workflows/deploy.yml` をmainへマージすると、Actions → **Deploy production** → **Run workflow** から再デプロイできる。ブランチはmain、targetは `all`（APIとWeb）、`web`（画面だけ）、`api`（APIだけ）を選ぶ。mainの同じコミットでCIの6ジョブ（デプロイ設定検証を含む）がすべて成功していることが条件。CIが実行中なら最大20分待機する。成功した場合だけ続行し、CI失敗・キャンセル・タイムアウトならクラウド認証前に停止する。複数のデプロイは直列実行する。

認証はWorkload Identity Federation。秘密鍵JSONやFirebase CLIの長期トークンは登録しない。`production` 環境の以下のVariablesは設定済み（2026-11-10）。値は秘密情報ではない。

- `GCP_WORKLOAD_IDENTITY_PROVIDER`: `projects/396432345000/locations/global/workloadIdentityPools/github-deploy/providers/tokyo03-main`
- `GCP_DEPLOY_SERVICE_ACCOUNT`: `github-deploy@tokyo03-514216.iam.gserviceaccount.com`

Google Cloud側は `deploy/setup-github-oidc.sh` で設定・再現できる。管理者がgcloudで実行する一度限りの準備であり、ワークフローからIAM権限を変更しない。信頼条件はリポジトリID・所有者ID・main・対象ワークフローファイル・workflow_dispatchのすべて。forkやPRからのデプロイは許可しない。

デプロイ用SAはCloud Run Developer、Firebase Hosting Admin、Firebase Viewer、Service Usage Consumerをプロジェクトに持つ。Artifact Registry Writerは `ailearn` リポジトリ、Service Account Userは実行用 `ailearn-api` SAだけに付与する。ActionsではCloud Runの既存公開IAMを保持し、Firestore/Storageルール・教材・IAMは変更しない。

既存Makeターゲットをビルド・準備・公開に分割し、重いビルドの後でOIDC認証する。Web公開前には認証を更新する。`deploy/ci-make.sh` がADCのファイルをFirebase CLIコンテナへ渡す。認証ファイルはGit管理から除外し、アクション終了時に削除される。ActionsのSummaryにコミットとURLを記録する。

### 取り消し

APIはCloud Runの直前の正常リビジョンへトラフィックを戻す（例: `gcloud run services update-traffic ailearn-api --project tokyo03-514216 --region asia-northeast1 --to-revisions=<previous-ready-revision>=100`）。WebはFirebaseコンソールのHostingリリース履歴から直前の版へ戻す。データの書き換えはこのフローに含めないので、データ復元は不要。手動実行による旧コミットの直接指定は許可せず、GitのrevertをmainへマージしてCI通過後に再配備する方法も使える。

### 2026-11-10の再デプロイ記録

- 対象コミット: `eadfa8f87ff391c6c31e3d10c4395ba0a7789e44`（main、CI全5ジョブ成功）
- API: `ailearn-api-00003-8m8`（直前は `ailearn-api-00002-thw`）
- Hosting: `https://tokyo03-514216.web.app`
- APIの `/v1/health` は `status=ok` / `env=prod`。Hostingの `main.dart.js` はローカル本番ビルドとSHA-256が一致。
- 教材の再投入と有料AIの呼び出しは実施していない。
