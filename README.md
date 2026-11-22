# TaskLab — Elixir / Phoenix / OTP / Kubernetes 学習プロジェクト

## 1. プロジェクト概要

Elixir / Phoenix / PostgreSQLを使ったタスク管理APIを実装し、OTPによるプロセス監視・障害復旧と、Kubernetesによるコンテナ監視・復旧の違いを学習する。

### 学習目標

- Elixirの言語仕様・並行処理モデルを理解する
- Phoenix / EctoによるAPI開発を習得する
- OTPのGenServer・Supervisor・Applicationを理解する
- 障害検知と復旧の責務を整理する
- Liveness / Readiness / Startup Probeを設計する
- Docker / Kubernetes上で障害を再現する

## 2. 技術スタックと用語集

| 技術・用語  | 概要                                                  | 主な役割                                           |
| ----------- | ----------------------------------------------------- | -------------------------------------------------- |
| Erlang      | 並行処理・分散処理・耐障害性を重視した言語            | BEAM・OTPの基盤                                    |
| BEAM        | Erlangの仮想マシン                                    | プロセス実行、スケジューリング、GC、メッセージ通信 |
| Elixir      | BEAM上で動作する関数型言語                            | アプリケーションの実装                             |
| OTP         | Open Telecom Platform。Erlangのライブラリ群・設計原則 | プロセス管理、監視、障害復旧                       |
| GenServer   | OTPのサーバープロセス実装パターン                     | 状態保持、同期・非同期メッセージ処理               |
| Supervisor  | OTPの監視プロセス                                     | 子プロセスの起動・再起動・終了管理                 |
| Application | OTPアプリケーションの起動・終了単位                   | Supervisor Treeなどのライフサイクル管理            |
| Phoenix     | Elixir製Webフレームワーク                             | Router、Controller、HTTP処理                       |
| Plug        | ElixirのWebリクエスト処理の仕組み                     | Middlewareに相当する処理                           |
| Ecto        | DB操作・データ検証ライブラリ                          | Schema、Changeset、Query、Repo                     |
| Mix         | Elixirのビルド・プロジェクト管理ツール                | 依存管理、コンパイル、テスト                       |
| ExUnit      | Elixirのテストフレームワーク                          | 単体・統合テスト                                   |

### BEAM・Elixir・OTPの関係

- **BEAM**：コードを実行するVM
- **Elixir**：BEAM上で動作するプログラミング言語
- **OTP**：BEAM上のプロセスを管理・監視・復旧する仕組み
- **Phoenix**：ElixirとOTPを利用するWebフレームワーク

OTPは単なる監視ツールではなく、アプリケーションを耐障害性のある構成で設計・実装するための基盤である。

## 3. OTPの重要な仕組み

### 3.1 BEAMプロセス

BEAMプロセスはOSプロセスとは異なる軽量な実行単位。

- 各プロセスが独立した状態を持つ
- メッセージパッシングで通信する
- 個別のプロセスがクラッシュしても、他のプロセスに直接影響しにくい
- スケジューリングはBEAMが管理する

Goのgoroutineと似た並行処理の用途に使えるが、メモリ共有や障害分離の仕組みが異なる。

### 3.2 GenServer

GenServerは、OTPが提供する汎用的なサーバープロセスの実装パターン。

主要な関数：

| 関数               | 用途                 |
| ------------------ | -------------------- |
| `start_link/1`     | プロセス起動         |
| `init/1`           | 初期状態設定         |
| `GenServer.call/2` | 同期メッセージ送信   |
| `GenServer.cast/2` | 非同期メッセージ送信 |
| `handle_call/3`    | 同期メッセージ処理   |
| `handle_cast/2`    | 非同期メッセージ処理 |

注意点：

- 単一のGenServerは受信メッセージを順次処理する
- 処理集中によるボトルネックに注意する
- メモリ上の状態は、プロセス再起動で基本的に失われる
- 永続化が必要な業務データはPostgreSQLなどで管理する

### 3.3 Supervisor

Supervisorは子プロセスのライフサイクルを管理するOTPプロセス。

