# MoonStatsD

MoonBit 原生 StatsD / DogStatsD 编码器与有界异步 UDP 客户端。当前为本地开发版 **0.1.0**，未发布到 Mooncakes，未创建远程仓库。
交接文档中的 API 是最初草案；实际公开接口以 `pkg.generated.mbti` 和 `client/pkg.generated.mbti` 为准。

## 支持范围

| 能力 | 基础 StatsD | DogStatsD | 已做的真实验证 |
|---|---|---|---|
| Counter / Timer（毫秒） | 是 | 是 | StatsD 0.9.0、statsd_exporter 0.28.0 |
| 非负绝对 Gauge | 是 | 是 | 两个接收器验证最终值 |
| GaugeDelta | 是 | 拒绝 | StatsD 0.9.0：10 加 -3 得到 7 |
| 负绝对 Gauge | 明确报错 | 明确报错 | 不把它误作负增量 |
| Set | 是 | 是 | StatsD 0.9.0 去重；DogStatsD wire 差分 |
| Histogram / Distribution | 拒绝 | 是 | statsd_exporter 0.28.0 |
| namespace、固定及调用级标签 | namespace；拒绝标签 | 是 | 采集器标签和参考客户端 wire |
| 概率采样 | Counter、Timer | 再加 Histogram、Distribution | 确定随机源测试；StatsD 采样放大 |

不实现 events、service checks、客户端聚合、重试、可靠交付、TCP、Unix socket、TLS 或来源识别。
仅实测 **Windows amd64 native** 网络功能；纯核心另在 wasm-gc 通过测试。Linux CI 已配置但尚未远程运行，不能据此声称 Linux 已验证。Datadog Agent 本身未运行，支持声明限于以上协议与接收器范围。

## 使用

模块当前从本地工作区或打包 ZIP 引用，不能把尚未发布的版本当作可用的 registry 依赖。`tools/test-consumer.ps1` 展示完整独立消费方式。
库项目依赖固定为 `moonbitlang/async@0.20.0`，native 目标。应用的 `moon.pkg` 导入：

```moonbit
import {
  "Ryan-1125/moonstatsd/client",
  "moonbitlang/async",
  "moonbitlang/async/socket",
}
pkgtype(kind: "executable")
```

```moonbit
async fn main {
  let address = @socket.Addr::parse("127.0.0.1:8125")
  @client.with_client(address, client => {
    ignore(client.record("requests", Counter(1.0), tags=["route:home"]))
    ignore(client.record("latency", Timer(12.5))) // 毫秒
    ignore(client.record("queue", Gauge(10.0)))
    ignore(client.record("queue", Gauge(7.0)))
    let report = client.flush()
    println("local submitted=\{report.submitted}, send errors=\{report.send_errors}")
    ignore(client.close())
  }, mode=DogStatsD, prefix="service.", fixed_tags=["env:dev"])
}
```

`record(name, Metric, tags~, rate~)` 同时处理所有指标类型，返回 `Enqueued` 或 `SampledOut`；未通过校验、关闭、队列满会抛错。无需商业账号的三场景示例在 `cmd/main`：请求完成、后台任务结束、工作进程 gauge 更新。避免高基数标签，例如用户 ID、完整 URL 和异常文本。

纯核心 `encode(...) -> Message` 只校验和编码采样声明，不执行随机抽样；`sampled(rate, draw)` 独立给出选择结果。客户端对可采样类型实际抽样，默认系统熵初始化 ChaCha8；熵不可用报错，可通过 `random=() => ...` 注入均匀 `[0,1)` 随机源。本库 rate 取 `(0,1]`，不编码零采样率；Gauge / Set 的 rate 必须为 1。无效输入即使原本会被抽样丢弃仍报错。

数值为有限 IEEE-754 Double；不保证超过 2^53 的整数精度。使用 SDK 最短数值字符串（可能为科学计数法）；Timer 单位为毫秒。负绝对 gauge 报错，因为基础协议需要先清零再发负增量，网络丢包和其他生产者会破坏这种两步更新的含义。相对 gauge 仅提供给基础 StatsD 模式，不将接收器的扩展语义当作 DogStatsD 的通用承诺。负零 gauge 归一为零，负零 delta 编码为 `+0`。

prefix 原样拼接，请自行包含末尾的 `.`。DogStatsD 的完整名称只允许 ASCII 字母、数字、下划线和点；基础 StatsD 允许其他不含注入字符的 UTF-8 名称。固定标签先于调用级标签；按第一个 `:` 前的 key 检查重复，重复键直接报错。名称、prefix、Set、标签分别拒绝相应分隔符和 ASCII 控制字符；不静默替换。最终长度按 UTF-8 字节计算。

