# Elixir / Phoenix × Kubernetes / AWS：現場参画・開発・SREキャッチアップメモ

> **目的**：12月からの現場で、既存システムの構造・信頼性・運用状況を素早く理解し、開発と障害対応で適切な判断をするための実務チェックリスト。
>
> **前提**：TaskLabでのハンズオン結果をもとにした汎用メモ。**参画先の構成（EKS使用有無、DB、非同期基盤、監視サービス、SLOなど）は未確認**。現場の事実と混同しないこと。
>
> **今回の優先順位**：初週は現状把握 → 2週目は重要なユーザーフローと監視の欠落確認 → 3週目以降に小さく改善。最初から監視基盤を全面刷新しない。

## 0. 最初に押さえる原則

1. **ユーザー影響が最優先**：PodがRunningでも、重要な機能が失敗・遅延していれば障害。
2. **復旧と処理成功は別**：SupervisorやKubernetesが再起動しても、途中の業務処理・データ整合性は保証されない。
3. **症状と原因を分ける**：HTTP 5xx・遅延は症状。DB接続待ち、CPU競合、外部API遅延などが原因候補。
4. **計測してから最適化する**：CPU・メモリの瞬間値だけでrequests/limits、Pool、Pod数を決めない。
5. **アラートは行動に結びつける**：緊急通知はユーザー影響・切迫した障害に重点を置き、調査用メトリクスと区別する。
6. **変更時の安全性を設計する**：リトライ・タイムアウト・冪等性・DB互換性・ロールバックを実装前に確認する。

---

## 1. 現場に入ったら最初に確認すること

### 1.1 システムと業務を把握する

- [ ] サービスの重要な業務フローを3つ程度把握する（例：登録、更新、外部連携）。「失敗すると誰が困るか」も確認。
- [ ] アーキテクチャ図、主要リポジトリ、サービス間通信、責務の境界を確認。
- [ ] Elixir/Phoenix、PostgreSQL、キャッシュ、メッセージキュー、外部APIの使用状況を確認。
- [ ] 実行基盤を確認（EKS / ECS / EC2 など）。開発・ステージング・本番の差分も確認。
- [ ] どこに**永続データ**と**インメモリ状態**があるかを把握。
- [ ] オーナー、障害時の連絡先、当番、過去のインシデント、よく起きる問題を確認。

**聞きたい質問**

- 「ユーザー影響が最も大きい機能と、その正常性を測る指標は何ですか？」
- 「障害時に最初に開くダッシュボードと、最初に確認するログはどれですか？」
- 「過去に再発している障害、手動で復旧している処理はありますか？」
- 「データの消失・二重実行・遅延で特に困る処理はどれですか？」

### 1.2 初日に確保したいアクセス・手順

- [ ] README、構成図、Runbook、権限申請、秘密情報管理の手順
- [ ] CI/CD、デプロイ履歴、ロールバック方法
- [ ] ログ・Metrics・Tracesの閲覧先
- [ ] DBのスキーマ・Migration・接続方法（原則、最小権限）
- [ ] 検証環境で安全に試せる範囲と、リソース作成・削除ルール

---

## 2. 監視の優先順位：ユーザー影響 → アプリ → インフラ

### 2.1 まずFour Golden Signals

| 観点           | 主な指標                             | どう使うか                                           |
| -------------- | ------------------------------------ | ---------------------------------------------------- |
| **Latency**    | API別 p50/p95/p99、タイムアウト      | 「遅い」を定量化。成功と失敗のレイテンシは分けて見る |
| **Traffic**    | RPS、同時接続、キュー流入数          | 負荷変化や異常な減少を知る                           |
| **Errors**     | 5xx率、処理失敗率、外部API失敗率     | **ユーザー影響を最優先**で検知する                   |
| **Saturation** | CPU、メモリ、DB Pool待ち、キュー滞留 | 原因特定・逼迫の予兆を見る                           |

**重要**：HTTP 200でも業務上の失敗があり得る。たとえば決済・データ連携・非同期ジョブでは、ビジネス成功率や処理完了遅延を別途計測する。

