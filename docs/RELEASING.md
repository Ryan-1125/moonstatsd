# 版本发布与包安全验收

## 包内容边界

`.moonignore` 采用默认拒绝、逐文件放行策略。`tools/package-files.txt` 是独立审计清单：新文件需要同时加入过滤规则与清单，实际 ZIP 的意外条目或缺失条目均导致失败。申报材料、凭据、日志及构建目录不属于包内容。

该规则只约束之后生成的包，不会删除 Mooncakes 已上传的历史版本。0.1.0 包含申报材料；0.2.0 使用新的白名单发布。若需移除历史归档，应联系 registry 维护方处理，不应把版本弃用等同于文件删除。

## 发布顺序

1. 更新 moon.mod、CHANGELOG、README 与版本化消费脚本，提交并核对生成接口。
2. 运行 `./tools/prepare-release.ps1`，验证格式、check/build、native 与 wasm-gc 测试、白名单审计和实际 ZIP 独立消费。缓存已就绪时可显式使用 `-SkipUpdate`，默认仍刷新索引。
3. 运行真实采集器和参考客户端验证；官方 Agent 测试需要 Linux amd64 Docker，使用 GitHub CI 执行。
4. 核对 `.local/evidence/release.json` 中的版本、SDK 和包 SHA256，确保版本对应的 CI 通过。
5. 人工或经授权运行 `moon publish`。prepare-release 脚本和 GitHub 工作流均不自动上传包，也不持有发布凭据。
6. 运行 `./tools/test-registry-consumer.ps1` 和 `./tools/test-readme.ps1`，验证 registry 的实际版本，而非工作区覆盖；保留输出作为发布后验收。

发布前脚本不创建远程 tag，不修改用户凭据，不进行全局 SDK 或 Git 配置修改。

## GitHub 版本验收

`Release acceptance` 工作流可手动触发：填写与 checkout 中 moon.mod 一致的版本；发布后勾选 published，额外执行实际 registry 消费与 README 示例测试。工作流保存版本、哈希和测试日志作为 artifact。普通 Verify 工作流继续覆盖 Windows、Ubuntu、真实采集器、参考客户端与官方 Agent。

## 运行排障

- `QueueFull`：说明本机缓冲已满。检查 `queue_full`，调整容量/刷新间隔、降低上报频率或采样，不应无限循环重试。
- `SendFailure`：检查 `message`、`bytes`、`metrics` 和 `stats`；发送失败计入本地 dropped，不会自动重试。
- `submitted` 增长但监控无数据：本机 UDP 成功不是远端确认；核对采集器地址、监听端口、协议模式、标签及网络策略。
- `TimerStopped`：计时器已进行过 stop 尝试。每次业务操作创建一个新计时器。
- `InvalidConfig("timer clock moved backwards")`：默认时钟发生回拨，可在应用侧提供经过确认的单调毫秒时钟。

可运行 `moon run cmd/diagnostics --target native`，通过真实本机 UDP 检查完整的业务辅助与诊断路径。
