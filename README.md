# QuickNetRecovery —— Windows 网络故障自检与自愈工具

**分层排查 + 智能匹配修复策略，快速恢复网络连接**。

## 核心能力

- **完整诊断链**：外网基线之外，逐项执行图片中的硬件、连接、DHCP、DNS、HOSTS、LSP、IE 代理和环境变量检查
- **自动配对修复**：根据检查结果推荐对应的修复动作，支持一键执行全部已推荐项
- **三种运行模式**：交互式修复、无人值守安全修复、仅诊断不修复
- **代理失效联动**：实际测试代理端口和经代理的 HTTPS 访问；确认失效且存在 Meta Tunnel / Meta Channel 时，按配置联动移除设备
- **安全保护措施**：hosts 修改前自动创建备份，修复后二次连通性验证
- **运行日志**：完整记录排查与修复全过程到 `logs/`，方便回溯
- **桌面快捷方式**：双击桌面的“网络快速修复”即可启动，并自动申请管理员权限

## 目录与模块

```
NetQuickFix/
├── netfix.ps1                     # 主调度脚本
├── netfix.config.json             # 用户自定义配置
├── install_task.ps1               # 事件驱动计划任务安装/卸载
├── install_shortcut.ps1           # 桌面快捷方式创建/移除
├── logs/                           # 运行日志（首次运行时自动创建）
├── diagnostics/                   # 基线连通性 + 8 项专项诊断
│   ├── diag_connectivity.ps1      # Internet 直连基线
│   ├── diag_hardware.ps1          # 1. 网卡、链路、设备管理器状态
│   ├── diag_network.ps1           # 2. IP、路由、网关可达性
│   ├── diag_dhcp.ps1              # 3. DHCP 服务与租约
│   ├── diag_dns.ps1               # 4. DNS 服务、服务器与解析
│   ├── diag_hosts.ps1             # 5. HOSTS 语法、冲突与目标覆盖
│   ├── diag_lsp.ps1               # 6. Winsock/LSP 目录完整性
│   ├── diag_proxy.ps1             # 7. IE/PAC/WinHTTP/环境代理实测
│   └── diag_environment.ps1       # 8. 系统及代理环境变量
├── tests/                         # 无破坏诊断与联动回归测试
└── repairs/                       # 8 项修复组件
    ├── repair_remove_meta_tunnel.ps1  # 移除虚拟隧道适配器
    ├── repair_enable_adapter.ps1      # 激活被停用的网卡
    ├── repair_renew_dhcp.ps1          # 强制刷新 DHCP 地址租约
    ├── repair_reset_winsock.ps1       # 重建 Winsock 与 IP 协议栈
    ├── repair_clear_proxy.ps1         # 关闭系统级代理及 WinHTTP 代理
    ├── repair_reset_dns.ps1           # 还原 DNS 为自动获取
    ├── repair_restart_services.ps1    # 重启关键 Windows 网络服务
    └── repair_fix_hosts.ps1           # 审查并清理 hosts 异常条目
```

### 诊断项目说明

| 项目 | 检查范围 |
| ---- | -------- |
| 连通性基线 | 对配置目标执行 DNS + TCP 443 直连测试；无论结果如何都会继续后续诊断 |
| 网络硬件配置 | 物理网卡启用状态、媒体链路、设备管理器错误码、Meta 设备识别 |
| 网络连接配置 | IPv4 地址、APIPA、默认路由、网关 ICMP 可达性、重复本机地址 |
| DHCP 服务 | DHCP Client 服务状态、启用 DHCP 的活动网卡及有效租约 |
| DNS 服务 | DNS Client 服务、服务器逐一查询、目标域名系统解析 |
| HOSTS 文件 | 文件可读性、语法、冲突映射、检测目标是否被本机地址阻断 |
| LSP 协议 | Winsock Catalog 可读性、核心提供程序、协议链和提供程序 DLL |
| IE 代理 | IE 固定代理、PAC/自动检测、WinHTTP 和环境代理；测试端口及实际 HTTPS 访问 |
| 环境变量 | HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/NO_PROXY 及关键系统路径 |

## 使用入门

### 前置条件

- Windows 10 / Windows 11
- PowerShell 5.1+
- 管理员身份（脚本会自动申请提权）