### 2.2 監視チェックリスト（まず現場に有無を確認）

| 対象          | 最初に見たいもの                                                                     | 検知したい問題・注意点                                   |
| ------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| HTTP/API      | 5xx率、p95/p99、RPS、タイムアウト                                                    | 重要APIの障害・性能劣化。4xxは仕様上正常なケースと分ける |
| 業務フロー    | 成功/失敗件数、完了までの時間、重複・欠損                                            | HTTPが正常でも機能が失敗していないか                     |
| Kubernetes    | Ready数、再起動数、CrashLoopBackOff、Pending、Node状態                               | Pod/Node異常、スケジューリング失敗                       |
| リソース      | CPU使用率、CPU throttling、メモリWorking Set、OOMKilled、requests/limits             | CPU競合・メモリ不足・過小/過大な予約                     |
| BEAM/OTP      | Supervisor再起動、異常終了、プロセス数、message queue長、scheduler使用率、メモリ内訳 | クラッシュループ、滞留、VMへの負荷                       |
| Ecto/DB       | クエリ時間、接続Pool待ち、タイムアウト、接続数、ロック、遅いSQL                      | DBがボトルネックか、アプリ側で待っているか               |
| 外部依存      | 成功率、時間、レート制限、Circuit Breaker状態                                        | 障害の伝播を防げるか                                     |
| ジョブ/キュー | 滞留件数・最古ジョブの経過時間、失敗/リトライ、デッドレター                          | 処理落ち、処理遅延、重複実行                             |
| リリース      | バージョン別エラー率、デプロイ時刻、Ready数                                          | 変更と不具合の関連を確認                                 |

### 2.3 Metrics / Logs / Traces の役割

- **Metrics**：異常に気付く。例：`POST /orders`の5xx率が悪化。
- **Traces**：どの区間で時間がかかったかを見る。例：Phoenix → Ecto → PostgreSQL。
- **Logs**：何が起きたかの詳細。例：request_id / trace_idと紐付く例外、外部APIのエラーコード。
- **業務イベント**：ユーザー操作が最後まで完了したか。技術指標だけで代用しない。

ログにはパスワード・Token・個人情報などを出さない。メトリクスのラベルにユーザーIDやリクエストIDなどの高カーディナリティ値を無制限に入れない。

### 2.4 アラート設計

- **緊急通知**：重要な業務の継続的失敗、エラーバジェットを急速に消費する5xx/遅延、サービス提供不能など。
- **営業時間内の調査**：再起動頻度上昇、メモリ増加傾向、遅いSQL、リトライ増加など。
- **ダッシュボードのみ**：一時的なCPU上昇など、ただちに対応が必要でない変動。

しきい値は固定値を当てはめず、トラフィック量・通常時の分布・SLO・継続時間・重大度から決める。**通知を見た人が何をするか分からないアラートは見直す。**

---

## 3. Elixir / OTPで開発・運用時に見るポイント

### 3.1 GenServer・Supervisor

- [ ] GenServerの状態は**揮発してもよいデータか**。再起動時に復元できるか。
- [ ] 一つのGenServerに要求が集中して直列処理のボトルネックにならないか。
- [ ] `GenServer.call`のタイムアウト、呼び出し元への失敗の伝播を理解しているか。
- [ ] `handle_call`/`handle_cast`が重い同期処理で塞がらないか。
- [ ] `Process.info(pid, :message_queue_len)`などでキューの滞留を調べられるか。
- [ ] Supervisorの階層、`strategy`、`max_restarts`/`max_seconds`、子のrestart設定を把握しているか。
- [ ] 再起動した回数・理由・失われた処理を監視できるか。

**注意**：Supervisorはプロセスの再起動を行うが、未完了ジョブの再試行やDB書き込みの整合性までは保証しない。

### 3.2 BEAMのメモリ・CPU

