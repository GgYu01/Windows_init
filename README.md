# Windows_init – Windows 安装镜像自动化与首启定制

本仓库用于在 **不修改 install.wim、不重新封装 ISO** 的前提下，对官方 Windows 安装镜像进行以下增强：

- 集成 `Autounattend.xml`，自动完成 OOBE、自动登录 Administrator。
- 在 **首次自动登录 Administrator** 时自动执行 `root.ps1`，进行首启配置。
- 在首启阶段自动：
  - 从本地 `MSI` 安装非 Store 版 `PowerShell 7.5.4`；
  - 将交互式 `Windows PowerShell` 默认跳转到 `PowerShell 7`；
  - 调整执行策略、关闭 Defender / 防火墙 / SmartScreen / UAC 等限制；
  - 将预置的软件安装包从镜像中复制到 `C:\Users\Administrator\Downloads`；
  - 从本地预装包注册并安装 Windows Terminal，并将其配置为当前用户的默认控制台宿主；
  - 对部分软件执行静默安装（仅记录错误，不中断首启流程），包括：
    - `7z2501-x64.exe`
    - `581.57-desktop-win10-win11-64bit-international-dch-whql.exe`（NVIDIA 驱动，使用静默和清洁安装参数）
    - `SteamSetup.exe`
    - `VC_redist.x64.exe`
    - `VC_redist.x86.exe`
  - 可选执行自定义脚本（如 KMS 激活、额外调试配置等）。
- 全流程在桌面生成详细的首启日志文件，所有错误只记录不阻塞安装和启动。

---

## 仓库结构与角色

当前仓库文件：

- `Autounattend.xml`  
  - 无盘符路径的无人参与安装应答文件。  
  - 负责：
    - 设置 `windowsPE` 阶段的语言区域；
    - 配置 `oobeSystem` 阶段跳过 OOBE、自动登录 Administrator；
    - 在首次登录时通过 `FirstLogonCommands` 调用 `root.ps1`。

- `root.ps1`  
  - PowerShell 版本兼容 loader：在 **安装完成之后、首次自动登录 Administrator 时由 `Autounattend.xml` 调用**，也是 RunOnce 的二阶段入口。  
  - 当运行在 PowerShell 5.1 时，会优先定位/安装同目录的 `PowerShell-7.5.4-win-x64.msi`，再以 `pwsh.exe` 重启核心脚本；在 7.x 下直接调用核心脚本。  
  - 不包含业务逻辑，仅负责环境检测、安装与转发。  

