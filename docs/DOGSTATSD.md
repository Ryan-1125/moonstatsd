# DogStatsD 协议与聚合 API

0.3.0 使用已实测 SDK moon 0.1.20261119 / moonc v0.10.22+124d61d05，依赖固定为 moonbitlang/async 0.22.10。旧版 async 0.20.0 与该 SDK 的 trait 方法规则不兼容，不能仅更新编译器而保留旧依赖。

## 事件与服务检查

纯协议入口为 `encode_event`、`encode_check`；异步入口为 `Client::event`、`Client::service_check`，Scope 提供同样方法。仅 DogStatsD 模式接受这些消息，沿用有界队列、定时发送、flush/close 屏障和本地错误通知。

事件支持 title、text、Unix 秒时间戳、hostname、aggregation_key、source_type、优先级 Normal/Low、Info/ErrorAlert/WarningAlert/Success 及标签。标题与正文长度按转义后的 UTF-8 字节计算；换行转成字面量 `\n`，长度前缀允许正文安全包含 `|`。字段中的 CR、NUL 和其他控制字符会报错。

服务检查提供 Ok、Warning、Critical、Unknown 四种状态，支持时间戳、hostname、标签及消息。消息始终置于最后，换行和 `m:` 按参考客户端规则转义；不允许通过分隔符注入新的字段。

固定标签先于调用标签，重复键拒绝；事件标题不追加 metric prefix，服务检查名称追加 prefix。Scope 对事件继承标签，对服务检查继承前缀和标签。时间戳单位是秒，Timer 的单位仍是毫秒。

## v1.1 多值打包

`encode_values(name, metrics, ...)` 与 `Client/Scope::record_values` 支持同一名称、类型、标签和采样率的数值观测，编码为 `name:v1:v2|type`。Counter、Gauge、Timer、Histogram、Distribution 支持此格式；Set、GaugeDelta、空数组、混合类型和超限消息会报错。该格式要求 Agent >=7.25.0，或 6.25.0 至 6.x。

客户端一次选择整个多值消息是否发送，采样率应用于其中每个值；这保留每个值的边际采样概率，但样本之间相关。验证在抽样前进行。不自动把超长显式 record_values 拆成部分入队；超限直接报错，避免调用方误以为整批成功。

## 有界聚合窗口

通过 `AggregateBuffer::new(capacity~, max_bytes~)` 创建窗口，调用 `record` 累积指标，再通过 `client.submit_aggregate(buffer)` 原子提交整个窗口；随后使用普通 `flush` 等待发送。也可 `messages()` 取得编码快照、`clear()` 显式丢弃窗口。

| 类型 | 窗口行为 |
| --- | --- |
| Counter | 同身份值相加；非有限和或超限结果拒绝，原值保留 |
| Gauge | 保留最后一个绝对值 |
| Set | 按成员去重 |
| Timer / Histogram / Distribution | 保留全部观测，不求平均、不降采样；相邻同身份观测自动按字节预算进行多值打包 |

身份包含名称、指标类型、排序后的标签；标签顺序不同仍归入同一逻辑指标，避免 gauge 的最后值被重新排序破坏。原始标签数组不会被修改。Set 不进行多值打包。窗口不接受采样参数，所有记录完整进入聚合；需要概率采样时使用普通客户端 record/record_values。

窗口容量计储存条目；重复 counter/gauge/set 不增加条目，分布类每次观测均计入容量。容量最大 65536，capacity × max_bytes 不超过 16 MiB wire 预算；对象、键和临时编码另有开销。满窗口拒绝新条目，调用方选择提交或清空，不会静默驱逐旧指标。

`submit_aggregate` 先生成完整快照、应用客户端固定前缀和标签并检查队列余量，全部可入队才清空窗口。编码失败、QueueFull、Closed 均保留窗口；窗口输出永久超过客户端容量时明确报 InvalidConfig；不会出现半个窗口已入队、重试又重复发送的情况。成功提交后，发送失败和 UDP 丢包仍可能发生，不能自动重试已提交窗口。

窗口采用显式提交，不隐式创建后台任务，也不把未提交记录计入客户端 pending。请在应用定时器或每个业务窗口结束时调用 submit_aggregate；关闭客户端只排空已经提交的消息。该生命周期设计使取消或重试责任明确。

## 统计口径与兼容范围

客户端 enqueued/submitted/dropped/pending 以编码消息为单位：事件、服务检查和多值消息各计一条；聚合窗口按提交后的消息数统计，而非原始业务调用次数。现有 SendFailure.metrics 字段沿用同一口径。send_errors 仍按失败数据报计数。

支持 StatsD 基础指标和上述 DogStatsD 协议。Origin detection、container/cardinality 等后续扩展字段及商业 Datadog 后端不在本次兼容性声明中。UDP 仍无可靠送达保证。

协议依据：[官方数据报文档](https://docs.datadoghq.com/extend/dogstatsd/datagram_shell.md)（2026-11-24 读取）；转义与可选字段顺序另对照固定 `datadog-go v5.8.3` 的 format.go、event.go、service_check.go（MIT）。新增代码为独立实现，没有复制上游实现。
