# 最小复制清单

目标：在 **不封装 ISO** 的情况下，将仓库内容复制到解压后的安装源根目录即可使用。

## 最小清单（保证首启链路 + 离线 PowerShell 7）

必需文件与目录：

1. `Autounattend.xml`
2. `sources\Autounattend.xml`
3. `sources\$OEM$\$$\Setup\Scripts\root.ps1`
4. `sources\$OEM$\$$\Setup\Scripts\root.core.ps1`
5. `sources\$OEM$\$$\Setup\Scripts\FirstLogonBootstrap.ps1`
6. `sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd`
7. `sources\$OEM$\$$\Setup\Scripts\WindowsInitDiagnostics.ps1`
8. `sources\$OEM$\$$\Setup\Scripts\Set-MemoryDmaOptimization.ps1`
9. `sources\$OEM$\$$\Setup\Scripts\PowerShell-7.5.4-win-x64.msi`

> 若目标系统已内置 PowerShell 7，可选跳过第 9 项；否则建议保留以确保离线安装。

## 可选组件（按需复制）

- `sources\$OEM$\$$\Setup\Scripts\Payloads\`：预置安装包与辅助脚本（自动复制/安装）
- `sources\$OEM$\$$\Setup\Scripts\WindowsTerminal\`：Windows Terminal 离线包
- `sources\$OEM$\$$\Setup\Scripts\DefenderRemover\`：第三方 Defender Remover
- `sources\$OEM$\$$\Setup\Scripts\StandbyListMaintenance\`：Standby List 维护脚本
- `sources\$OEM$\$$\Setup\Scripts\Payloads\Set-GpuDeviceDesc.ps1`：手动 GPU 描述修改

## 最小复制方式（推荐）

使用本仓库提供的 cmd 脚本一键复制：`scripts\sync-media.cmd`  
详见 `docs/sync-script.md`。
