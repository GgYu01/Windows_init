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
| R6 | Windows Terminal 必须全离线安装：缺少 AppX 栈或 XAML/VCLibs 依赖时应跳过，避免联网与长时间挂起 | 高 | 完成 | `Install-WindowsTerminal` 新增 AppX 部署栈探测与依赖完整性检查，缺失即跳过 |
| R7 | Defender 模块被第三方移除时仍应静默降级，避免 Set-MpPreference/ Add-MpPreference 报错刷屏 | 中 | 完成 | 缺失 Defender cmdlet 时仅写策略注册表，跳过 mp cmdlet 调用和状态查询 |
| R8 | MSIX 版 PowerShell 7 不可写 LocalMachine 执行策略，需绕过并给出明确告警 | 低 | 完成 | `Set-ExecutionPolicies` 检测 `PSHOME` 位于 WindowsApps 时跳过 LocalMachine 作用域 |
| R9 | 修复 Windows Terminal 离线依赖枚举在“仅匹配到 1 个文件”时的 `op_Addition` 崩溃 | 高 | 完成 | 将 `Get-ChildItem` 返回值强制转为数组，避免 `FileInfo + FileInfo` |
| R10 | 首启自动触发需可自愈：即使 `FirstLogonCommands` 未执行也能在首次交互登录自动跑 `root.ps1` | 高 | 完成 | 新增 `SetupComplete.cmd` + `FirstLogonBootstrap.ps1` 写入 RunOnce 兜底并规避两阶段时序串扰；`root.core.ps1` 增加 `RootPhase>=2` 幂等退出与互斥锁防并发 |
| R11 | Steam 在所有静默安装任务中应最高优先级启动 | 中 | 完成 | 将 Steam 安装移动到 `Install-Applications` 的第一位并保持后台启动 |
| R12 | 增强首启可观测性：即使未生成用户桌面 Transcript，也必须能定位触发链路与早退原因 | 高 | 完成 | SetupComplete/Bootstrap/Loader 写入 Public Desktop + ProgramData 调试日志；root.core 主 Transcript 落盘到 ProgramData 并复制到 Public Desktop；新增 `WindowsInitDiagnostics.ps1` + `-Probe` 无侵入验证 |

## 用户故事
- 作为镜像自动化维护者，我需要 `root.ps1` 在首次登录时可以无语法错误地执行，以便所有配置步骤可顺利跑完。
- 作为使用者，我需要安装完成后无需手动执行命令，首启流程能自动触发并在偶发入口失效时自愈。
- 作为重装成本很高的使用者，我需要一种在现有系统内可重复验证“触发链路是否工作”的方式，并且该验证不能影响我已下载/已安装的软件。
- 作为游戏环境维护者，我希望 Steam 尽早启动安装，避免后续步骤异常或重启导致安装优先级下降。
- 作为运维工程师，我希望日志采集在脚本异常时也能安全关闭，避免阻塞后续动作。
- 作为新加入的开发者，我需要一套中文文档来理解系统设计、演进决策与接手步骤。

## 待办与后续验证
- [ ] 在目标 Windows 机器上以 PowerShell 5.1 运行解析测试，确认 loader 可自动安装并调用 PowerShell 7。
- [ ] 在“现有已安装系统”上跑一次 `WindowsInitDiagnostics.ps1 -RegisterProbe -Scope User`，验证 Probe 日志是否在下次登录出现在 `C:\\Users\\Public\\Desktop\\WindowsInit-Debug`。
- [ ] 若未来新增步骤，需同步更新 `docs/design.md` 的流程图与 `docs/decision-log.md` 的决策条目。

## 风险与假设
- 假设目标环境具备本地管理员权限，允许写入 RunOnce 与注册表键值。
- 当前未在 Linux 环境下执行脚本主体，仍需在真实 Windows 环境验证各子步骤的执行结果。
