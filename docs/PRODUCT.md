# プロダクト情報

> このファイルはチームで自由に編集します（変更は PR で共有）。CLAUDE.md から読み込まれます。

- プロダクト名: ailearn（仮称）
- 概要: 中高生向けの AI リテラシー学習アプリ。短いレッスン形式で、AI の回答からハルシネーションを見抜く力、適切なプロンプトを書く力、AI エージェントを使ってプロダクトを作る力を身につける。
- 要件定義書: [docs/REQUIREMENTS.md](REQUIREMENTS.md)
- 実装プラン: [docs/IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)（PR の順番・担当ディレクトリ・完了の定義）
- 技術スタック: Flutter（Web 主）/ Firebase（Hosting・Authentication・Firestore・Storage・App Check）/ Cloud Run（Python・FastAPI）/ Vertex AI の Gemini・Gemini TTS / Agent Development Kit
- 開発環境: すべて Docker コンテナで動く（Flutter・Python・Firebase Emulator をホストに入れない）。詳細は [README](../README.md)
- セットアップ手順: Docker（Docker Desktop または Colima）と `make` を用意する
- 起動方法: `make up` → http://localhost:3000（API: http://localhost:8000、Emulator UI: http://localhost:4000）
- デプロイ: `make deploy`（Firebase Hosting・Cloud Run）。手順・費用の上限は [docs/DEPLOY.md](DEPLOY.md)
- テスト・lint の実行方法: `make check`（CI と同じ）。個別には `make check-api`（オフライン単体テスト） / `make check-api-integration`（専用 Firestore Emulator で回答・完了・同時実行を検証） / `make check-app` / `make check-rules` / `make check-schemas` / `make check-tools`。教材は `make content-validate`（検証）と `make seed`（Emulator へ投入）
- ディレクトリ構成: 実装プランの §2 を参照（`app/` Flutter、`api/` バックエンド、`content/` 教材、`tools/` 教材ツール、`firebase/` ルール、`docker/` 開発用イメージ）

## 開発原則

このプロジェクトのすべてのコードは以下を守ること。

### 独立性を保つ（直交性）
「1箇所を変えても他所に影響しない」状態を保つ。
- 関数の引数は互いに独立させる。「片方の引数の値によってもう片方の意味が変わる」
  引数の組を作らない。そうなりそうなら関数を分けるか、組み合わせを型で表現する
- 真偽値で振る舞いを切り替えるフラグ引数（`doX(data, true)`）は作らず、別関数に分ける
- グローバル状態やシングルトンへの暗黙依存を作らない。必要な値は引数で渡す
- 同じ知識（仕様・定数・ロジック）を2箇所に書かない。ただし「たまたま似ているだけのコード」の
  無理な共通化は結合を増やすのでしない
- 外部ライブラリ・DB・外部APIへは薄いラッパー1枚を挟み、後で差し替えられるようにする

### 境界で検証し、早く失敗する
網羅的な防御ではなく「入口で検証し、内部は信頼し、異常なら即座に止まる」設計にする。
- 外から値が入ってくる場所（API受け口・ユーザー入力・ファイル読み込み・公開関数）の
  入口で引数を検証する。検証を通った値は内側の関数で再検証しない
- 不正な値・ありえない状態を検出したら、デフォルト値で握りつぶして続行せず、
  即座に例外を投げて止める。壊れたまま動き続けるより、すぐ止まるほうが原因特定が速く被害も小さい
- try-catch を至る所に書かない。catch するのは「その場で意味のある回復ができる場所」だけで、
  それ以外は上に伝播させる
- 「null は来ない」「正の数のみ」といった前提はコメントでなく、型・assert・バリデーションの
  コードで表現する
- 通常フローで起こりうる失敗（検索ヒットなし等）は戻り値や Result 型で返し、
  例外は「起きてはならない事態」にだけ使う

### 共有状態は一箇所に集約する
複数のコンポーネント（または並列エージェント）が状態を共有するときのルール。
- 互いを直接参照させず、共有ストア・キュー・共有ファイルなど「一箇所の置き場」を介して読み書きする
- 各コンポーネントが触ってよいリソースは排他に分割する。同じリソースに2者が書き込む設計に
  なったら分割をやり直す
- 「AがBより先に動くはず」という暗黙の順序依存を作らない。順序が必要なら
  共有置き場の状態（フラグ・イベント）で明示する

### 迷ったら保守的に
選択に迷ったら、直列実行・実績のあるライブラリ・明示的で読めば分かるコードを選ぶ。

## プロジェクト固有の規約

- AI（Gemini・TTS・ADK）の呼び出しは `api/app/ai/` のラッパー経由でのみ行う。モデル ID は環境変数で指定し、コードに直書きしない
- AI の出力は必ず JSON スキーマ（Pydantic）で検証してから使う
- 正解キー・採点ロジックはサーバー側にだけ置き、クライアントに渡さない
- XP・スコアなど成績に関わる値は、サーバー（Admin SDK）だけが Firestore に書き込む
- ホストに直接ツールを入れず、コマンドは `make` か `docker compose run` 経由で実行する。ツールのバージョンは Dockerfile で固定する
- 共通の約束事（`api/app/schemas/`、`firebase/*.rules`）は、機能 PR の中で変えず、専用の PR で変える。手順は [docs/CONTRACTS.md](CONTRACTS.md)
