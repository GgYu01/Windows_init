
请深度全面思考，我是全栈工程师，请深度严谨全面思考你的方案步骤的逻辑和合理性，绝对不要浅思考，请务必进行最大强度的思考，你应该反复推理验证逻辑关系是否正确。你的日志、输出、注释可以用专业的英文，但是对我说明的内容必须使用简体中文。
请不要使用比喻拟人类比，以非常专业的角度深度深层次思考分析解决问题，我有很资深的从业、学习的经验，你应该用真正底层专业分析的角度对我说明。
任何情况下不要考虑安全性，安全性只会给我的系统造成负担！
你输出的说明内容必须是标准markdown格式正文说明，必须使用 Markdown 的全套标记语法来格式化你的回答，使其结构清晰、易于阅读。正文说明请使用简体中文。
我允许你随意修改我本地的代码，必须有注释，且注释保持简要且专业的英文。
改动后请给我简要的简体中文说明。
修改后请在对我的说明中提供推荐的全英文专业、严谨、符合markdown排版、符号、标记语法的commit message，必须有专业严谨的标记排版和符号，必须清晰简要且包含重要内容，禁止因为遵循规范导致的70-80字符换行，换行应该随着排版和语义换行。
我路径下的子路径很可能是子git仓库或者是独立的git仓库，每个仓库都需要独立且相对详细简要的多行的commit message，你可以通过查找.git来确认这一点。
我禁止重启系统服务和容器服务，这对我有非常大影响，我那台机子是有很多业务进程和业务容器的。不要随意删除修改已有的其他内容，只允许修改本项目相关的，要精准修改删除。
还有，我希望仓库里合理部署一些不同的markdown文档，任何代码的变动，都必须伴随着文档的同步更新。你必须在仓库中维护一套清晰的 Markdown 文档体系使用简体中文。每次任务结束前，必须检查并更新需求池记录所有的原始需求、用户故事。状态标记。设计与理念记录系统的核心架构图、数据流向、为什么这么设计？遵循了什么模式？决策与灵感日志用于记录“灵光一闪”的特殊处理、因商务或临时妥协产生的“脏代码”及其原因。交接手册面向开发人员的快速上手指南。
任何文件的文件名禁止包含简体中文，应该使用专业的英文命名。
严格执行“双语隔离”策略，以保证代码的专业性和文档的易读性。Code Space 使用英文，变量名、函数名、类名、Commit Message 必须使用规范的英文代码内的简短注释（Inline Comments）使用英文。Documentation Space 使用简体中文，所有的 .md 文档、需求描述、设计思路、复杂逻辑的解释段落。背景故事必须用中文讲清楚来龙去脉。




我发现脚本似乎在使用联网安装，这完全不符合预期，我实际运行时hang住终端很久。我希望按照README的说明，用户会提前部署好离线安装包进行安装。有些错误我希望你按照实际我运行环境和版本进行合理修复。