- `root.core.ps1`  
  - 首启总控脚本（运行于 PowerShell 7），逻辑模块化：每个功能封装为函数，并通过统一的 `Invoke-Step` 包装执行。  
  - 关键行为：
    - 在首启一开始尽可能关闭 / 禁用 Defender 与防火墙，并为 `C:\Windows\Setup\Scripts` 与当前用户 `Downloads` 添加宽泛的排除项，避免预置安装包被误删；
    - 如果检测到 `C:\Windows\Setup\Scripts\DefenderRemover\Script_Run.bat`，会采用 **两阶段首启流程**：  
      - 第 1 阶段（首次自动登录）：只执行 Defender / 防火墙 / SmartScreen / UAC 配置，向注册表 `HKLM\SOFTWARE\WindowsInit` 写入阶段标记 `RootPhase=1`，并在 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce` 下注册 `WindowsInit-Phase2`（指向 loader），随后以参数 `y` 调用 `Script_Run.bat` 完成更激进的 Defender 移除并触发重启；  
      - 第 2 阶段（重启后再次登录）：由 `RunOnce` 再次调用 `root.ps1` loader，自动切换到 PowerShell 7，跳过 Defender 移除阶段，仅执行后续的 PowerShell/Windows Terminal/内存与 DMA 优化、payload 复制与软件安装等配置；  
    - 安装 `PowerShell-7.5.4-win-x64.msi` 到系统（如果尚未安装）；
    - 为当前用户写入 Windows PowerShell profile，将交互式会话自动转发到 `pwsh.exe`；
    - 同时配置 Windows PowerShell 与 PowerShell 7 的执行策略为 `Bypass`（7.x 环境下仍通过 `powershell.exe` 设置 5.1 策略）；
    - 调用 Defender / Firewall / SmartScreen / UAC 的配置逻辑；
    - 从预置目录复制 payload 到 `Downloads`；
    - 可选运行 `UserCustomization.ps1` 自定义脚本；
    - 将完整输出写入桌面日志文件 `FirstBoot-*.log`。

- `kms.txt`  
  - 目前仅作为你手动执行命令的备忘，并未在安装/首启流程中自动执行。  
  - 你可以将其中稳定可用的部分整理后迁移到 `UserCustomization.ps1` 中，由 `root.ps1` 在首启自动执行。

- `PowerShell-7.5.4-win-x64.msi`  
  - 官方的 PowerShell 7.5.4 x64 MSI 安装包。  
  - 在镜像中会被放置到 `C:\Windows\Setup\Scripts\PowerShell-7.5.4-win-x64.msi`，由 `root.ps1` 调用安装。

- `pe_tools.ps1`  
  - 在带图形界面的 WinPE 中使用的辅助脚本，要求 WinPE 已集成 PowerShell。  
  - 主要能力：
    - 生成 5 个长度为 10 的随机十六进制字符串（大写），以及 1 个 `000E` 开头、后续 8 位十六进制的字符串，并写入执行路径下的 `RandomHexIdentifiers.txt`；
    - 从脚本路径的相对路径 `无序网卡使用教程带工具\驱动\右键安装.inf` 自动安装网卡驱动（等效于右键 INF → 安装）；  
    - 启动 3 个 GUI 程序（路径均相对于脚本所在目录）：
      - `无序网卡使用教程带工具\修改程序.exe`
      - `硬盘PE系统和教程 文件如果无法打开请下载 RAR 解压工具 注意别下广告收费的\第二 SATA 硬盘 这个整个文件夹拷贝到PE桌面\VIUpdateTools.exe`
      - `主板修改和板载网卡教学\机器猫硬解工具 (1).exe`

- `Set-GpuDeviceDesc.ps1`
  - 仅用于安装完成后的系统中 **手动执行**，不会在安装或首启阶段自动调用。
  - 功能：根据显卡设备的 InstanceId，将注册表路径
    `HKLM\SYSTEM\CurrentControlSet\Enum\<InstanceId>\DeviceDesc`
    的值修改为指定的字符串（默认 `NVIDIA Geforce GTX 660`）。
  - 支持两种使用模式：
    - 直接指定 `-InstanceId` 参数；
    - 不指定参数时，使用 `Get-PnpDevice -Class Display` 枚举所有显示适配器，供你选择目标设备。

- `Set-MemoryDmaOptimization.ps1`
  - 内存管理与 PCIe/DMA 优化脚本，解决游戏高频操作导致的卡顿和 DMA 设备连接问题。
  - **在首启阶段由 `root.ps1` 自动执行核心优化**（一次性注册表配置）。
  - 也可手动执行进行验证或额外配置。
  - 核心优化项（对反作弊系统安全）：
    - 禁用 Memory Compression（内存压缩）
    - 禁用 SysMain/Superfetch 服务
    - 禁用 PCIe ASPM（Active State Power Management）
    - 扩展 PCIe Completion Timeout（65ms-210ms）
    - 配置 Ultimate Performance 电源计划
    - 禁用网络节流和 Nagle 算法
  - 支持 `-WhatIf` 预览模式和 `-ShowCurrentConfig` 查看当前配置。

- `StandbyListMaintenance/`
  - Standby List 维护子系统，用于定期清理内存 Standby List。
  - **警告**：计划任务功能使用 P/Invoke 调用 `ntdll.dll`，**可能触发反作弊系统检测**。
  - 包含文件：
    - `Clear-StandbyListGradual.ps1` - 渐进式清理脚本（阈值触发：>60% 物理内存）
    - `Register-StandbyListTask.ps1` - 计划任务注册脚本（15分钟间隔）
  - **推荐用法**：在启动游戏前手动运行 `Clear-StandbyListGradual.ps1 -Force`，而非注册计划任务。

---

## 内存管理与 DMA 优化模块

### 问题背景

游戏高频交易行操作（大量小内存对象分配/释放、频繁网络 I/O）可能导致：
- 游戏卡顿
- DMA 设备（如 PCIe FPGA 设备）连接超时或断开
- 类似 RAMMap 执行 "Empty Working Sets" 后的症状

### 技术原理

```
高频内存分配/释放 → Standby List 膨胀 → Working Set Trimming
→ PTE 失效 → TLB Shootdown → DMA 设备访问的物理地址失效
→ PCIe TLP Completion Timeout → 设备连接丢失
```

### 优化项说明

| 优化项 | 注册表/配置 | 作用 |
|--------|-------------|------|
| 禁用 Memory Compression | `Disable-MMAgent` + `DisablePageCombining=1` | 避免压缩页导致物理地址无效 |
| 禁用 SysMain | 服务 StartupType=Disabled | 减少 Working Set 竞争 |
| 禁用 ASPM | `ASPMOptOut=1` | 消除 PCIe 链路状态切换延迟 |
| 扩展 PCIe Timeout | `CompletionTimeout=0x6` | 65ms-210ms 超时范围 |
| Ultimate Performance | `powercfg` 配置 | 禁用所有电源管理延迟 |
| 禁用网络节流 | `NetworkThrottlingIndex=0xFFFFFFFF` | 减少交易延迟 |

### 反作弊系统注意事项

| 功能 | 风险等级 | 说明 |
|------|----------|------|
| 一次性注册表配置 | **安全** | 首启时执行，无持续进程 |
| 服务配置 | **安全** | 标准系统 API |
| 电源计划配置 | **安全** | 标准系统 API |
| Standby List 计划任务 | **高风险** | P/Invoke 调用 ntdll.dll，可能被检测 |

**建议**：
- 首启优化（`root.ps1` 中的 `Configure-MemoryAndDma`）在反作弊系统加载前执行，安全。
- **不要注册 Standby List 计划任务**，改为在启动游戏前手动运行清理脚本。

### 使用方法

```powershell
# （可选）在镜像中集成第三方 Defender Remover：
# 将 windows-defender-remover 仓库发布包中的完整内容
# 复制到 C:\Windows\Setup\Scripts\DefenderRemover（至少包含 Script_Run.bat、PowerRun.exe 以及 reg/powershell 脚本）
# 首次登录时，root.ps1 的第 1 阶段会自动执行：
#   Script_Run.bat y
# 等价于在 Defender Remover 交互界面中选择：
#   [Y] Remove Windows Defender Antivirus + Disable All Security Mitigations

