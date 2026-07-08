# QuickNetRecovery —— Windows 网络故障自检与自愈工具

**分层排查 + 智能匹配修复策略，快速恢复网络连接**。

## 核心能力

- **层次化诊断**：从外网可达性到操作系统环境，共 5 层递进定位根因
- **自动配对修复**：根据检查结果自动推荐对应的修复动作，支持一键执行全部修复
- **双模式运行**：人工分步确认（交互式）与无人值守自动修复两种策略
- **虚拟网卡专项**：自动识别并移除 Meta Tunnel / TUN / TAP 类干扰适配器
- **安全保护措施**：hosts 修改前自动创建备份，修复后二次连通性验证
- **运行日志**：完整记录排查与修复全过程，方便回溯

## 目录与模块

```
QuickNet/
├── netfix.ps1                     # 主调度脚本
├── netfix.config.json             # 用户自定义配置
├── install_task.ps1               # 事件驱动计划任务安装/卸载
├── diagnostics/                   # 5 层诊断组件
│   ├── diag_connectivity.ps1      # 第 0 层: Internet 连通性探测
│   ├── diag_hardware.ps1          # 第 1 层: 适配器/硬件状态
│   ├── diag_network.ps1           # 第 2 层: IP/DHCP/网关配置
│   ├── diag_dns.ps1               # 第 3 层: DNS 域名解析
│   └── diag_env.ps1               # 第 4 层: 系统代理/服务/Winsock
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

### 诊断层次说明

| 层次    | 组件             | 检查范围                                          |
| ------- | ---------------- | ------------------------------------------------- |
| Layer 0 | 互联网可达性探测 | 对百度 / 新浪 / B 站分别做 DNS + TCP 443 连通测试 |
| Layer 1 | 适配器/硬件检查  | 网卡启用情况、物理链路信号、虚拟适配器扫描        |
| Layer 2 | IP 配置审计      | 默认网关存在性及可达性、DHCP 状态、APIPA 地址     |
| Layer 3 | DNS 解析验证     | DNS 服务器可达性、域名实际解析能力                |
| Layer 4 | 系统环境排查     | 代理设置、关键服务运行状态、LSP/Winsock、hosts    |

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

2. **启动脚本**

右键 `netfix.ps1` → **使用 PowerShell 运行**，或在管理员终端内：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\netfix.ps1
```

3. **选择执行策略**

默认以交互模式启动。也可通过命令行参数直接指定：

```powershell
# 自动模式（无人值守）
.\netfix.ps1 -RunAs auto

# 交互模式（默认）
.\netfix.ps1 -RunAs interactive
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
- **触发源**: `Microsoft-Windows-NetworkProfile/Operational` 通道中 `NetworkProfile` 事件 ID 10001（表示网络断开）
- **运行身份**: `SYSTEM`，拥有最高权限

### 交互式操作流程

1. 启动后自动完成全部 5 层诊断
2. 输出检测摘要，标注所有发现的问题及对应的修复建议
3. 输入编号选择要执行的修复项（支持逗号分隔多选），或输入 `A` 一键执行全部
4. 修复完成后自动验证网络是否恢复

### 自动模式操作流程

1. 完整运行全部诊断
2. 自动执行所有匹配到的修复动作
3. 打印修复结果和连通性验证

## 配置项说明

`netfix.config.json` 可选参数：

| 参数              | 类型     | 含义                                                     |
| ----------------- | -------- | -------------------------------------------------------- |
| `run_mode`      | string   | 执行策略：`"interactive"`（交互）或 `"auto"`（自动） |
| `check_targets` | string[] | 连通探测时的目标站点                                     |
| `repair_order`  | string[] | 修复动作的执行优先级                                     |
| `log_enabled`   | bool     | 是否启用日志输出到文件                                   |

## 注意事项

- 修复操作会修改操作系统级别的网络设置，请先了解每个修复步骤的具体含义再执行
- `repair_reset_winsock` 和 `repair_reset_dns` 这两项执行后建议重启系统以确保完全生效
- hosts 文件修复将自动保留备份，备份件存放于 `C:\Windows\System32\drivers\etc\` 目录下

## 许可证

[MIT License](LICENSE)