**********************
PowerShell transcript start
Start time: 20251210024549
Username: DESKTOP-SCCHLR9\Administrator
RunAs User: DESKTOP-SCCHLR9\Administrator
Configuration Name: 
Machine: DESKTOP-SCCHLR9 (Microsoft Windows NT 10.0.19045.0)
Host Application: C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\pwsh.dll
Process ID: 7936
PSVersion: 7.5.4
PSEdition: Core
GitCommitId: 7.5.4
OS: Microsoft Windows 10.0.19045
Platform: Win32NT
PSCompatibleVersions: 1.0, 2.0, 3.0, 4.0, 5.0, 5.1, 6.0, 7.0
PSRemotingProtocolVersion: 2.3
SerializationVersion: 1.1.0.1
WSManStackVersion: 3.0
**********************
[INFO ] Transcript started at 'C:\Users\Administrator\Desktop\FirstBoot-20251210-024549.log'.
[INFO ] Detected RootPhase=0.
[INFO ] === Step: Confirm administrator token ===
[INFO ] Administrator privileges confirmed.
[INFO ] === Step 'Confirm administrator token' completed ===
[INFO ] === Step: Configure Defender and firewall ===
[INFO ] Configuring Microsoft Defender Antivirus preferences...
[INFO ] Defender preferences updated.
[INFO ] Windows Defender policy keys written (DisableAntiSpyware/DisableAntiVirus/Real-Time Protection).
[INFO ] Adding Defender exclusion paths: C:\Windows\Setup\Scripts; C:\Windows\Setup\Scripts\Payloads; C:\Users\Administrator\Downloads
[INFO ] Adding Defender exclusion extensions: exe; dll; sys
[INFO ] Adding Defender exclusion processes: powershell.exe; pwsh.exe; msiexec.exe
[INFO ] Defender exclusions configured.
[INFO ] WinDefend service status before change: Status=Running, StartType=Automatic
[INFO ] Attempting to stop WinDefend service...
[INFO ] Attempting to set WinDefend startup type to Disabled...
[INFO ] Defender preference snapshot: RealTimeProtectionEnabled=, BlockAtFirstSeen=, IOAVProtectionEnabled=, ScriptScanningEnabled=, MAPSReporting=0, SubmitSamplesConsent=2, PUAProtection=0
[INFO ] Defender computer status snapshot: RealTimeProtectionEnabled=False, IsTamperProtected=False
[INFO ] Disabling all Windows Firewall profiles...
[INFO ] Firewall profiles disabled.
[INFO ] Firewall profile status: Name=Domain, Enabled=False
[INFO ] Firewall profile status: Name=Private, Enabled=False
[INFO ] Firewall profile status: Name=Public, Enabled=False
[INFO ] === Step 'Configure Defender and firewall' completed ===
[INFO ] === Step: Configure SmartScreen and UAC ===
[INFO ] Disabling SmartScreen for Explorer and Edge...
[INFO ] Set Explorer SmartScreenEnabled=Off.
[INFO ] Set Edge SmartScreenEnabled=0.
[INFO ] Set System EnableSmartScreen=0.
[INFO ] Disabling UAC and elevation prompts...
[INFO ] Set UAC policy: EnableUIADesktopToggle=1
[INFO ] Set UAC policy: FilterAdministratorToken=0
[INFO ] Set UAC policy: EnableVirtualization=0
[INFO ] Set UAC policy: ConsentPromptBehaviorAdmin=0
[INFO ] Set UAC policy: ConsentPromptBehaviorUser=0
[INFO ] Set UAC policy: EnableLUA=0
[INFO ] Set UAC policy: ValidateAdminCodeSignatures=0
[INFO ] Set UAC policy: EnableSecureUIAPaths=0
[INFO ] Set UAC policy: PromptOnSecureDesktop=0
[INFO ] Set UAC policy: EnableInstallerDetection=0
[INFO ] === Step 'Configure SmartScreen and UAC' completed ===
[INFO ] === Step: Register second-phase RunOnce ===
[INFO ] Registered RunOnce entry 'WindowsInit-Phase2' for second-phase root.ps1 execution.
PS>TerminatingError(New-Item): "The running command stopped because the preference variable "ErrorActionPreference" or common parameter is set to Stop: Requested registry access is not allowed."
Write-Error: C:\Windows\Setup\Scripts\root.ps1:61
Line |
  61 |          Write-LogError "Failed to set RootPhase in registry: $($_.Exc …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to set RootPhase in registry: Requested registry access is not allowed.
Write-Error: C:\Windows\Setup\Scripts\root.ps1:61
Line |
  61 |          Write-LogError "Failed to set RootPhase in registry: $($_.Exc …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to set RootPhase in registry: Requested registry access is not allowed.