# 查看当前配置
.\Set-MemoryDmaOptimization.ps1 -ShowCurrentConfig

# 预览所有优化（不实际执行）
.\Set-MemoryDmaOptimization.ps1 -All -WhatIf

# 执行所有安全优化（不包含计划任务）
.\Set-MemoryDmaOptimization.ps1 -All

# 游戏前手动清理 Standby List（推荐）
.\StandbyListMaintenance\Clear-StandbyListGradual.ps1 -Force
```

---

## 镜像目录布局设计（$OEM$ 机制）

**目标**：不修改 `install.wim`，只通过向安装介质添加文件完成所有集成。

Windows 安装程序对 `sources\$OEM$` 目录有约定：

- `sources\$OEM$\$1\...` 会在安装时复制到目标系统盘根目录（通常为 `C:\`）。
- `sources\$OEM$\$$\...` 会在安装时复制到目标 Windows 目录（通常为 `C:\Windows`）。

利用该机制，可以将本仓库的脚本与 payload 放到安装介质的以下路径：

```text
<镜像根>
├─ Autounattend.xml                        ← 来自仓库根目录
├─ boot
├─ efi
├─ sources
│  ├─ install.wim (或 install.esd)
│  ├─ ...
│  └─ $OEM$
│     └─ $$
│        └─ Setup
│           └─ Scripts
│              ├─ root.ps1                 ← 来自仓库 root.ps1
│              ├─ root.core.ps1            ← 业务编排主脚本（PowerShell 7）
│              ├─ Set-MemoryDmaOptimization.ps1  ← 内存/DMA优化脚本（可选手动执行）
│              ├─ StandbyListMaintenance   ← Standby List 维护子系统
│              │  ├─ Clear-StandbyListGradual.ps1
│              │  └─ Register-StandbyListTask.ps1
│              ├─ PowerShell-7.5.4-win-x64.msi
│              ├─ UserCustomization.ps1    ← 可选：你的扩展脚本
│              ├─ WindowsTerminal          ← Windows Terminal 预装包目录（需手动复制）
│              │  ├─ 47c42ab59d47421a89290c85b705f6ff.msixbundle
│              │  ├─ 47c42ab59d47421a89290c85b705f6ff_License1.xml
│              │  ├─ AUMIDs.txt
│              │  ├─ Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe.appx
│              │  ├─ Microsoft.UI.Xaml.2.8_8.2501.31001.0_x86__8wekyb3d8bbwe.appx
│              │  └─ （可选）其他架构的 XAML 依赖或 provxml 文件
│              ├─ DefenderRemover          ← 可选：第三方 Defender Remover 工具目录（放 Script_Run.bat 与其依赖文件）
│              └─ Payloads
│                 ├─ Defender_Control_2.1.0_Single
│                 ├─ Sunshine
│                 ├─ 7z2501-x64.exe
│                 ├─ 581.57-desktop-win10-win11-64bit-international-dch-whql.exe
│                 ├─ Kook_PC_Setup_v0.99.0.0.exe
│                 ├─ MSIAfterburner-64-4.6.5.exe
│                 ├─ QQ9.7.25.29411.exe
│                 ├─ ShareX-17.1.0-setup.exe
│                 ├─ SteamSetup.exe
│                 ├─ uuyc_4.8.2.exe
│                 ├─ VC_redist.x64.exe
│                 └─ VC_redist.x86.exe
└─ support
└─ ...
```

安装完成后，上述内容会出现在目标系统中：

- `Autounattend.xml` → 仅安装阶段使用；  
- `sources\$OEM$\$$\Setup\Scripts\*` → 复制到  
  `C:\Windows\Setup\Scripts\*`

`root.ps1` 以及 `MSI` 和 payload 由此进入目标系统，无需修改 `install.wim`。

---

## 仓库内容与镜像集成步骤

以下假设：

- 官方 ISO 已解压到某个目录，例如 `D:\WinISO`；
- 本仓库在 Linux 或 Windows 上均可使用，只要最终文件布局与 ISO 解压路径一致即可。

### 1. 在镜像根目录集成 Autounattend.xml

将仓库根目录下的 `Autounattend.xml` 复制到 ISO 解压目录根：

```powershell
# Windows PowerShell / PowerShell 7 示例
Copy-Item -Path "C:\path\to\Windows_init\Autounattend.xml" `
          -Destination "D:\WinISO\Autounattend.xml" `
          -Force
