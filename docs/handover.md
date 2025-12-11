# 交接手册（开发者快速上手）

## 环境准备
- 建议在 Windows 10/11 + PowerShell 5.1/7.x 下验证；Linux 仅用于静态解析。
- 核心文件：`root.ps1`（5.1/7.x 兼容 loader，负责安装/调用 pwsh）、`root.core.ps1`（首启编排主逻辑）、`Autounattend.xml`（触发）、`Payloads/`（离线安装包）。

## 快速检查
1. 静态解析（Linux 亦可）：`pwsh -NoLogo -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('root.ps1',[ref]$null,[ref]$null);[System.Management.Automation.Language.Parser]::ParseFile('root.core.ps1',[ref]$null,[ref]$null)"`（无输出即通过）。
2. Loader 自检（在隔离 VM 上进行）：确认 `PowerShell-7.5.4-win-x64.msi` 与 `root.core.ps1` 同目录；用 `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\\root.ps1` 观察是否自动安装/定位 `pwsh.exe`，退出码为 0。
3. 逻辑入口：核心脚本末尾已调用 `Invoke-RootOrchestration`，无需额外入口。
4. 关注日志：首启生成 `FirstBoot-*.log`，包含每步的 Info/Warn/Error。
5. Windows Terminal 离线包自检：`WindowsTerminal/` 需包含 msixbundle、License、`Microsoft.UI.Xaml.2.8_*` x86/x64、`Microsoft.VCLibs.*Desktop*` x86/x64；缺失任一或 AppX 栈被裁剪时脚本会跳过安装与预配。

## 修改指引
- 仅在 `Invoke-RootOrchestration` 内追加新的 `Invoke-Step`，保持阶段顺序。
- 日志行为调整需复用 `Start-RootTranscript` / `Stop-RootTranscript`，避免在主流程中直接调用 `Start-Transcript` 或 `Stop-Transcript`。
- 新增外部依赖时，确保在缺失场景下只记录警告，不中断流程。
- 任何代码改动需同步更新 `docs/requirements.md`（状态）、`docs/design.md`（流程/模块）、`docs/decision-log.md`（决策）。

## 两阶段执行说明
- Phase0：首次自动登录时执行。若发现 `DefenderRemover`，仅做安全/防护配置并注册 RunOnce，然后调用 remover（可能触发重启）。
- Phase1：若 Phase0 已注册 RunOnce，则重启后由 RunOnce 自动用 `powershell.exe` 调用 loader，再跳转到 PowerShell 7 继续执行余下配置。
- 单阶段：未检测到 `DefenderRemover` 时，直接在当前会话完成所有步骤。

## 打包与部署
- 按 README 的 $OEM$ 布局将脚本与 payload 置于 `sources\\$OEM$\\$$\\Setup\\Scripts`。
- 如需两阶段执行，确保 `DefenderRemover` 目录完整并包含 `Script_Run.bat`/`Defender.Remover.exe`。

## 常见故障切入点
- Transcript 无法启动：检查执行策略或磁盘权限，必要时手动创建桌面日志目录。
- RunOnce 未注册：确认当前用户为 Administrator 且注册表写入未被策略阻断。
- 安装器静默参数失效：查看各安装器对应的日志/退出码，并在 `Install-Applications` 中追加专用处理。
- Windows Terminal 未安装：常见原因是缺失 VCLibs/UI.Xaml 依赖或目标系统裁剪了 AppX 部署栈，脚本会跳过以避免联网安装；补齐离线包或在支持 AppX 的版本上安装。
- Defender 步骤报错消失：当第三方 Defender Remover 删除了 Mp 模块时，脚本会仅写策略注册表并跳过 Mp cmdlet，属预期降级行为。
