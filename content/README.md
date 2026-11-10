# 教材データ（content/）

教材の中身は YAML で書き、`tools/` のツールで検証してから Firestore に投入する。
形式の正本は `api/app/schemas/content.py`（JSON Schema は `content/schema/`、`make schemas` で生成）。

## ファイル構成

```
content/units/<unitId>/unit.yaml                  ユニット（Unit）
content/units/<unitId>/<lessonId>.yaml            レッスンとその問題（Lesson と Exercise の一覧）
content/units/<unitId>/<lessonId>.answers.yaml    そのレッスンの正解キー（問題 ID → AnswerKey）
```

- キーは JSON と同じ camelCase（`unitId`、`exerciseIds`、`correctOptionId` など）。
- ID は小文字のケバブケース: ユニット `u1`、レッスン `u1-l1`、問題 `u1-l1-q1`。レッスン ID はユニット ID で、問題 ID はレッスン ID で始める。
- ファイル名は ID と同じにする（`u1-l1.yaml` の中のレッスン ID は `u1-l1`）。
- 正解キーは別ファイルに分け、Firestore の `answerKeys` にだけ投入する（クライアントからは読めない）。

レッスンファイルの例:

```yaml
lesson:
  id: u1-l1
  unitId: u1
  order: 1
  title: AI はどうやって文章をつくる？
  exerciseIds: [u1-l1-q1]
  intro:
    text: マスコットが最初に話すセリフ
exercises:
  - id: u1-l1-q1
    lessonId: u1-l1
    type: choice
    question: 問題文
    options:
      - {id: a, text: 選択肢 A}
      - {id: b, text: 選択肢 B}
```

正解キーファイルの例:

```yaml
u1-l1-q1:
  type: choice
  correctOptionId: b
  explanation: 解説（正解・不正解のどちらでも表示する）
```

## 紙しばい（story）の書き方

場面（`scenes`）を 1 枚ずつ見せたあと、`question`（「ユイはどうする？」）で選択肢をえらばせ、えらんだ選択肢の「そのあと」（`outcomes`）を見せてから解説を出す。どの選択肢がいちばんよいか・そのあとどうなるかは正解キーにだけ書く。

```yaml
# u1-l4.yaml の exercises の 1 つ
- id: u1-l4-q1
  lessonId: u1-l4
  type: story
  title: 自由研究と AI の答え
  question: ユイはどうする？
  scenes:                          # 1〜8 場面（教材では 3〜6）
    - speaker: narrator            # narrator / mascot / student（ユイ）/ friend（ソウタ）/ teacher / ai
      text: 夏休み。ユイは、自由研究で…
      illustration:                # 省略すると、前の場面の絵をそのまま見せる
        prompt: >-                 # 絵の説明（英語）。共通の画風は make illustrate が前に付ける
          Summer evening in Yui's small, tidy bedroom. …
    - speaker: ai
      text: ホタルは、おしりの中で電気をつくって…
  options:                         # 2〜4 こ
    - {id: copy, text: AI の答えを、そのままレポートに書く}
    - {id: check, text: 図鑑や信頼できるサイトで、本当にそうか確かめてから書く}
```

```yaml
# u1-l4.answers.yaml
u1-l4-q1:
  type: story
  bestOptionId: check
  outcomes:                        # 選択肢ごとに 1 つ。場面は 1〜4（教材では 1〜3）
    - optionId: copy
      scenes:
        - speaker: teacher
          text: ホタルの光は、電気ではなく…
    - optionId: check
      scenes: [...]
  explanation: 解説（どれをえらんでも、そのあとの場面のあとに表示する）
```

- 登場人物はオリジナル: ユイ（中学 2 年の女の子）、友だちのソウタ、先生、AI アシスタント（光る小さなタブレット）、ナレーション。実在の人物・商品名は出さない。マスコットの名前はまだ決めない（セリフでは名前を出さない）。
- `audioPath` と `illustration.imagePath` は書かない（`make speak` / `make illustrate` の対応表から `make seed` が埋める）。絵や音声がまだない場面は、アプリが字幕と落ち着いた代わりの絵を表示する。

