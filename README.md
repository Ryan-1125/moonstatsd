# MoonStatsD

[![Verify](https://github.com/Ryan-1125/moonstatsd/actions/workflows/ci.yml/badge.svg)](https://github.com/Ryan-1125/moonstatsd/actions/workflows/ci.yml)
[![Mooncakes](https://img.shields.io/badge/Mooncakes-0.1.0-blue)](https://mooncakes.io/docs/Ryan-1125/moonstatsd)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**MoonBit 原生 StatsD / DogStatsD 协议核心与异步 UDP 指标上报客户端。**

为 Web 服务、后台任务和工作进程上报请求数量、响应耗时、任务结果及队列状态。MoonStatsD 提供类型化指标、概率采样、标签校验、按字节打包，以及具有明确资源和生命周期边界的异步客户端，可接入已有 StatsD、DogStatsD 和 Prometheus statsd_exporter 采集链路。

## 安装

```sh
moon add Ryan-1125/moonstatsd
```

当前发布版本为 **0.1.0**，使用 Apache-2.0 许可证。异步 UDP 客户端使用 **native** 目标，依赖 `moonbitlang/async@0.20.0`；纯协议核心可独立使用，并通过 native 和 wasm-gc 测试。

[Mooncakes 包与文档](https://mooncakes.io/docs/Ryan-1125/moonstatsd) · [版本记录](CHANGELOG.md) · [验证结果](docs/STATUS.md)

## 快速开始

应用直接使用异步运行时时，显式添加依赖：

```sh
moon add moonbitlang/async@0.20.0
```

在可执行包的 `moon.pkg` 中导入：

```moonbit
import {
  "Ryan-1125/moonstatsd/client",
  "moonbitlang/async",
  "moonbitlang/async/socket",
}
pkgtype(kind: "executable")
```

向本机 `8125` 端口的 DogStatsD 采集器发送指标：

```moonbit
///|
async fn main {
  let address = @socket.Addr::parse("127.0.0.1:8125")
  @client.with_client(address, client => {
    ignore(client.record("requests", Counter(1.0), tags=["route:home"]))
    ignore(client.record("latency", Timer(12.5))) // 毫秒
    ignore(client.record("queue", Gauge(7.0)))
    let report = client.flush()
    println("local submitted=\{report.submitted}, send errors=\{report.send_errors}")
  }, mode=DogStatsD, prefix="service.", fixed_tags=["env:dev"])
}
```

```sh
moon run . --target native
```

`with_client` 在回调正常结束时自动关闭并排空缓冲。`record` 返回 `Enqueued` 或 `SampledOut`，非法输入、队列满和关闭后的写入会抛错。`flush` 返回本地累计统计，应用可检查 `send_errors` 和 `dropped`。UDP 无接收确认；本机发送成功不代表采集器已收到。

仓库中的 [`cmd/main`](cmd/main/main.mbt) 包含请求、后台任务和工作进程三种使用场景。

## 纯协议编码

编码和打包不需要 UDP 套接字。可执行包导入根包：

```moonbit
import {
  "Ryan-1125/moonstatsd" @statsd,
}
pkgtype(kind: "executable")
```

```moonbit
///|
fn main raise {
  let message = @statsd.encode("requests", Counter(1.0))
  assert_eq(message.bytes(), b"requests:1|c")
  let datagrams = @statsd.pack([message], max_bytes=512)
  assert_eq(datagrams.length(), 1)
}
```

`encode` 校验并生成不可拆分的 `Message`；`pack` 按换行合并完整消息，遵守单数据报及总输入字节预算。协议层只编码采样声明，实际概率抽样由客户端执行，也可通过 `sampled(rate, draw)` 独立使用。

## 指标与协议支持

| 指标或能力 | StatsD | DogStatsD |
| --- | --- | --- |
| `Counter`、`Timer`（毫秒）、`Set` | 支持 | 支持 |
| `Gauge`（非负绝对值） | 支持 | 支持 |
| `GaugeDelta`（相对变化） | 支持 | 显式拒绝 |
| `Histogram`、`Distribution` | 显式拒绝 | 支持 |
| 指标名前缀 `prefix` | 支持 | 支持 |
| 固定标签与调用级标签 | 显式拒绝 | 支持 |
| 概率采样 | Counter、Timer | Counter、Timer、Histogram、Distribution |

- **明确的 gauge 语义：**负绝对值会报错，避免被解释成相对减少。基础 StatsD 的相对变化使用 `GaugeDelta`；负零 gauge 归一为零。
- **严格字段校验：**拒绝字段注入、非法控制字符、重复标签键、非有限数值及非法采样率。完整 DogStatsD 名称限定 ASCII 字母、数字、下划线和点。
- **可测试采样：**采样率取 `(0, 1]`，Gauge 与 Set 必须为 1。默认使用系统熵初始化的 ChaCha8，支持注入随机源。
- **UTF-8 字节预算：**默认数据报上限 512 字节，支持配置为 `1..65507`；应结合采集器限制与路径 MTU 选择。
- **名称与数值约定：**`prefix` 原样拼接，请自行包含末尾的 `.`；数值使用有限 IEEE-754 Double。避免用户 ID、完整 URL 等高基数标签。

## 有界缓冲与生命周期

默认容量 **256 条**、刷新间隔 **100 ms**、发送及 flush/close 时限 **1000 ms**。单一发送任务管理 UDP 套接字，容量包括发送中的记录。配置限制容量最多 65536 条，容量乘数据报上限不超过 16 MiB 的 wire 缓冲预算。

| 操作 | 行为 |
| --- | --- |
| `record` | 校验、概率采样、入队；队列满时拒绝新记录 |
| 定时刷新 | 按字节预算合并完整指标并发送 |
| `flush` | 等待调用前已入队记录完成；后续生产者不延长屏障 |
| flush 超时或取消 | 结束当前等待，发送任务继续 |
| `close` | 立即拒绝新记录，限时排空；可重复调用 |
| close 超时或取消 | 中止发送任务，将剩余记录计入丢弃 |
| 回调正常退出 | 自动关闭；作用域退出时完成资源清理 |
| 回调失败或作用域取消 | 中止发送并清理资源 |

`stats()` 提供入队、采样排除、队列满、提交、发送错误、丢弃、待处理及关闭状态；`last_send_error` 保留最近一次本机发送错误。

客户端适用于同一 async 事件循环内的协作任务。UDP 可能丢失、重复和乱序，本库采用无重试发送；`submitted` 与 `flush` 是本机处理结果，不是采集器 ACK。当前 API 聚焦指标数据报编码与 UDP 上报，events、service checks 及其他传输方式不属于本版本范围。

## 真实互操作与质量验证

| 验证对象 | 覆盖内容 |
| --- | --- |
| native：20 项通过 | 协议、真实 UDP、有界队列、定时刷新、错误、取消、flush/close 竞争 |
| 纯核心 wasm-gc：6 项通过 | 编码、校验、采样和打包 |
| StatsD 0.9.0 | counter 采样放大、gauge 相对变化、timer、set 去重 |
| statsd_exporter 0.28.0 | counter、gauge、timer、histogram、distribution 与标签 |
| 官方 DogStatsD Agent 7.60.0 | counter、非负 gauge、timer、histogram、set 与标签的真实聚合输出 |
| datadog-go 5.8.3 | 六种共同指标的 wire 语义差分 |
| 独立 ZIP 消费与包审计 | 解压包独立编译、真实 UDP、包内资源检查 |
| Mooncakes 0.1.0 独立消费 | registry 依赖解析、编码与打包、真实 DogStatsD UDP 收发 |
| Windows / Ubuntu CI | 构建、测试、采集器互操作与独立消费 |

Agent 验证使用固定摘要的官方 Linux amd64 镜像；distribution 的覆盖来自 exporter 与 wire 差分。平台与兼容性声明以实测范围为准；本项目不作吞吐性能或商业 Datadog 后端兼容性保证。

```powershell
moon info --target native
moon fmt --check
moon test --target native
moon test --target wasm-gc --package Ryan-1125/moonstatsd
./tools/install-collectors.ps1
node tools/test-interop.mjs
node tools/test-reference.mjs
./tools/test-consumer.ps1
./tools/test-registry-consumer.ps1
./tools/audit-package.ps1
```

官方 Agent 复现环境为 Linux amd64、Docker、Node 22 与 MoonBit SDK：

```sh
node tools/test-agent.mjs
```

## 文档与许可证

- [使用细节与生命周期约定](docs/USAGE.md)
- [发布与验证概览](docs/STATUS.md)
- [实测命令与结果记录](docs/VALIDATION.md)
- [协议来源与生态调研](docs/SOURCES.md)
- [纯核心 API](pkg.generated.mbti) / [异步客户端 API](client/pkg.generated.mbti)
- [第三方参考与许可证](THIRD_PARTY.md)

MoonStatsD 是依据公开协议重新编写的 MoonBit 原生实现。参考客户端与采集器用于行为对照和测试，不是库的运行时依赖。项目使用 [Apache License 2.0](LICENSE)。