- **BEAM内部**：`:erlang.memory()`の`total`・`processes`・`binary`・`ets`など。
- **コンテナ全体**：`kubectl top pods`のWorking Set。BEAM以外のネイティブ領域、アロケータの保持領域などを含み、両者は一致しない。
- **CPU**：`kubectl top`の`m`はmillicores。`100m` = 0.1 CPU。CPUが増えてもBEAMの管理メモリが比例して増えるわけではない。
- **運用判断**：単発の数値ではなく、通常・ピーク・負荷終了後の推移と、OOM/レイテンシを合わせて見る。
- **注意**：大量のプロセス・メールボックス滞留、過大なバイナリ参照、ETS、NIFなどが問題になり得る。

### 3.3 複数Pod時に再確認

- [ ] インメモリ状態はPod間で共有されない前提になっているか。
- [ ] Phoenix PubSub / Channels / Presenceなどで分散をどう扱っているか。
- [ ] ジョブが複数Podで重複取得されても安全か。
- [ ] セッションや接続状態がPod再配置・ローリング更新に耐えられるか。

---

## 4. Kubernetes / AWSで確認すること

### 4.1 Probeと復旧責務を混同しない

| 機構                      | 主な役割                                 | 典型的な注意                                       |
| ------------------------- | ---------------------------------------- | -------------------------------------------------- |
| **Readiness Probe**       | Serviceの送信先に含めるか                | 共通DB障害で全PodがNotReadyになる設計が適切か検討  |
| **Liveness Probe**        | 復旧不能なコンテナの再起動               | DBや外部APIの瞬断で再起動を連鎖させない            |
| **Startup Probe**         | 起動中にLiveness/Readiness判定を急がない | Releaseの立ち上がりが遅い場合に検討                |
| **Supervisor**            | BEAM内の子プロセスの再起動               | 内部の状態消失・再起動ループを監視                 |
| **kubelet/restartPolicy** | 終了したコンテナの再起動                 | Liveness失敗以外でも再起動する                     |
| **Deployment/ReplicaSet** | 必要なPod数の維持                        | Pod削除時には新しいPodを作る。コンテナ再起動と区別 |

### 4.2 requests / limits の判断

- CPU **request**：配置判断とCPU競合時の配分に関係。CPU使用量の上限ではない。
- CPU **limit**：制限を超えるとthrottling。性能影響を評価して設定する。
- Memory **request**：配置とNodeメモリ圧迫時の扱いに関係。超過しても直ちにOOMではない。
- Memory **limit**：上限超過でOOM Killの可能性。ピーク実測と余裕を考える。
- **QoS**：BestEffort / Burstable / Guaranteedを理解する。GuaranteedでもOOMが起きない保証ではない。
- レプリカ数やNodeサイズを決める際は、**アプリだけでなくCoreDNS、CNI、監視エージェントなどの消費も考慮**。

### 4.3 AWS/EKSで現場に確認

- [ ] 実際にEKSか。他基盤なら該当部分だけ読み替える。
- [ ] Node Group/Fargate、インスタンス、AZ、オートスケーリング、Pod配置制約
- [ ] ALB/Ingress、内部公開/外部公開、Security Group、NetworkPolicy、VPC経路
- [ ] IRSA / EKS Pod IdentityなどのAWS権限とSecret管理方式
- [ ] ECR、イメージのスキャン、タグ固定・digest、ロールバック可能性
- [ ] RDS等のDB可用性・バックアップ・復旧手順（RPO/RTO）
- [ ] 監視基盤（CloudWatch、Prometheus/Grafana、OpenTelemetry等）とログ保存期間
- [ ] Node/Pod障害のRunbook、負荷増時のスケール方針

※ TaskLabでのEKSは**単一Node・学習用PostgreSQL Pod・port-forward**。これは本番の高可用性構成ではない。

---

## 5. 安全なバックエンド開発で確認すること

### 5.1 リトライ・冪等性・非同期処理

- [ ] API/ジョブ/外部Webhookは**重複実行され得る**前提か。
- [ ] 成功直後にレスポンスを返す前に落ちても、再送で二重処理されないか。
- [ ] 必要なら冪等キー、DB UNIQUE制約、トランザクション、処理状態を設ける。
- [ ] 再試行する条件を分類（タイムアウト/一時的5xxは候補、入力不正は原則不可）。
- [ ] 指数バックオフ・ジッター・最大回数・最終失敗時の扱いを設計する。
- [ ] DB更新と外部API呼び出しの間の失敗を想定する。必要ならOutboxや補償処理を検討。
- [ ] キュー/ジョブの滞留・重複・失敗を監視する。