主な再起動戦略：

| 戦略            | 挙動                                           |
| --------------- | ---------------------------------------------- |
| `:one_for_one`  | 障害が発生した子だけ再起動                     |
| `:one_for_all`  | 全ての子を再起動                               |
| `:rest_for_one` | 障害が発生した子と、その後に起動した子を再起動 |

Supervisor自身も別のSupervisorによって監視できる。

再起動回数が設定された上限を超えると、Supervisor自身が終了する場合がある。

**重要：Supervisorはプロセスを再起動できるが、失われたメモリ上のデータを自動復元するわけではない。**

### 3.4 Application

OTP Applicationは、関連するプロセスや設定をまとめた起動・停止の単位。

Phoenixアプリでは、`TaskLab.Application`がルートSupervisorを起動する。

概念的な監視ツリー：

```text
OTP Application Controller
  └── TaskLab.Supervisor
       ├── TaskLab.Repo
       ├── Phoenix.PubSub
       ├── TaskLabWeb.Endpoint
       └── TaskLab.TaskServer
```

実際の構成は`lib/task_lab/application.ex`の`children`で確認する。

## 4. OTPとKubernetesの責務分担

### 4.1 監視対象の階層

```text
Kubernetes
  └── Pod / Container
       └── BEAM VM
            └── OTP Application
                 └── Supervisor
                      ├── GenServer
                      └── その他のWorker
```

障害の発生場所によって、復旧を担当する仕組みが異なる。

| 障害                           | 主な復旧担当                             |
| ------------------------------ | ---------------------------------------- |
| GenServerの単発クラッシュ      | OTP Supervisor                           |
| 子プロセスの繰り返すクラッシュ | Supervisorの再起動制限・上位監視         |
| ルートSupervisorの停止         | OTP Applicationのライフサイクル管理      |
| BEAM VMの異常終了              | コンテナランタイム・Kubernetes           |
| BEAM VMのハング                | Kubernetes Liveness Probe                |
| DBの一時的な接続障害           | アプリ側の再接続・リトライ               |
| Podがリクエスト処理不能        | Kubernetes Readiness Probeによる転送制御 |

監視と復旧は必ずしも1対1ではない。

特に、OTPで復旧できる一時的な障害を理由にPod全体を再起動すると、正常なプロセスまで巻き込んでしまう。

## 5. Kubernetesのヘルスチェック設計

### 5.1 Liveness Probe

**目的：コンテナを再起動する必要があるか判断する。**

例：

- アプリケーションが応答不能になった
- 回復不能な内部状態になった
- BEAMがハングしている

一時的なDB障害や、Supervisorが正常に復旧したGenServerのクラッシュを、直ちにLiveness失敗とするべきではない。

Liveness失敗が設定回数に達すると、Kubernetesは対象コンテナを再起動する。

### 5.2 Readiness Probe

**目的：現在のPodにトラフィックを送ってよいか判断する。**

例：

- 必須機能が利用可能か
- アプリケーションがリクエストを処理する準備ができているか
- サービスの必須依存先が利用可能か

Readiness失敗時、Podは通常稼働を続けるが、Serviceの転送先から除外される。

DBをReadinessに含めるかは要件次第。共有DBの全面障害で全PodがUnreadyになると、サービス全体への転送が止まる可能性があるため、障害の性質と復旧戦略を考慮する。

### 5.3 Startup Probe

**目的：起動処理が完了したか判断する。**

初期化に時間がかかるアプリケーションで利用する。

Startup Probeが成功するまでLiveness / Readiness Probeの実行を抑制できる。

## 6. 障害シナリオ別の監視方針

以下は本プロジェクトで検証する初期方針。最終的な判定は業務要件や依存関係に応じて調整する。