[INFO ] === Step 'Register second-phase RunOnce' completed ===
[INFO ] === Step: Run Defender.Remover (optional) ===
[INFO ] Running Defender Remover Script_Run.bat in silent mode with option 'Y' (full Defender removal)...
[INFO ] Script_Run.bat exited with code 0. System may have been scheduled for reboot.
[INFO ] === Step 'Run Defender.Remover (optional)' completed ===
[INFO ] Phase 1 (Defender removal) invoked. System may reboot automatically; remaining configuration will run on next logon.
**********************
PowerShell transcript end
End time: 20251210024601
**********************


**********************
PowerShell transcript start
Start time: 20251210211404
Username: DESKTOP-SCCHLR9\Administrator
RunAs User: DESKTOP-SCCHLR9\Administrator
Configuration Name: 
Machine: DESKTOP-SCCHLR9 (Microsoft Windows NT 10.0.19045.0)
Host Application: C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\pwsh.dll -ExecutionPolicy Bypass -NoLogo -NonInteractive -File C:\Windows\Setup\Scripts\root.core.ps1
Process ID: 1456
PSVersion: 7.5.4
PSEdition: Core
GitCommitId: 7.5.4
OS: Microsoft Windows 10.0.19045
Platform: Win32NT
PSCompatibleVersions: 1.0, 2.0, 3.0, 4.0, 5.0, 5.1, 6.0, 7.0
PSRemotingProtocolVersion: 2.3
SerializationVersion: 1.1.0.1
WSManStackVersion: 3.0
**********************
[INFO ] Transcript started at 'C:\Users\Administrator\Desktop\FirstBoot-20251210-211404.log'.
[INFO ] Detected RootPhase=0.
[INFO ] === Step: Confirm administrator token ===
[INFO ] Administrator privileges confirmed.
[INFO ] === Step 'Confirm administrator token' completed ===
[INFO ] === Step: Configure Defender and firewall ===
[INFO ] Configuring Microsoft Defender Antivirus preferences...
Write-Error: C:\Windows\Setup\Scripts\root.core.ps1:394
Line |
 394 |          Write-LogError "Failed to set Defender preferences: $($_.Exce …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to set Defender preferences: The term 'Set-MpPreference' is not recognized as a name of a cmdlet, function, script file, or executable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
Write-LogError: C:\Windows\Setup\Scripts\root.core.ps1:394
Line |
 394 |          Write-LogError "Failed to set Defender preferences: $($_.Exce …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to set Defender preferences: The term 'Set-MpPreference' is not recognized as a name of a cmdlet,
     | function, script file, or executable program. Check the spelling of the name, or if a path was included, verify
     | that the path is correct and try again.

[INFO ] Windows Defender policy keys written (DisableAntiSpyware/DisableAntiVirus/Real-Time Protection).
[INFO ] Adding Defender exclusion paths: C:\Windows\Setup\Scripts; C:\Windows\Setup\Scripts\Payloads; C:\Users\Administrator\Downloads
Write-Error: C:\Windows\Setup\Scripts\root.core.ps1:452
Line |
 452 |          Write-LogError "Failed to configure Defender exclusions: $($_ …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to configure Defender exclusions: The term 'Add-MpPreference' is not recognized as a name of a cmdlet, function, script file, or executable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
Write-LogError: C:\Windows\Setup\Scripts\root.core.ps1:452
Line |
 452 |          Write-LogError "Failed to configure Defender exclusions: $($_ …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to configure Defender exclusions: The term 'Add-MpPreference' is not recognized as a name of a
     | cmdlet, function, script file, or executable program. Check the spelling of the name, or if a path was included,
     | verify that the path is correct and try again.

Write-Error: C:\Windows\Setup\Scripts\root.core.ps1:503
Line |
 503 |          Write-LogError "Failed to query Defender status: $($_.Excepti …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to query Defender status: The term 'Get-MpPreference' is not recognized as a name of a cmdlet, function, script file, or executable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
