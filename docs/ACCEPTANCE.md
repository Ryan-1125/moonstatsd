# 最终验收导航

MoonStatsD 的验收以可安装的 MoonBit 库、实际协议行为和可复现证据为主。当前公开版本为 0.3.0，申报方向覆盖 Metrics、Events、Service Checks、多值打包及有界聚合。

## 评估维度与入口

| 维度 | 可检查产物 | 验收方式 |
| --- | --- | --- |
| 完成度 | 根包与 client API、Scope、Stopwatch、AggregateBuffer | 安装后执行独立应用和真实 UDP 接收断言 |
| 协议正确性 | Events/Checks 长度及转义、多值、聚合语义 | 单元断言、固定 datadog-go 差分、官方 Agent 转发结果 |
| 代码质量 | 类型化接口、字节预算、有界队列、取消和关闭行为 | deny-warn 构建、回归测试、生成接口一致性检查 |
| 开源合规 | LICENSE、THIRD_PARTY、固定参考版本、发布白名单 | 核对归属，审计真实 ZIP 的全部文件 |
| MoonBit 生态复用 | Mooncakes 发布、纯协议/native 分层、可运行示例 | registry 独立消费、README 原样代码编译运行 |

## 环境与执行

使用已实测 SDK moon 0.1.20261119 / moonc v0.10.22，PowerShell 7、Node 22；参考差分需要 Go，可通过 GO_EXE 指定可执行文件。官方 Agent 使用 Linux amd64 Docker。安装依赖和采集器时需要网络。

```powershell
./tools/verify-acceptance.ps1 -Published
```

Linux Docker 环境加入官方 Agent：

```powershell
./tools/verify-acceptance.ps1 -Published -Agent
```

索引及所需依赖已就绪时，可显式增加 `-SkipUpdate`。每次执行在独立的 `.local/evidence/acceptance-*` 目录记录各步骤日志与 summary.json。只记录实际执行的检查；失败立即停止，同时保留已完成步骤和失败信息。摘要的 requested 字段标识是否请求 Agent 与线上安装验证。

## 建议演示顺序

1. 展示 Mooncakes 0.3.0 安装和 README 编码/UDP 示例。
2. 展示 Events、Service Checks、多值与聚合的类型化 API，结合 [协议说明](DOGSTATSD.md) 解释窗口的显式提交、采样和字节限制。
3. 运行 `moon run cmd/diagnostics --target native`，展示子客户端、计时、队列满和真实本机 UDP 接收。
4. 展示官方 Agent 的事件/check 转发及多值、聚合数值断言。
5. 对照 summary.json、Git 提交和包哈希，展示验证对象与结果的对应关系。

已有完整成功证据：[扩展功能 Windows/Ubuntu CI](https://github.com/Ryan-1125/moonstatsd/actions/runs/45391820670)。历史命令、失败定位与修复记录见 [VALIDATION.md](VALIDATION.md)，接口入口见 [README](../README.md)。

申报材料保存在本地 docs/shenbao.md；公开仓库通过上述源码、使用文档和证据入口展示项目。个人联系方式沿用本地材料的排除规则。
