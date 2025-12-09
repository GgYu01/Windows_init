# 设计与理念（root.ps1 首启编排）

## 系统概览
- 入口：`Autounattend.xml` 在首次自动登录 Administrator 后调用 `C:\Windows\Setup\Scripts\root.ps1`。
- 目标：单次或分阶段完成 Defender/防火墙关闭、PowerShell/Windows Terminal 配置、内存&DMA 优化、payload 复制与应用静默安装。
- 新增：主流程封装为 `Invoke-RootOrchestration`，Transcript 生命周期由 `Start-RootTranscript` / `Stop-RootTranscript` 辅助函数集中管理，兜底捕获未处理异常。

## 核心流程
```
Autounattend -> root.ps1
  -> Invoke-RootOrchestration
     -> Start-RootTranscript (返回启动标记)
     -> 读取 RootPhase
        -> Phase0: 安全/防护配置 + 可选 DefenderRemover -> 可能 return
        -> Phase1: PowerShell/Terminal/优化/复制/安装/自定义脚本
     -> Phase1 完成且 RootPhase=1 -> Set RootPhase=2
     -> Stop-RootTranscript (仅在启动成功时)
```

## 关键设计点
- **阶段控制**：通过 `RootPhase` 注册表值与 `RunOnce` 实现二阶段执行；保持幂等。
- **步骤包装**：`Invoke-Step` 统一捕获并记录每个子步骤的异常，避免全局中断。
- **日志可靠性**：`Start-RootTranscript` 返回布尔标志，`Stop-RootTranscript` 仅在成功启动时执行，避免 Stop-Transcript 抛错导致误判。
- **结构清晰**：Transcript 处理抽象为函数，主 try/finally 仅负责业务步骤，降低 PowerShell 5.1 对嵌套 try 的误判概率。
- **可扩展性**：主流程集中在单一函数，后续可按顺序插入新 `Invoke-Step` 而不破坏结构。

## 模块与数据流
- **输入**：本地预置 MSI/EXE、注册表键值、RunOnce 项。
- **状态写入**：
  - `HKLM\SOFTWARE\WindowsInit\RootPhase`（阶段标记）
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`（二阶段入口）
  - 各安全策略与电源/网络优化相关注册表键。
- **输出**：桌面日志 `FirstBoot-*.log`、可能的应用安装日志（各安装器自身产生）。

## 设计取舍
- 保留局部 `try/catch`：每个外部依赖调用（安装器、注册表写入）均局部防护，确保单点失败不终止流程；但将 Transcript 处理拆分函数以减少全局嵌套。
- 不强行重试：首启时间与稳定性优先，错误记录后由人工复核。

## 兼容性
- 语法兼容 PowerShell 5.1 与 7.x（验证于 7.5.4 解析无误）。
- 依赖组件（DefenderRemover、WindowsTerminal 预装包等）缺失时，仅记录警告并跳过。

## 后续演进建议
- 为关键步骤添加运行时度量（耗时、退出码）写入日志，便于远程诊断。
- 如新增网络/下载类操作，需考虑离线环境的失败降级策略。