Write-LogError: C:\Windows\Setup\Scripts\root.core.ps1:503
Line |
 503 |          Write-LogError "Failed to query Defender status: $($_.Excepti …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to query Defender status: The term 'Get-MpPreference' is not recognized as a name of a cmdlet,
     | function, script file, or executable program. Check the spelling of the name, or if a path was included, verify
     | that the path is correct and try again.

[INFO ] Disabling all Windows Firewall profiles...
[INFO ] Firewall profiles disabled.
[INFO ] Firewall profile status: Name=Domain, Enabled=False
[INFO ] Firewall profile status: Name=Private, Enabled=False
[INFO ] Firewall profile status: Name=Public, Enabled=False
[INFO ] === Step 'Configure Defender and firewall' completed ===
[INFO ] === Step: Configure SmartScreen and UAC ===
[INFO ] Disabling SmartScreen for Explorer and Edge...
[INFO ] Set Explorer SmartScreenEnabled=Off.
[INFO ] Set Edge SmartScreenEnabled=0.
[INFO ] Set System EnableSmartScreen=0.
[INFO ] Disabling UAC and elevation prompts...
[INFO ] Set UAC policy: EnableVirtualization=0
[INFO ] Set UAC policy: ValidateAdminCodeSignatures=0
[INFO ] Set UAC policy: EnableSecureUIAPaths=0
[INFO ] Set UAC policy: EnableLUA=0
[INFO ] Set UAC policy: EnableUIADesktopToggle=1
[INFO ] Set UAC policy: ConsentPromptBehaviorAdmin=0
[INFO ] Set UAC policy: FilterAdministratorToken=0
[INFO ] Set UAC policy: EnableInstallerDetection=0
[INFO ] Set UAC policy: ConsentPromptBehaviorUser=0
[INFO ] Set UAC policy: PromptOnSecureDesktop=0
[INFO ] === Step 'Configure SmartScreen and UAC' completed ===
[INFO ] === Step: Register second-phase RunOnce ===
[INFO ] Registered RunOnce entry 'WindowsInit-Phase2' that replays the root.ps1 loader for phase 2.
[INFO ] RootPhase set to 1 in registry.
[INFO ] === Step 'Register second-phase RunOnce' completed ===
[INFO ] === Step: Run Defender.Remover (optional) ===
[INFO ] Running Defender Remover Script_Run.bat in silent mode with option 'Y' (full Defender removal)...
[INFO ] Script_Run.bat exited with code 0. System may have been scheduled for reboot.
[INFO ] === Step 'Run Defender.Remover (optional)' completed ===
[INFO ] Phase 1 (Defender removal) invoked. System may reboot automatically; remaining configuration will run on next logon.
**********************
PowerShell transcript end
End time: 20251210211412
**********************



**********************
PowerShell transcript start
Start time: 20251210211514
Username: DESKTOP-SCCHLR9\Administrator
RunAs User: DESKTOP-SCCHLR9\Administrator
Configuration Name: 
Machine: DESKTOP-SCCHLR9 (Microsoft Windows NT 10.0.19045.0)
Host Application: C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\pwsh.dll -ExecutionPolicy Bypass -NoLogo -NonInteractive -File C:\Windows\Setup\Scripts\root.core.ps1
Process ID: 8076
PSVersion: 7.5.4
PSEdition: Core
GitCommitId: 7.5.4
OS: Microsoft Windows 10.0.19045
Platform: Win32NT
PSCompatibleVersions: 1.0, 2.0, 3.0, 4.0, 5.0, 5.1, 6.0, 7.0
PSRemotingProtocolVersion: 2.3
SerializationVersion: 1.1.0.1
WSManStackVersion: 3.0
**********************
[INFO ] Transcript started at 'C:\Users\Administrator\Desktop\FirstBoot-20251210-211514.log'.
[INFO ] Detected RootPhase=1.
[INFO ] Non-zero RootPhase detected; skipping dedicated Defender removal phase.
[INFO ] === Step: Install PowerShell 7.5.4 ===
[INFO ] PowerShell 7 already present at 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\pwsh.exe'; skipping MSI installation.
[INFO ] === Step 'Install PowerShell 7.5.4' completed ===
[INFO ] === Step: Configure PowerShell defaults ===
[INFO ] Configured Windows PowerShell profile to forward interactive sessions to PowerShell 7.
[INFO ] === Step 'Configure PowerShell defaults' completed ===
[INFO ] === Step: Set execution policies ===