### 5.2 DB / Ecto

- [ ] クエリ時間だけでなく**Pool checkout待ち**を区別できるか。
- [ ] N+1、Index、トランザクション競合、長いロック、タイムアウトを確認する。
- [ ] 複数PodへのスケールでDB接続数が増えても大丈夫か（Pool Size × Pod数）。
- [ ] 条件付きUPDATEや制約による競合対策を検討する。
- [ ] Migrationは一回限りのJobなどで実行し、アプリの起動と責務を分ける。

### 5.3 リリース・Migration

- [ ] Migrationの成功確認とアプリ更新の順序が決まっているか。
- [ ] Rolling Update中に新旧アプリが同じDBを利用しても互換性があるか。
- [ ] カラム追加 → アプリ切替 → 古いカラム削除（Expand/Contract）が必要か。
- [ ] デプロイ後に5xx・p95・業務成功率を監視し、戻す条件が定義されているか。
- [ ] 戻すのはアプリだけでよいか。DB変更は簡単に巻き戻せない可能性がある。
- [ ] SIGTERM時の終了猶予、既存HTTP/WebSocket接続、処理中ジョブの終了動作を確認する。

---

## 6. 障害発生時の切り分けメモ

> **順序**：ユーザー影響を確認 → 直近の変更を確認 → 依存先・アプリ・基盤を絞る → 復旧 → 再発防止。

| 症状                     | 最初に見るもの                                       | 主な仮説・次の確認                                |
| ------------------------ | ---------------------------------------------------- | ------------------------------------------------- |
| API 5xx増加              | エンドポイント別失敗率、trace、直近デプロイ          | アプリ例外、DB障害、外部API障害                   |
| APIが遅い                | p95/p99、DB時間/Pool待ち、CPU throttling             | 遅いSQL、Pool不足、外部依存、CPU競合              |
| Podが再起動              | `describe pod`のLast State/Events、`logs --previous` | OOMKilled、Liveness、メインプロセス終了を区別     |
| PodがPending             | `describe pod` Events                                | requests、Node不足、taint、affinity、PVC          |
| PodはRunningだが疎通不可 | Ready、Service/EndpointSlice、Ingress、アプリログ    | Probe、Service selector、アプリbind、ネットワーク |
| GenServerが頻繁に再起動  | Supervisor/クラッシュログ、message queue、依存先     | 例外、過負荷、外部依存失敗、状態復元              |
| DB待ちが増える           | Pool待ち、接続数、DB CPU/Locks、遅いSQL              | Pool不足かSQL/ロックかを分ける                    |
| ジョブが終わらない       | 最古ジョブの滞留時間、失敗・再試行数                 | Worker停止、依存先、毒メッセージ、重複            |
| リリース後に異常         | デプロイ差分、Migration、アラート                    | 互換性、設定差分、Secret、ロールバック判断        |

**利用できる場合のKubernetes初動コマンド**（対象クラスタ・Namespaceに注意）：

```bash
kubectl config current-context
kubectl get pods -n <namespace> -o wide
kubectl get deploy,svc -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --tail=200
kubectl logs <pod-name> -n <namespace> --previous --tail=200
kubectl top pods -n <namespace>
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
```

`<...>`はプレースホルダー。**本番で`delete`・`scale`・障害注入を勝手に実行しない。**

---

## 7. TaskLabハンズオンで確認できた事実（学習の根拠）