### 基本用法

1. **获取项目**

```bash
git clone https://github.com/your-username/NetQuickFix.git
cd NetQuickFix
```

2. **推荐：从桌面启动**

首次执行以下命令创建桌面快捷方式：

```powershell
.\install_shortcut.ps1
```

以后双击桌面的 **网络快速修复** 即可。快捷方式始终指向当前项目文件，不会生成额外代码副本。需要移除时执行：

```powershell
.\install_shortcut.ps1 -Remove
```

3. **直接启动脚本**

右键 `netfix.ps1` → **使用 PowerShell 运行**，或在管理员终端内：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\netfix.ps1
```

4. **选择执行策略**

默认以交互模式启动。也可通过命令行参数直接指定：

```powershell
# 自动模式（无人值守）
.\netfix.ps1 -RunAs auto

# 交互模式（默认）
.\netfix.ps1 -RunAs interactive

# 仅诊断，不执行任何修复
.\netfix.ps1 -RunAs diagnostics
```

或者修改 `netfix.config.json` 中的默认模式：

```json
{
    "run_mode": "auto"
}
```

### 事件驱动自动修复

执行 `install_task.ps1` 可在 Windows 计划任务库中注册一个触发器任务，**一旦系统检测到网络断开即自动执行诊断修复**：

```powershell
# 注册计划任务（需要管理员权限）
.\install_task.ps1

# 移除计划任务
.\install_task.ps1 -Remove
```

任务属性：

- **名称**: `NetworkDisconnectRunScript`
- **触发源**: `Microsoft-Windows-NetworkProfile/Operational` 通道中 `Microsoft-Windows-NetworkProfile` 事件 ID 10001（表示网络断开）
- **运行身份**: `SYSTEM`，拥有最高权限

### 交互式操作流程

1. 启动后自动完成连通性基线和全部 8 项专项诊断
2. 输出检测摘要，标注所有发现的问题及对应的修复建议
3. 输入编号选择要执行的修复项（支持逗号分隔多选），或输入 `A` 一键执行全部
4. 修复完成后自动验证网络是否恢复

### 自动模式操作流程

1. 完整运行全部诊断
2. 只执行“错误”级别问题匹配到的修复动作
3. 打印修复结果和连通性验证

正常工作的代理和正常存在的 Meta 网卡不会被修改。只有代理端点本身不可达，或直连正常但经代理访问全部失败，并且确实找到匹配的 Meta Tunnel / Meta Channel 设备时，才会生成设备移除修复。若直连与代理同时失败，则视为全局断网，不会贸然删除 Meta 设备；该联动也可通过配置关闭。

## 配置项说明

`netfix.config.json` 可选参数：

| 参数              | 类型     | 含义                                                     |
| ----------------- | -------- | -------------------------------------------------------- |
| `run_mode`      | string   | 执行策略：`"interactive"`（交互）、`"auto"`（自动）或 `"diagnostics"`（仅诊断） |
| `check_targets` | string[] | 连通探测时的目标站点                                     |
| `proxy_timeout_ms` | int | 单次代理端口及 HTTPS 测试超时，允许 500–30000 毫秒 |
| `remove_meta_on_proxy_failure` | bool | 代理确认失效时是否推荐/自动执行 Meta 设备移除 |
| `meta_adapter_patterns` | string[] | 用于识别 Meta Tunnel / Meta Channel 名称的正则表达式 |
| `repair_order`  | string[] | 修复动作的执行优先级                                     |
| `log_enabled`   | bool     | 是否启用日志输出到文件                                   |

## 注意事项

- 修复操作会修改操作系统级别的网络设置，请先了解每个修复步骤的具体含义再执行
- `repair_reset_winsock` 和 `repair_reset_dns` 这两项执行后建议重启系统以确保完全生效
- hosts 文件修复将自动保留备份，备份件存放于 `C:\Windows\System32\drivers\etc\` 目录下
- Meta 修复使用设备的 PNP Instance ID 调用 `pnputil /remove-device`，只移除匹配设备，不删除驱动包
- `-RunAs` 命令行参数优先于 `netfix.config.json` 中的 `run_mode`

## 许可证

[MIT License](LICENSE)