## 検証される内容（`make content-validate`）

- 各ファイルが形式（Pydantic モデル）に合っている。YAML のキーの重複もエラー
- ユニット・レッスン・問題・正解キーの ID が重複していない。ユニットの `order`、ユニット内のレッスンの `order` が重複していない
- ID とフォルダ名・ファイル名が一致し、レッスンの `unitId` が存在する
- レッスンの `exerciseIds` の問題がすべてあり、その `lessonId` がそのレッスンになっている。どのレッスンにも載っていない問題がない
- すべての問題に、同じ `type` の正解キーがちょうど 1 つある。問題のない正解キーがない
- 種類ごとの対応: choice の正解が選択肢にある / order の正解が項目の並べ替えになっている / fill_blank の正解が空欄ごとにあり、その空欄の選択肢の中にある / hallucination の誤りの位置が文の範囲内で、数が `errorCount` と一致する / story の `bestOptionId` が選択肢にあり、`outcomes` が選択肢ごとにちょうど 1 つある
- 生成物のパス（`intro.audioPath`、場面の `audioPath`・`illustration.imagePath`）を手で書いていない。`content/audio/lines.yaml` と `content/images/scenes.yaml` が形式に合っている

問題が 1 つでもあれば、ファイルのパスつきで全部表示して失敗する。

## ライブ検証（live_check、Q10）の書き方

生徒が自分で書いた質問（または例のタップ）に Gemini が Google 検索つきで答え、サーバーがその場で `errorCount` 文をこっそり書きかえる。答えも誤りも生徒ごとに作るので、教材に書くのはテーマ・質問の例・回数と、正解キーの「答えてよい範囲」だけ。

```yaml
  - id: u3-l1-q3
    lessonId: u3-l1
    type: live_check
    question: AI に富士山のことを質問しよう。まちがった文が 1 つまぎれこんでいるよ。
    theme: 富士山                # 答えの見出しと、AI に伝えるテーマ
    suggestions:                 # 1〜4 個。タップすると入力欄に入る
      - 富士山の高さと、どこにあるかを教えて
    errorCount: 1                # 書きかえる文の数（1〜2）
    lookupLimit: 2               # 「調べる」の回数（0〜5、省略時 2）
    maxLength: 200               # 質問の最大文字数（20〜400、省略時 200）
```

```yaml
u3-l1-q3:
  type: live_check
  topicGuide: |-
    富士山について答えてよい: 高さ、場所、でき方、噴火の歴史、世界文化遺産の登録 …
    富士山と関係のない話題、人のうわさ話、危険な登り方は対象外。
```

- `topicGuide` は AI への指示に入る（生徒には見えない）。答えてよい範囲と対象外を具体的に書く。範囲の外の質問は `off_topic`、ふさわしくない質問は `inappropriate` としてブロックされ、記録されない。
- テーマは、検索で確かめられる事実が多く、子ども向けに安全なもの（自然・宇宙・歴史・地理など）を選ぶ。人物のうわさや時事の争点は避ける。
- 1 人 1 日の回数は API の `LIVE_CHECK_DAILY_LIMIT`（省略時 10 回）で制限される。

## セリフの音声（content/audio/lines.yaml）

レッスンと問題の `intro.text`（マスコットの固定セリフ）と、紙しばいの場面（問題の `scenes` と正解キーの `outcomes`）のセリフは、`make speak` で前もって音声にしておく。生徒が回答したあとの解説の音声は、API（`POST /v1/tts`）がその場で作る。

```bash
make speak TTS_MODEL=gemini-2.5-flash-tts STORAGE_BUCKET=tokyo03-514216.firebasestorage.app FIREBASE_PROJECT_ID=tokyo03-514216
```

