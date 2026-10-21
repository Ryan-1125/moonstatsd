# 发布与验证概览

更新日期：2026-10-21。历史命令、失败与修复细节保留在 VALIDATION.md。

## 已实现

- 原生 StatsD / DogStatsD 编码、类型与字段校验、可测试概率采样。
- 按 UTF-8 字节限制的不可拆分消息和有界数据报打包。
- 官方 async 0.20.0 真实 UDP；单一发送任务、有界排队、定时刷新。
- flush 入队快照屏障、限时 close、本地计数与最近发送错误诊断。
- 显式拒绝负绝对 gauge；相对 gauge 仅在基础 StatsD 模式提供。

## 当前验证

| 项目 | 已有证据 |
|---|---|
| 本地 native | 20 组通过；包含持续生产竞争、标签快照及构造期配置预算 |
| 纯核心 wasm-gc | 6 组通过 |
| StatsD 0.9.0 | 实际 counter/gauge/timer/set 聚合与采样验证 |
| statsd_exporter 0.28.0 | 实际 counter/gauge/timer/histogram/distribution 和标签验证 |
| datadog-go 5.8.3 | 六种共同 wire 语义差分通过 |
| 独立消费 | 实际 ZIP 解压副本、独立应用编译与真实 UDP 通过 |
| Mooncakes 0.1.0 消费 | 从 registry 解析依赖，独立应用编码、打包与真实 DogStatsD UDP 收发通过 |
| Windows / Ubuntu CI | a547b5b 两个平台全流程成功，native 20/20、核心 wasm-gc 6/6 |
| 官方 DogStatsD Agent 7.60.0 | Ubuntu CI 真实通过：采样计数、gauge、timer、histogram、set 与标签 |

本轮通过的运行：[39542103570](https://github.com/Ryan-1125/moonstatsd/actions/runs/39542103570)。
官方二进制报告 7.60.0 / commit 799e298。其真实输出中 counter 为 rate=0.4、
interval=10（折算计数 4），gauge=7、timer.avg=250、histogram.avg=42、set=2。

## 发布

- Mooncakes 0.1.0 已发布：[`Ryan-1125/moonstatsd`](https://mooncakes.io/docs/Ryan-1125/moonstatsd)。
- 安装：`moon add Ryan-1125/moonstatsd`。
- 全新消费验证：`./tools/test-registry-consumer.ps1`，无本地源码或 workspace 覆盖。
- 公开 GitHub 仓库提供源码、示例、CI、许可证和可复现验证工具。

## 使用与兼容范围

- UDP 发送成功不保证采集器收到；flush 返回本机结果，不是 ACK。
- 只支持同一 async 事件循环的协作任务，不承诺 OS 线程安全。
- Agent 测试范围为 counter、非负 gauge、timer、histogram、set 和标签。
  Distribution 的 Agent sketches 输出不在该项断言范围内。
- 未做吞吐性能基准，未验证其他 CPU 架构或完整商业 Datadog 后端。

真实 Agent 的本地复现需要 Linux amd64 + Docker + Node 22 和当前 MoonBit SDK：

```sh
node tools/test-agent.mjs
```

它运行固定摘要的官方镜像，在内部 Docker 网络中把聚合输出送往有界 HTTP
sink。该 sink 不解析 StatsD 输入，不是替代接收器。无需真实 API key，日志和
断言数据写入 .local/evidence/agent，并尝试在 finally 中清理容器及临时网络。
