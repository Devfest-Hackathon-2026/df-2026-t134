# 共通の約束事（コントラクト）

フロントエンド・バックエンド・教材・ルールが共有する定義。**正本は下の表の左列だけ**で、右列は自動生成または正本に合わせて書くもの。

| 正本 | 内容 | 生成物・追従するもの |
|------|------|------------------|
| `api/app/schemas/answers.py`、`prompt.py`、`tts.py`、`lessons.py`、`live_check.py`、`common.py` | API のリクエスト / レスポンス、エラー形式 | `docs/openapi.json`（`make schemas`）、Flutter の `app/lib/models/` |
| `api/app/schemas/content.py` | 教材（ユニット・レッスン・問題・正解キー） | `content/schema/*.schema.json`（`make schemas`）、`content/` の YAML |
| `api/app/schemas/firestore.py` | Firestore のドキュメントとコレクションの権限表 | `docs/schemas/firestore/*.schema.json`（`make schemas`）、`firebase/firestore.rules` |
| `firebase/firestore.rules`、`firebase/storage.rules` | クライアントからのアクセス権限 | `firebase/tests/`（`make check-rules`） |

## ルール

- JSON のフィールド名は camelCase（`exerciseId`）、Python は snake_case（`exercise_id`）。変換は `Contract` 基底クラスが行う。
- 未知のフィールドは拒否する。問題・回答・結果の種類は `type`（プロンプト採点の結果は `status`）で判別する。
- エラーはすべて `{"error": {"code": ..., "message": ...}}`。入力の検証エラーは 400 / `bad_request`。
- 正解キー（`answerKeys`）と下書き（`exerciseDrafts`）は、クライアントから一切アクセスできない。
- XP・ストリーク・回答の記録はサーバーだけが書く。クライアントが書けるのは `users/{uid}` のニックネームと学年だけ。
- 音声（Cloud Storage の `audio/`）と紙しばいの絵（`images/`）はログインユーザーが読めるだけで、クライアントからはアップロードできない。

## 変更するとき

1. 機能の PR の中では変えない。先に、約束事だけを変える PR（`change/〇〇`）を出す。
2. 正本を編集して `make schemas` を実行し、生成物も同じ PR でコミットする（CI の `make check-schemas` が差分を検出する）。
3. ルールを変えたら `firebase/tests/` にテストを足し、`make check-rules` を通す。
4. 要件定義書の §9（データモデル）・§10（API）も合わせて更新する。