- すべてのセリフを、話す人（`speaker`）ごとの Gemini-TTS の声で読み上げる（使えないときは同じ名前の Chirp 3 HD の声にする）。声と話し方は `tools/content_tools/scene_voices.py`: ナレーションは落ち着いた読み聞かせ（Sulafat）、ユイは明るい中学生の女の子（Zephyr）、ソウタは元気な男の子（Puck）、先生はあたたかく落ち着いた声（Kore）、AI は少し機械的でやさしい声（Iapetus）、マスコットは API と同じ声（`TTS_VOICE`、省略時は Leda）。
- 音声は Cloud Storage の `audio/lines/<声と文章のハッシュ>.mp3` に保存する。保存済みのセリフは作り直さないので、何度実行してもよい。最後に「新しく作った数（newly synthesized）」を表示する。
- 同じ文章でも話す人がちがえば別の音声になる。セリフと音声の対応（話す人・文章・保存先）を `content/audio/lines.yaml` に書き出すので、コミットする。`make seed` は、この対応表から `intro.audioPath` と場面の `audioPath` を埋める。
- `audioPath` を YAML に手で書かない（検証でエラーになる）。セリフを書きかえたら、`make speak` をやり直すまで、そのセリフは音声なし（字幕だけ）になる。
- Google Cloud の認証は docs/DEPLOY.md の「ログイン」（Docker ボリューム `ailearn-gcloud-config`）を使う。

## 紙しばいの絵（content/images/scenes.yaml）

紙しばいの場面の `illustration.prompt` は、`make illustrate` で Vertex AI の Gemini 画像モデルに描かせておく。

```bash
make illustrate IMAGE_MODEL=gemini-3.1-flash-lite-image VERTEX_PROJECT=tokyo03-514216 \
  STORAGE_BUCKET=tokyo03-514216.firebasestorage.app FIREBASE_PROJECT_ID=tokyo03-514216
```

- 画風はすべての絵で共通（`tools/content_tools/illustrations.py` の `STYLE_PROMPT`）: アイボリーとテラコッタを基調にした、やわらかい水彩の絵本風。ユイ・ソウタ・先生・AI アシスタントの見た目もここで決めている。絵の中に文字・ロゴ・吹き出しは入れない。
- 絵は 3:2 の JPEG で、Cloud Storage の `images/scenes/<モデルと説明文のハッシュ>.jpg` に保存する。保存済みの絵は作り直さないので、何度実行してもよい（`STYLE_PROMPT` やモデルを変えると、すべて描き直しになる）。
- 説明文と絵の対応を `content/images/scenes.yaml` に書き出すので、コミットする。`make seed` / `make seed-production` は、この対応表から `illustration.imagePath` を埋める。
- アプリはログインしたユーザーだけが `images/` を読める（`firebase/storage.rules`）。

### 費用（ハッカソン予算）

- 1 回の `make illustrate` で新しく頼む絵は最大 30 枚（`ARGS="--max-new N"` で減らせる）。上限に達した場面は「NO PICTURE」と表示し、次の実行で続きを描く。混雑（429）で断られた分は数えず、少し待ってから頼み直す。
- 最後に「新しく描いた枚数（newly generated）」と「課金されうるリクエスト数（billable image requests）」を表示する。
- `make speak` に件数の上限はない。実行前に、読み上げるセリフの数（lines.yaml にまだない分）を確かめる。
- 2026-11-10 に u1-l4（と既存の intro）のために生成した量: 絵 22 枚（`gemini-3.1-flash-lite-image`、課金されうるリクエスト 22 回）、音声 42 本（`gemini-2.5-flash-tts` 40 本＋ Gemini-TTS が一時的に失敗した 2 セリフの Chirp 3 HD 2 本。2 セリフは再実行で Gemini-TTS の声にした）。

## AI で問題の下書きを作る

ハルシネーション探し（Q2）の問題は、`make draft-hallucination` で Gemini に下書きを作らせられる。下書きは `content/drafts/` に保存され、人が事実を確かめてから `content/units/` に移したものだけが公開される。使い方と公開までの手順は [drafts/README.md](drafts/README.md)。

## 教材を変えるときの流れ

1. YAML を編集する
2. `make content-validate` で検証する（`make check-tools` と CI でも実行される）
3. `make seed` で Firestore Emulator に投入し、アプリで確認する。投入は何度実行してもよく、content にないドキュメントは削除される
