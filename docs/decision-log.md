# 决策与灵感日志

| 日期 (UTC+0) | 决策/灵感 | 背景 | 影响 |
| --- | --- | --- | --- |
| 2026-01-14 | 仓库结构对齐安装源目录，移除 PE PowerShell 脚本，补充最小清单与 cmd 同步脚本，并启用目录级 LFS | 需要在 PE 中直接运行解压后的安装源，且 PowerShell 不一定可用；仓库需与镜像目录一致以便直接复制 | `sources\$OEM$\$$\Setup\Scripts` 成为唯一脚本入口路径；新增最小清单与一键同步脚本；对 DefenderRemover/WindowsTerminal/关键 Payload 目录启用 LFS 追踪以控制 `.git` 体积 |
| 2025-12-14 | 强化“触发链路可观测性”：多落点日志 + Probe 验证脚本 | 仍出现“开机不自动执行且桌面无日志”，需要区分：入口未触发 / 触发但早退 / 触发但日志写错位置；同时重装成本高 | SetupComplete/Bootstrap/Loader 先写调试日志，root.core 主 Transcript 落盘到 ProgramData 并复制到 Public Desktop；提供 `WindowsInitDiagnostics.ps1` + `-Probe` 在不影响现有程序的前提下验证 RunOnce 是否工作 |
| 2025-12-13 | 新增 `SetupComplete.cmd` + `FirstLogonBootstrap.ps1` 写入 Phase0 RunOnce 作为兜底触发，并在 `root.core.ps1` 增加 `RootPhase>=2` 幂等退出与命名 Mutex | 目标机出现“安装后未自动执行 root.ps1”的偶发现象；同时多入口触发可能导致并发或时序串扰 | 不依赖单一入口，首启可自愈；避免并发重复安装/写注册表；两阶段场景下避免 Phase1 被重复入口提前执行 |
| 2025-12-13 | 修复 Windows Terminal 离线依赖合并逻辑：强制数组化避免 `FileInfo + FileInfo` | `Get-ChildItem` 仅匹配 1 个依赖文件时变量为 `FileInfo`，使用 `+` 触发 `op_Addition` 崩溃 | Windows Terminal 安装步骤不再因依赖数量为 1 而中断；离线安装路径更稳定 |
| 2025-12-13 | 将 Steam 安装提至应用安装步骤的最前，优先启动 | 首启流程中任意后续步骤异常/重启都可能导致 Steam 迟迟未开始安装 | Steam 更早开始安装，降低“首启没装上”的概率 |
| 2025-12-10 | Windows Terminal 安装前强制校验 AppX 部署栈与 UI.Xaml/VCLibs 离线依赖，缺失即跳过 | 目标机可能裁剪了 AppX 组件，或缺少 VCLibs 导致 Add-AppxPackage 尝试联网并挂起 | 避免联网安装与长时间等待，确保首启流程可控且纯离线 |
| 2025-12-10 | Defender 模块缺失时降级为仅写策略注册表，跳过 Mp cmdlet | 第三方 Defender Remover 会移除 Defender 模块，原逻辑大量报错 | 日志更干净，仍维持策略级禁用与防火墙关闭 |
| 2025-12-10 | MSIX 版 PowerShell 7 跳过 LocalMachine 执行策略写入 | WindowsApps 下的 pwsh 包路径只读，Set-ExecutionPolicy LocalMachine 会报拒绝访问 | 消除无意义错误输出，仍保持 CurrentUser 作用域 Bypass |
| 2025-12-10 | 引入 `root.ps1` loader + `root.core.ps1` 核心拆分，RunOnce 指向 loader | PowerShell 5.1 解析失败且两阶段重启后仍需自动继续；需在 5.1 场景自动安装/切换到 7.x | 兼容 5.1 入口、保持二阶段自动续跑；核心逻辑固定运行在 7.x，行为稳定 |
| 2025-12-10 | 在 7.x 环境下显式写入 Windows PowerShell profile 与执行策略 | 主脚本改为 7.x 运行，原有 profile/执行策略修改针对 5.1，需保持旧版控制台重定向与策略放宽 | `powershell.exe` 仍被设置为 Bypass，Windows PowerShell profile 照常转发到 `pwsh.exe` |
| 2025-12-09 | 将 Transcript 生命周期抽象为 `Start-RootTranscript`/`Stop-RootTranscript`，清理主流程嵌套 try | 目标机仍出现“Try 缺少 Catch/Finally”报错，需要把日志开启/关闭与业务步骤解耦，减少解析歧义 | 语法验证 0 错误，Transcript 行为可重复复用，主流程结构更扁平 |
| 2025-12-09 | 将主流程封装为 `Invoke-RootOrchestration`，增加全局 catch 和 Transcript 启停标志 | Windows 目标机出现 Try 缺少 Catch/Finally 的解析错误，需要显式界定主流程边界，避免拷贝时缺少块导致语法异常 | 脚本在 PowerShell 7.5.4 解析无误，后续扩展集中在单函数内，便于审计与回归 |
| 2025-12-09 | 建立中文文档体系（需求池/设计/决策/交接） | 满足双语隔离要求，提升可维护性和交接效率 | 开发协作成本下降，后续需求与设计变更有可追溯记录 |
| 2025-12-09 | Transcript 停止前引入 `transcriptStarted` 防御 | Start-Transcript 可能因策略失败；原逻辑强停会产生误判 | 日志关闭行为与真实启动状态一致，减少伪异常 |
| 2025-12-09 | 将 Transcript 启动的 try/catch 拆出主 try，简化嵌套 | PowerShell 5.1 运行时报“Try 缺少 Catch/Finally”，怀疑嵌套 try 在某些环境被误判 | 解析路径更直观，减少旧版运行时的语法误报 |
| 2025-12-09 | 将 Transcript 启动重新纳入主 try/finally，保持单一 try 栈 | 避免多层 try 在 PS5 解析器上的潜在歧义，同时继续用内层 try 捕获启动失败 | 结构更扁平，兼容性更高，功能不变 |