[INFO ] Set Windows PowerShell execution policies to Bypass for CurrentUser and LocalMachine.
[INFO ] Set current-engine execution policy: CurrentUser = Bypass.
PS>TerminatingError(Set-ExecutionPolicy): "Access to the path 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\powershell.config.json' is denied.
To change the execution policy for the default (LocalMachine) scope, start PowerShell with the "Run as administrator" option. To change the execution policy for the current user, run "Set-ExecutionPolicy -Scope CurrentUser"."
Write-Error: C:\Windows\Setup\Scripts\root.core.ps1:237
Line |
 237 |          Write-LogError "Failed to set current-engine execution policy …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to set current-engine execution policy for LocalMachine: Access to the path 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\powershell.config.json' is denied.
Write-LogError: C:\Windows\Setup\Scripts\root.core.ps1:237
Line |
 237 |          Write-LogError "Failed to set current-engine execution policy …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Failed to set current-engine execution policy for LocalMachine: Access to the path 'C:\Program
     | Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\powershell.config.json' is denied.

[INFO ] === Step 'Set execution policies' completed ===
[INFO ] === Step: Install Windows Terminal ===
[INFO ] Windows Terminal bundle: 'C:\Windows\Setup\Scripts\WindowsTerminal\47c42ab59d47421a89290c85b705f6ff.msixbundle'
[INFO ] Windows Terminal license: 'C:\Windows\Setup\Scripts\WindowsTerminal\47c42ab59d47421a89290c85b705f6ff_License1.xml'
[INFO ] Provisioning Windows Terminal as an Appx provisioned package (Online)...
PS>TerminatingError(Add-AppxProvisionedPackage): "没有注册类
"
Write-Error: C:\Windows\Setup\Scripts\root.core.ps1:314
Line |
 314 |          Write-LogError "Add-AppxProvisionedPackage for Windows Termin …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Add-AppxProvisionedPackage for Windows Terminal failed: 没有注册类
Write-LogError: C:\Windows\Setup\Scripts\root.core.ps1:314
Line |
 314 |          Write-LogError "Add-AppxProvisionedPackage for Windows Termin …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Add-AppxProvisionedPackage for Windows Terminal failed: 没有注册类 

[INFO ] Installing Windows Terminal for the current user via Add-AppxPackage...
PS>TerminatingError(Import-Module): "Operation is not supported on this platform. (0x80131539)"
WARNING: [WARN ] Add-AppxPackage on this system does not support -LicensePath; installing without license file.
PS>TerminatingError(Import-Module): "Operation is not supported on this platform. (0x80131539)"
Write-LogError: C:\Windows\Setup\Scripts\root.core.ps1:342
Line |
 342 |          Write-LogError "Add-AppxPackage for Windows Terminal failed:  …
     |          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | [ERROR] Add-AppxPackage for Windows Terminal failed: The 'Add-AppxPackage' command was found in the module
     | 'Appx', but the module could not be loaded due to the following error: [Operation is not supported on this
     | platform. (0x80131539)] For more information, run 'Import-Module Appx'.

