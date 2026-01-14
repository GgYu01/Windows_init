# 设计与理念（root.ps1 首启编排）

## 系统概览
- 入口（主）：`Autounattend.xml` 在首次自动登录 Administrator 后调用 `C:\Windows\Setup\Scripts\root.ps1`。
- 入口（兜底）：`SetupComplete.cmd` 在安装完成阶段写入 `RunOnce`，确保首次交互登录也会调用 `root.ps1`（避免 `FirstLogonCommands` 偶发不执行）。
- 执行环境切换：`root.ps1` 为轻量 loader，若当前是 PowerShell 5.1 则尝试用本地 MSI 安装/定位 `pwsh.exe` 并以 7.x 重新执行 `root.core.ps1`；7.x 下直接调用核心脚本。
- 目标：单次或分阶段完成 Defender/防火墙关闭、PowerShell/Windows Terminal 配置、内存&DMA 优化、payload 复制与应用静默安装。
- 主流程封装为 `Invoke-RootOrchestration`，Transcript 生命周期由 `Start-RootTranscript` / `Stop-RootTranscript` 辅助函数集中管理，兜底捕获未处理异常。
- 日志输出采用“多落点”：主 Transcript 写入 `C:\ProgramData\WindowsInit\Logs`，并在结束时复制到 `C:\Users\Public\Desktop\WindowsInit-Debug`，同时入口脚本也各自写早期日志用于定位触发链路问题。
- 介质同步：仓库目录与安装源一致，提供 cmd 脚本一键同步最小内容（`scripts\sync-media.cmd`），并维护最小复制清单（`docs/minimal-copy.md`）。

## 核心流程
```
Autounattend -> root.ps1 (loader)
SetupComplete.cmd -> RunOnce -> FirstLogonBootstrap.ps1 -> root.ps1 (loader)   # fallback trigger
  -> 检测/安装 pwsh.exe
  -> 以 PowerShell 7 调用 root.core.ps1
      -> Invoke-RootOrchestration
         -> Acquire mutex (single-instance)
         -> Start-RootTranscript (返回启动标记)
         -> 读取 RootPhase
            -> Phase0: 安全/防护配置 + 可选 DefenderRemover -> 可能 return
            -> Phase1: PowerShell/Terminal/优化/复制/安装/自定义脚本
         -> Phase1 完成 -> Set RootPhase=2（单阶段/二阶段均标记完成）
         -> Stop-RootTranscript (仅在启动成功时)
         -> Release mutex
```

## 关键设计点
- **阶段控制**：通过 `RootPhase` 注册表值与 `RunOnce` 实现二阶段执行；保持幂等。
- **执行环境兼容**：`RunOnce` 指向 loader（root.ps1），确保二阶段在 PowerShell 5.1 下也能先安装/切换到 7.x 再继续。
- **入口可用性兜底**：在 `SetupComplete.cmd` 中写入 Phase0 的 `RunOnce`（指向 `FirstLogonBootstrap.ps1`），与 `FirstLogonCommands` 相互独立，避免单点入口失效导致必须手动执行，同时规避两阶段场景的时序串扰。
- **步骤包装**：`Invoke-Step` 统一捕获并记录每个子步骤的异常，避免全局中断。
- **日志可靠性**：`Start-RootTranscript` 返回布尔标志，`Stop-RootTranscript` 仅在成功启动时执行，避免 Stop-Transcript 抛错导致误判。
- **早期可观测性**：在 Transcript 之前先写入 `EarlyLogPath`（ProgramData），并将关键日志复制到 Public Desktop，确保“触发了但桌面没日志”也能定位到入口层级。
- **单实例保护**：`Invoke-RootOrchestration` 通过命名 Mutex 防止多个触发源并发执行造成重复安装/写注册表。
- **结构清晰**：Transcript 处理抽象为函数，主 try/finally 仅负责业务步骤，降低 PowerShell 5.1 对嵌套 try 的误判概率。
- **可扩展性**：主流程集中在单一函数，后续可按顺序插入新 `Invoke-Step` 而不破坏结构。
- **配置等效性**：在 PowerShell 7 中仍显式写入 Windows PowerShell profile 与执行策略（通过 `powershell.exe` 调用），保持旧版交互控制台的行为一致。
- **离线优先**：Windows Terminal 安装前检测 AppX 部署栈可用性以及本地离线依赖（UI.Xaml 2.8 + VCLibs Desktop x86/x64）；缺失即跳过以避免联网拉取或长时间挂起。
- **降级防御**：Defender 模块被第三方移除时，仅写策略注册表并跳过 `Set/Add/Get-Mp*` 调用，避免日志刷屏但保持防火墙等配置。
- **MSIX 兼容**：当当前 PowerShell 7 来自 WindowsApps（MSIX），跳过 LocalMachine 执行策略写入，避免对只读包路径的访问拒绝。

## 介质同步与最小清单
- **最小复制目标**：`Autounattend.xml`、`sources\Autounattend.xml`、`sources\$OEM$\$$\Setup\Scripts\`。
- **自动化入口**：`scripts\sync-media.cmd` 以 cmd 方式完成复制，适配 WinPE 环境。
- **可选组件**：WindowsTerminal / DefenderRemover / Payloads 等目录按需同步。

## 模块与数据流
- **输入**：本地预置 MSI/EXE、注册表键值、RunOnce 项。
- **状态写入**：
  - `HKLM\SOFTWARE\WindowsInit\RootPhase`（阶段标记）
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`（Phase0/Phase2 入口）
  - 各安全策略与电源/网络优化相关注册表键。
- **输出**：
  - 主 Transcript：`C:\ProgramData\WindowsInit\Logs\FirstBoot-*.log`（并复制到 `C:\Users\Public\Desktop\WindowsInit-Debug\`）
  - 入口级早期日志：`SetupComplete-*` / `FirstLogonBootstrap-*` / `RootLoader-*`
  - 可能的应用安装日志（各安装器自身产生）。

## 设计取舍
- 保留局部 `try/catch`：每个外部依赖调用（安装器、注册表写入）均局部防护，确保单点失败不终止流程；但将 Transcript 处理拆分函数以减少全局嵌套。
- 不强行重试：首启时间与稳定性优先，错误记录后由人工复核。

## 兼容性
- Loader 在 PowerShell 5.1 与 7.x 均可解析；核心逻辑运行于 7.x，遇到 5.1 会自动安装/切换。
- 依赖组件（DefenderRemover、WindowsTerminal 预装包等）缺失时，仅记录警告并跳过。

## 后续演进建议
- 为关键步骤添加运行时度量（耗时、退出码）写入日志，便于远程诊断。
- 如新增网络/下载类操作，需考虑离线环境的失败降级策略。