```

### 2. 在 sources\$OEM$\$$\Setup\Scripts 下集成首启脚本与 MSI

创建目录结构并复制脚本与 MSI：

```powershell
$isoRoot = "D:\WinISO"
$scripts = Join-Path $isoRoot "sources\$OEM$\$$\Setup\Scripts"

New-Item -Path $scripts -ItemType Directory -Force | Out-Null

Copy-Item "C:\path\to\Windows_init\root.ps1" `
          (Join-Path $scripts "root.ps1") -Force

Copy-Item "C:\path\to\Windows_init\PowerShell-7.5.4-win-x64.msi" `
          (Join-Path $scripts "PowerShell-7.5.4-win-x64.msi") -Force
```

如果你还需要自动执行自己的扩展逻辑（例如 KMS、额外注册表设置等），可以在仓库中创建 `UserCustomization.ps1`，然后一并复制：

```powershell
Copy-Item "C:\path\to\Windows_init\UserCustomization.ps1" `
          (Join-Path $scripts "UserCustomization.ps1") -Force
```

### 3. 在 Payloads 中集成软件安装包

在 `sources\$OEM$\$$\Setup\Scripts` 下创建 `Payloads` 子目录，并将所有预置软件复制进去：

```powershell
$payloads = Join-Path $scripts "Payloads"
New-Item -Path $payloads -ItemType Directory -Force | Out-Null

$files = @(
    "Defender_Control_2.1.0_Single",
    "Sunshine",
    "7z2501-x64.exe",
    "581.57-desktop-win10-win11-64bit-international-dch-whql.exe",
    "Kook_PC_Setup_v0.99.0.0.exe",
    "MSIAfterburner-64-4.6.5.exe",
    "QQ9.7.25.29411.exe",
    "ShareX-17.1.0-setup.exe",
    "SteamSetup.exe",
    "uuyc_4.8.2.exe",
    "VC_redist.x64.exe",
    "VC_redist.x86.exe"
)

foreach ($name in $files) {
    Copy-Item "C:\path\to\your\payloads\$name" `
              (Join-Path $payloads $name) `
              -Recurse -Force
}
```

> **说明**：这些 payload 不需要放入 Git 仓库，只需要在构建安装介质时按照上述命名复制到 `Payloads` 目录即可。