| 障害シナリオ                                    | Liveness | Readiness | アラート     | 主な対応                    |
| ----------------------------------------------- | -------- | --------- | ------------ | --------------------------- |
| GenServerが1回クラッシュし復旧                  | 成功     | 原則成功  | 通常不要     | Supervisorが復旧            |
| GenServerが頻繁にクラッシュするが機能提供は可能 | 成功     | 成功      | 必要         | 再起動頻度・例外を調査      |
| 必須GenServerが停止し機能提供不能               | 状況次第 | 失敗      | 必要         | 上位監視・復旧判断          |
| ルートSupervisorが停止しアプリ応答不能          | 失敗     | 失敗      | 必要         | OTP終了処理・コンテナ再起動 |
| BEAM VMがハング                                 | 失敗     | 失敗      | 必要         | コンテナ再起動              |
| DB接続が一時的に失敗                            | 成功     | 要件次第  | 継続時に必要 | 再接続・リトライ            |
| HTTP APIは200だがWorkerが繰り返しクラッシュ     | 成功     | 機能次第  | 必要         | メトリクス・ログ調査        |

※ 「成功」はProbeが応答可能な場合の想定。「失敗」はタイムアウトや異常レスポンスを含む。Probe自体が実行されない状況では、設定された閾値やタイミングに従って状態が判定される。

### 重要な設計原則

1. **Livenessは再起動の判断**に使う。
2. **Readinessはトラフィックの制御**に使う。
3. **監視メトリクスとアラートは異常の早期発見**に使う。
4. OTPが復旧できる異常でPodを不用意に再起動しない。
5. HTTP 200だけを根拠にサービス全体が正常だと判断しない。
6. 再起動によって復旧できない障害は、再起動を繰り返しても解決しない。

## 7. 監視すべきメトリクス

| レイヤー   | 監視対象                                     | 目的                |
| ---------- | -------------------------------------------- | ------------------- |
| HTTP       | リクエスト数、エラー率、レイテンシ           | API品質の監視       |
| OTP        | プロセス異常終了数、Supervisorの再起動頻度   | 内部障害の検出      |
| BEAM       | メモリ使用量、プロセス数、メッセージキュー長 | VM負荷・滞留の検出  |
| DB         | 接続エラー、クエリ時間、接続プールの状態     | DB依存処理の監視    |
| Kubernetes | Pod再起動数、Ready状態、OOMKilled            | コンテナ・Podの監視 |

監視メトリクスとアラートの閾値は、実際のトラフィックや正常時の挙動を測定して決定する。

## 8. TaskLabの実装状況

### 実装・動作確認済み

- Phoenixによるタスク管理API
- PostgreSQLによる永続化
- Ecto Schema / Changesetによる入力検証
- Tasks Contextによる業務処理の分離
- 条件付きUPDATEによる完了処理の競合制御
- Controllerテスト
- GitHub Actionsによるコンパイル・フォーマット・テストのCI

### Phase 2：OTP・障害検知

- [ ] TaskServerをApplicationの監視ツリーに組み込む
- [ ] GenServerを強制終了し、自動再起動を確認する
- [ ] 再起動後のメモリ状態とDBデータを比較する
- [ ] `/health/live` を実装する
- [ ] `/health/ready` を実装する
- [ ] 障害時のHTTPステータスを検証する
- [ ] プロセス再起動頻度の監視方法を調べる

### Phase 3：Docker / Kubernetes

- [ ] Phoenixアプリをコンテナ化する
- [ ] ローカルKubernetesにデプロイする
- [ ] Liveness / Readiness / Startup Probeを設定する
- [ ] GenServer障害とコンテナ障害の違いを検証する
- [ ] Pod再起動とデータ永続化を確認する

### Phase 4：AWS EKS

- [ ] ECRへコンテナイメージを登録する
- [ ] EKSへデプロイする
- [ ] Podの障害復旧を検証する
- [ ] ログ・メトリクス・アラートを確認する

## 9. 参考資料

- Elixir： https://elixir-lang.org/
- Erlang/OTP Design Principles： https://www.erlang.org/docs/27/system/design_principles.html
- Phoenix： https://www.phoenixframework.org/
- Ecto： https://hexdocs.pm/ecto/
- Kubernetes Probes： https://kubernetes.io/docs/concepts/workloads/pods/probes/
