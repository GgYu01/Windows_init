# 需求池（Windows_init）

## 背景与范围
- 场景：Windows 安装镜像首启脚本在目标机原生 `powershell.exe`（5.1）中解析失败，需要兼容旧版并保持首启自动化。
- 目标：在不重启服务/容器、不改动非本项目内容的前提下，修复脚本可解析性、保持功能等价，并建立可追踪的文档体系。

## 原始需求与状态
| ID | 描述 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| R1 | 修复 `root.ps1` 语法错误，确保在 PowerShell 5.1/7.x 均可解析 | 高 | 完成 | 将 Transcript 生命周期抽象为 `Start-RootTranscript` / `Stop-RootTranscript`，移除易误判的嵌套 try，`Parser.ParseFile` 验证 0 语法错误 |
| R2 | 保证首启日志（Transcript）可靠启动与关闭，不因失败导致异常 | 中 | 完成 | `Stop-RootTranscript` 仅在启动成功时调用，避免 Stop-Transcript 的伪异常 |
| R3 | 建立中文文档体系：需求池、设计理念、决策日志、交接手册 | 中 | 完成 | 新增 `docs/` 目录四份 Markdown 文档 |
| R4 | README 中暴露文档索引，便于快速定位 | 低 | 完成 | 新增文档索引段落 |
| R5 | 在 PowerShell 5.1 环境下自动切换到 PowerShell 7 执行核心逻辑 | 高 | 完成 | 引入 `root.ps1` 轻量 loader：如缺失 `pwsh.exe` 自动用本地 MSI 安装，再调用 `root.core.ps1`；`RunOnce` 也指向 loader |

## 用户故事
- 作为镜像自动化维护者，我需要 `root.ps1` 在首次登录时可以无语法错误地执行，以便所有配置步骤可顺利跑完。
- 作为运维工程师，我希望日志采集在脚本异常时也能安全关闭，避免阻塞后续动作。
- 作为新加入的开发者，我需要一套中文文档来理解系统设计、演进决策与接手步骤。

## 待办与后续验证
- [ ] 在目标 Windows 机器上以 PowerShell 5.1 运行解析测试，确认 loader 可自动安装并调用 PowerShell 7。
- [ ] 若未来新增步骤，需同步更新 `docs/design.md` 的流程图与 `docs/decision-log.md` 的决策条目。

## 风险与假设
- 假设目标环境具备本地管理员权限，允许写入 RunOnce 与注册表键值。
- 当前未在 Linux 环境下执行脚本主体，仍需在真实 Windows 环境验证各子步骤的执行结果。