| 実験                      | 観測結果                                                    | 実務への持ち帰り                                                      |
| ------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------- |
| GenServerをkill           | PIDが変わりSupervisorが再起動、Podの再起動数は増えず        | BEAM内の復旧とKubernetes復旧は別層                                    |
| 短時間に連続kill          | OTP ApplicationとBEAMが終了し、コンテナRestart Countが1増加 | 再起動上限、Application終了、外側の復旧を理解。業務処理成功は別途確認 |
| DB Podを停止              | Readinessが失敗、Phoenix PodはRunningのままNotReady         | Readinessは通信先制御。共有依存を含める設計には注意                   |
| Liveness Pathを不正にする | kubeletがコンテナを再起動                                   | Probe設定ミス自体が障害を起こし得る                                   |
| CPU/メモリ計測            | アイドル約3m/156Mi、負荷中少なくとも454m/242Mi              | CPU request 100mを超えて利用できた。瞬間値でサイズ決定しない          |
| 負荷終了後                | CPUは約2mへ低下、メモリは約234Miで高止まり                  | GC・アロケータ・Working Setの違い。直ちにリークとは断定できない       |
| `:erlang.memory()`        | BEAM管理メモリ約99〜100MiB、Kubernetes計測は約234〜242MiB   | 計測対象が違うので単純比較しない                                      |
| Kubernetes Job            | `task-lab-migrate`がCompleted、`tasks`テーブル作成          | MigrationをDeploymentと切り離せる                                     |
| AWS ECR → EKS             | Image Push、Node Ready、Migration成功、API 200・空配列      | Docker/Kubernetesの知識をAWSでも適用できた                            |
| AWS後片付け               | EKS削除を実施                                               | **ECR等は別途残存確認**。課金リソースの棚卸しまでが作業               |

**今回試した学習用リソース設定**：CPU request `100m`、Memory request `256Mi`、Memory limit `512Mi`、CPU limitなし。これはTaskLabの暫定設定であり、現場にそのまま転用しない。

---

## 8. 参画後の30日プラン（業務優先で柔軟に変更）

| 時期      | 目的                                 | 成果物の例                                          |
| --------- | ------------------------------------ | --------------------------------------------------- |
| **1週目** | 業務と構成・運用手順を理解           | 重要フロー、依存先、監視先、リリース手順メモ        |
| **2週目** | 重要フローの失敗パターンと監視を確認 | 5xx/遅延/業務成功/DB/Podの監視カバレッジ表          |
| **3週目** | 変更を安全に出せるか確認             | 冪等性・リトライ・Migration・ロールバックのチェック |
| **4週目** | 小さく改善し、効果を検証             | ダッシュボード/アラート/テスト/Runbookの改善1件     |

**優先する小さな改善候補**：重要APIの5xx・p95を見える化／再起動の原因が追えるRunbook／DB Pool待ちの計測／ジョブの滞留検知／重要処理の冪等性テスト。

---

## 9. 現場キャッチアップ用メモ欄（埋めながら更新する）

| 項目                           | 現場で確認した内容 | 未確認/次のアクション |
| ------------------------------ | ------------------ | --------------------- |
| 重要なユーザーフロー・SLO      |                    |                       |
| サービス・リポジトリ構成       |                    |                       |
| 実行基盤とPod/Node構成         |                    |                       |
| DB/外部依存/非同期ジョブ       |                    |                       |
| Supervisor構成とインメモリ状態 |                    |                       |
| Dashboard / Logs / Traces      |                    |                       |
| 主要アラートと通知先           |                    |                       |
| CI/CD・Migration・ロールバック |                    |                       |
| 既知の障害・技術的負債         |                    |                       |
| 最初に改善したい一件           |                    |                       |

### 参画時に思い出す問い

> **「何が壊れたらユーザーが困るか？ それをどう検知し、どう切り分け、どう安全に復旧するか？」**

この問いを起点に、必要なメトリクス・ログ・トレース・設計・Runbookを考える。

---

## 参考資料（必要に応じて確認）

- Google SRE Book: https://sre.google/sre-book/monitoring-distributed-systems/
- Kubernetes Probes: https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/
- Kubernetes Resource Management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- Kubernetes Jobs: https://kubernetes.io/docs/concepts/workloads/controllers/job/
- Elixir GenServer: https://hexdocs.pm/elixir/GenServer.html
- Elixir Supervisor: https://hexdocs.pm/elixir/Supervisor.html
- Phoenix Telemetry: https://hexdocs.pm/phoenix/telemetry.html
- Amazon EKS Best Practices: https://aws.github.io/aws-eks-best-practices/