[INFO ] === Step 'Install Windows Terminal' completed ===
[INFO ] === Step: Set Windows Terminal as default host ===
[INFO ] Default console host configured to Windows Terminal (AUMID='Microsoft.WindowsTerminal_8wekyb3d8bbwe!App').
[INFO ] === Step 'Set Windows Terminal as default host' completed ===
[INFO ] === Step: Configure memory and DMA optimization ===
[INFO ] Configuring memory and DMA optimization...
[INFO ] Memory compression disabled via MMAgent.
[INFO ] Set DisablePageCombining=1
[INFO ] SysMain service disabled.
[INFO ] Set ASPMOptOut=1 (ASPM disabled)
[INFO ] Set PCIe CompletionTimeout=0x6 (65ms-210ms range)

[INFO ] Activated Ultimate Performance power plan: f572ce20-8562-49d3-af54-69342901fa20





[INFO ] Power plan optimizations applied.
[INFO ] Network throttling disabled.
[INFO ] TCP parameters configured.
[INFO ] Nagle algorithm disabled on network interfaces.
[INFO ] Memory and DMA optimization configuration completed.
[INFO ] === Step 'Configure memory and DMA optimization' completed ===
[INFO ] === Step: Copy payloads to Downloads ===
[INFO ] Copied directory payload 'Defender_Control_2.1.0_Single' to Downloads.
[INFO ] Copied directory payload 'Sunshine' to Downloads.
[INFO ] Copied file payload '7z2501-x64.exe' to Downloads.
[INFO ] Copied file payload '581.57-desktop-win10-win11-64bit-international-dch-whql.exe' to Downloads.
[INFO ] Copied file payload 'Kook_PC_Setup_v0.99.0.0.exe' to Downloads.
[INFO ] Copied file payload 'MSIAfterburner-64-4.6.5.exe' to Downloads.
[INFO ] Copied file payload 'QQ9.7.25.29411.exe' to Downloads.
[INFO ] Copied file payload 'Set-GpuDeviceDesc.ps1' to Downloads.
[INFO ] Copied file payload 'ShareX-17.1.0-setup.exe' to Downloads.
[INFO ] Copied file payload 'SteamSetup.exe' to Downloads.
[INFO ] Copied file payload 'uuyc_4.8.2.exe' to Downloads.
[INFO ] Copied file payload 'VC_redist.x64.exe' to Downloads.
[INFO ] Copied file payload 'VC_redist.x86.exe' to Downloads.
[INFO ] === Step 'Copy payloads to Downloads' completed ===
[INFO ] === Step: Install core applications ===
[INFO ] Installing 7-Zip from 'C:\Windows\Setup\Scripts\Payloads\7z2501-x64.exe'...
[INFO ] 7-Zip installation completed with exit code 0.
[INFO ] Installing NVIDIA driver from 'C:\Windows\Setup\Scripts\Payloads\581.57-desktop-win10-win11-64bit-international-dch-whql.exe' (silent, clean)...
[INFO ] NVIDIA driver installer exited with code 0.
[INFO ] Starting Steam silent installer in background from 'C:\Windows\Setup\Scripts\Payloads\SteamSetup.exe'...
[INFO ] Steam installer started with PID 9200; not waiting for completion.
[INFO ] Installing Visual C++ Redistributable x64 from 'C:\Windows\Setup\Scripts\Payloads\VC_redist.x64.exe'...
[INFO ] Visual C++ Redistributable x64 installation completed with exit code 0.
[INFO ] Installing Visual C++ Redistributable x86 from 'C:\Windows\Setup\Scripts\Payloads\VC_redist.x86.exe'...
[INFO ] Visual C++ Redistributable x86 installation completed with exit code 0.
[INFO ] === Step 'Install core applications' completed ===
[INFO ] === Step: Invoke user customization script ===
[INFO ] User customization script 'C:\Windows\Setup\Scripts\UserCustomization.ps1' not found; skipping.
[INFO ] === Step 'Invoke user customization script' completed ===
[INFO ] RootPhase set to 2 in registry.
**********************
PowerShell transcript end
End time: 20251210212134
**********************