### 4. 是否需要重新封装 ISO

你有两种选择：

1. **不封装 ISO，直接用解压目录作为安装源**  
   - 将 `D:\WinISO` 直接复制到 U 盘根目录（保持目录结构不变）；  
   - 用该 U 盘启动后，从 U 盘根运行 `setup.exe`，或者从 WinPE 中指定该目录调用 `setup.exe`。

2. **重新生成 ISO（可选）**  
   - 如果你需要一个单文件 ISO 分发，可以使用 `oscdimg` 等工具重新打包。  
   - 但从 Windows Setup 行为上讲，这不是必须的。

仓库的设计是**不依赖重新封装 `install.wim`**，只依赖文件系统层面的目录结构，所以两种方式都兼容。

---

## 使用 WinPE 或 PE U 盘进行安装的工作流

你的问题是：是否可以 **在 PE 环境中解压官方 Windows 镜像，直接将新增文件写入解压路径，然后不重新封装 WIM，直接运行 setup 并指定安装磁盘**。

从 Windows Setup 机制分析：

- `setup.exe` 在运行时，只要能在其同级或下级目录找到标准的结构（`sources\install.wim` / `install.esd` 等），就可以正常工作；
- 它不要求安装介质必须是 ISO 形式，也不要求 `install.wim` 再重新打包，只要文件和目录结构正确即可；
- `$OEM$` 复制机制在这种文件夹结构下仍然按标准规则工作。

因此，典型流程如下：

1. 在任意环境（Windows / Linux）中将官方 ISO 解压到某个目录（如 `D:\WinISO`）。  
2. 按前面说明，将本仓库的内容（`Autounattend.xml`、`root.ps1`、`MSI`、`Payloads` 等）复制到该目录及其子目录。  
3. 将 `D:\WinISO` 完整复制到 PE U 盘上的某个目录（例如 `X:\WinSrc`），或直接作为 U 盘根。  
4. 使用 PE U 盘启动目标机器，在 PE 中：

   ```cmd
   :: 例如 WinPE 中，假设安装源在 D:\ ，目标为磁盘 0
   diskpart
   # 在 diskpart 中进行你想要的分区操作，完成后 exit

   D:\setup.exe /unattend:D:\Autounattend.xml
   ```

   - 如果 `Autounattend.xml` 置于安装源根目录，`setup.exe` 可自动发现；你显式指定 `/unattend` 则更直观。
   - 如果你在 `Autounattend.xml` 中没有配置 `DiskConfiguration`，则磁盘分区仍旧可由 GUI 交互决定；  
     若你在其中写入了完整的磁盘分区配置，则可以做到全程无人值守。

> **结论**：  
> 你完全可以使用“解压后的安装源 + 文件系统级复制 + 不修改 WIM”模式，配合本仓库内容，实现自动安装与首启定制，无需每次重新封装 install.wim。

---

## 在 WinPE 中使用 `pe_tools.ps1`

前提假设：

- 你的 WinPE 为带图形界面的版本，并已集成 PowerShell（通常是 WinPE-HTA 或基于 ADK 自行添加 PowerShell 组件后构建的镜像）。
- 与 `pe_tools.ps1` 同级或子目录下，已经放置以下目录/文件：
  - `无序网卡使用教程带工具\驱动\右键安装.inf`
  - `无序网卡使用教程带工具\修改程序.exe`
  - `硬盘PE系统和教程 文件如果无法打开请下载 RAR 解压工具 注意别下广告收费的\第二 SATA 硬盘 这个整个文件夹拷贝到PE桌面\VIUpdateTools.exe`
  - `主板修改和板载网卡教学\机器猫硬解工具 (1).exe`

推荐的目录结构示例（在 PE 环境中挂载后）：

```text
X:\Tools
├─ pe_tools.ps1
├─ 无序网卡使用教程带工具
│  ├─ 修改程序.exe
│  └─ 驱动
│     └─ 右键安装.inf
├─ 硬盘PE系统和教程 文件如果无法打开请下载 RAR 解压工具 注意别下广告收费的
│  └─ 第二 SATA 硬盘 这个整个文件夹拷贝到PE桌面
│     └─ VIUpdateTools.exe
└─ 主板修改和板载网卡教学
   └─ 机器猫硬解工具 (1).exe
```

在 WinPE 中使用步骤：

