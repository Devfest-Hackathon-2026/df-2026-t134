# 問題の下書き（content/drafts/）

AI（Gemini）が作った問題の下書きを置く場所。ここにあるファイルは検証（`make content-validate`）にも投入（`make seed`）にも使われないので、アプリには出ない。人が確かめてから `content/units/` に移したものだけが公開される（要件 §5.2・§14 R4）。

## ハルシネーション探し（Q2）の下書きを作る

`gcloud auth application-default login` を済ませてから、レッスン ID とテーマを指定して実行する。テーマごとに `hallucination/<レッスン ID>-d<番号>.yaml` が 1 つできる。

```bash
GEMINI_MODEL=<モデル ID> VERTEX_PROJECT=<プロジェクト ID> \
  make draft-hallucination ARGS="--lesson u3-l1 --topic 光合成 --topic 富士山"
```

- 入れる誤りの種類は `--error-type` で 1〜3 個指定する（省略時は `number` と `causality`）。種類は `number`（数値）・`date`（日付）・`name`（人名・地名）・`fake_source`（存在しない出典）・`causality`（因果関係）・`fact`（事実）。
- 下書きを作る流れ:
  1. Google 検索で根拠をとりながら、テーマの正しい解説文（4〜8 文）を書かせる。
  2. 別の指示で、指定した種類の誤りをいくつかの文に入れさせる。
  3. もとの正しい文を、正解キーの「正しい内容」にする。
- 教材の品質を優先するなら、`GEMINI_MODEL` には採点に使うモデルより性能の高いモデルを指定してよい。
- AI の出力がおかしいテーマ（文の数が合わない、誤りの種類が違う、など）は下書きを作らずに報告するので、もう一度実行する。

## 公開するまでの手順

1. `review.sources` のページやほかの信頼できる資料で、`review.correctSentences`（もとの正しい文）の事実を 1 つずつ確かめる。正しい文そのものがまちがっていたら直す（`answerKey` の `correction` も同じように直す）。
2. `exercise.sentences` のまちがった文が、もっともらしいがはっきりまちがっていること、`tip` が答えをそのまま言っていないことを確かめる。
3. ID を `<レッスン ID>-d<番号>` から、レッスンの中の問題番号（`<レッスン ID>-q<番号>`）に変える。
4. `exercise` をレッスンファイル（`content/units/<ユニット>/<レッスン>.yaml`）の `exercises` に移し、`lesson.exerciseIds` に ID を足す。`answerKey` は同じ ID をキーにして `.answers.yaml` に移す。
5. `make content-validate` と `make seed` を実行し、アプリで遊んで確かめる。
6. 移し終えた下書きファイルを消し、同じ PR でレビューしてもらう。