## 缓冲与生命周期

默认数据报 512 字节，来自 StatsD 固定版本文档的保守网络建议；应根据接收器限制和路径 MTU 配置（1..65507）。上限不代表安全 MTU。`pack` 只以换行合并完整 Message，拒绝单条超限；另以 `max_total_bytes` 限制输入总字节数。

`with_client` 使用结构化任务作用域和唯一发送任务。仅支持同一 async 事件循环中的协作任务共享，不承诺 OS 线程安全。默认容量 256 条、刷新间隔 100ms、发送/flush/close 时限 1000ms；容量包含发送中的指标。配置限制容量最多 65536，容量乘数据报上限不超过 16MiB。这是 wire 缓冲预算，进程还会使用对象、临时编码和数据报内存。

| 操作或情况 | 确定行为 |
|---|---|
| 队列满 | 拒绝最新调用并增加 queue_full；不覆盖旧指标 |
| 定时刷新 / flush | 单一任务发送；flush 是调用前入队项的完成屏障，后续生产者不延长此屏障 |
| 本机发送错误或发送超时 | 不重试；增加 send_errors（数据报次数）和 dropped（指标数），继续处理后续项 |
| flush 返回 | 返回累计 Stats，必须检查 dropped/send_errors；不是采集器 ACK |
| flush 超时或调用者取消 | 只停止该等待者，发送任务继续 |
| close | 立即拒绝新指标，限时排空；重复调用共享关闭结果 |
| close 超时或调用者取消 | 取消唯一发送任务，剩余项计入 dropped；其他关闭等待者也观察这次中止 |
| callback 成功退出 | 自动 close；失败或作用域取消则中止并丢弃未完成项 |
| 作用域退出 | 等待子任务清理并关闭 socket；逃逸的句柄也已关闭 |

close 的时限限制排空等待；取消之后的运行时资源清理可能延后完成。超时调用返回后可读取 stats，作用域退出保证清理完成。进程强制终止时无法保证排空。

Stats 中 enqueued/submitted/dropped/pending 是指标数；sampled_out 是抽样排除数，queue_full 是满队列拒绝数，send_errors 是失败数据报次数。`submitted` 只表示 SDK 的本机 socket 发送调用返回成功。UDP 可能丢失、重复、乱序；取消期间的数据报也可能已经发出，不能把本地 dropped 当作“采集器绝未收到”。

## 验证命令

本次实测 SDK：moon 0.1.20261020 / moonc v0.10.16+b1a0e846e，Node 22.22.1，Go 1.23.2。

```powershell
moon update
moon fmt --check
moon info --target native
moon check --target native --deny-warn
moon build --target native --deny-warn
moon test --target native --deny-warn
moon test --target wasm-gc --package Ryan-1125/moonstatsd
./tools/install-collectors.ps1
node tools/test-interop.mjs
node tools/test-reference.mjs
./tools/test-consumer.ps1
moon package --list
```

Go 用于参考客户端差分；不属于库运行依赖。可通过 `GO_EXE` 指向已有 Go。下载受限时可在当前进程设置 GOPROXY；不要改全局配置。interop 使用本机端口 19102、19125、19126、19127，退出时停止自行启动的接收器。采集器归档版本和 SHA256 在安装脚本固定。仅适配该脚本的 Windows/Linux amd64 资产；这不等于库已经完成跨平台测试。

`test-reference.mjs` 与 datadog-go v5.8.3 比较共同支持的六种 wire，按数值语义归一 Timer 小数位；不拿格式差异冒充协议错误。`test-consumer.ps1` 从实际 ZIP 解压独立副本建立独立应用，不依赖工作树源码覆盖发布内容。证据输出写入不提交、不打包的 `.local/evidence`；重要实测摘录见 [docs/VALIDATION.md](docs/VALIDATION.md)。

CI 覆盖格式、接口差异、check/build/test、真实 UDP、两个采集器、参考客户端和独立消费；目前只交付工作流文件，没有远程 CI 结果。安装脚本使用官方当前 SDK，并记录版本，后续升级需重新验证。未运行性能基准，不作吞吐或生态唯一性声明。

查重、固定协议资料和许可证见 [docs/SOURCES.md](docs/SOURCES.md) 与 [THIRD_PARTY.md](THIRD_PARTY.md)。项目使用 Apache-2.0。