```powershell
# 1. 打开 WinPE 中的 PowerShell（如通过开始菜单或 Run 对话框）

# 2. 切换到工具目录
Set-Location X:\Tools

# 3. 临时放宽执行策略（仅当前进程）
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# 4. 执行脚本
.\pe_tools.ps1
```

运行结果：

- 在脚本所在目录生成 `RandomHexIdentifiers.txt`，内容包括：
  - 5 行，每行 10 个大写十六进制字符；
  - 第 6 行，形如 `000E1234ABCD` 的字符串（`000E` + 8 位随机十六进制，大写）。
- 使用 `rundll32.exe setupapi,InstallHinfSection` 静默安装 `右键安装.inf` 指定的网卡驱动。
- 启动 3 个 GUI 程序到前台，便于你在 WinPE 中进行进一步的交互操作。

---

## root.core.ps1 核心接口与扩展点概览

作为后续维护的参考，这里列出 `root.core.ps1` 的主要扩展点（业务编排），`root.ps1` 仅作为版本兼容 loader：

```powershell
function Install-PowerShell7 { ... }
function Configure-PowerShellDefaults { ... }
function Set-ExecutionPolicies { ... }
function Install-WindowsTerminal { ... }
function Set-DefaultTerminalToWindowsTerminal { ... }
function Configure-DefenderAndFirewall { ... }
function Configure-SmartScreenAndUac { ... }
function Configure-MemoryAndDma { ... }           # 内存/DMA优化
function Copy-PayloadsToDownloads { ... }
function Install-Applications { ... }
function Invoke-UserCustomizationScript { ... }
function Confirm-AdministratorToken { ... }
```

主流程调用顺序：

```powershell
Invoke-Step -Name 'Confirm administrator token'           -Action { Confirm-AdministratorToken }
Invoke-Step -Name 'Install PowerShell 7.5.4'              -Action { Install-PowerShell7 }
Invoke-Step -Name 'Configure PowerShell defaults'         -Action { Configure-PowerShellDefaults }
Invoke-Step -Name 'Set execution policies'                -Action { Set-ExecutionPolicies }
Invoke-Step -Name 'Install Windows Terminal'              -Action { Install-WindowsTerminal }
Invoke-Step -Name 'Set Windows Terminal as default host'  -Action { Set-DefaultTerminalToWindowsTerminal }
Invoke-Step -Name 'Configure Defender and firewall'       -Action { Configure-DefenderAndFirewall }
Invoke-Step -Name 'Configure SmartScreen and UAC'         -Action { Configure-SmartScreenAndUac }
Invoke-Step -Name 'Configure memory and DMA optimization' -Action { Configure-MemoryAndDma }
Invoke-Step -Name 'Copy payloads to Downloads'            -Action { Copy-PayloadsToDownloads }
Invoke-Step -Name 'Install core applications'             -Action { Install-Applications }
Invoke-Step -Name 'Invoke user customization script'      -Action { Invoke-UserCustomizationScript }
```

如果你后续希望添加新的子步骤（例如 GPU 驱动静默安装、特定服务配置等），只需：

1. 在 `root.ps1` 中新增一个 `function` 封装该逻辑；
2. 在主流程中增加一条对应的 `Invoke-Step` 调用；
3. 确保任何潜在的异常由该函数内部的 `try/catch` 或 `Invoke-Step` 包装捕获。

---

## 文档索引

- `docs/requirements.md`：需求池与用户故事，含当前状态与风险假设。
- `docs/design.md`：首启编排设计、数据流与兼容性说明。
- `docs/decision-log.md`：关键决策与灵感记录，含日期与影响范围。
- `docs/handover.md`：开发者交接手册，覆盖解析校验、修改指南与常见故障切入点。

---

## 建议的提交信息（commit message）

推荐使用如下英文提交信息，简洁但涵盖关键改动点：

```text
Document OEM-based layout for first-boot automation and media integration

- Clarify how Autounattend.xml and root.ps1 are mapped into the installed system
- Describe use of sources\$OEM$\$$\Setup\Scripts to avoid modifying install.wim
- Explain PowerShell 7 MSI installation, payload staging, and first-boot logging
- Provide detailed instructions for integrating this repo into extracted Windows media and using WinPE for setup
```

如你希望进一步模块化（例如把 Defender/UAC 相关设置拆成独立脚本模块，再由 `root.ps1` dot-source），可以在现有结构上继续演进，我可以按你偏好的风格设计对应的文件拆分方案。
