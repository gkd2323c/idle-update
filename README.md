# idle-update

当系统空闲时，自动通过 winget、choco、scoop 更新软件。

## 功能

- 检测系统空闲时间（键盘/鼠标无操作），达到阈值后自动触发
- 依次调用 winget → choco → scoop 执行升级
- 支持冷却时间，避免短时间内重复更新
- 所有操作记录到日志文件

## 安装

```powershell
.\setup.ps1
```

首次运行会注册到注册表 `HKCU\Run`，下次登录自动启动。无需管理员权限。

可选参数：

```powershell
.\setup.ps1 -IdleMinutes 10 -CooldownHours 6   # 自定义阈值
.\setup.ps1 -Remove                              # 卸载
```

## 使用

```powershell
# 仅列出更新不安装（测试用）
.\auto-update.ps1 -RunOnce -DryRun

# 立即执行一次完整更新
.\auto-update.ps1 -RunOnce

# 前台持续运行
.\auto-update.ps1

# 后台静默运行
双击 run-silent.vbs
```

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-IdleMinutes` | 10 | 空闲多少分钟后触发更新 |
| `-CheckInterval` | 30 | 空闲检测间隔（秒） |
| `-CooldownHours` | 6 | 两次更新最少间隔小时数 |
| `-RunOnce` | false | 执行一次后退出 |
| `-DryRun` | false | 仅列出更新，不安装 |

## 日志

日志按日期写入 `logs\autoupdate-yyyy-MM-dd.log`，格式：

```
2026-05-02 12:00:00 [INFO] System idle for 10 min. Running updates...
2026-05-02 12:01:30 [INFO] winget exited with code 0
```

## 依赖

至少安装以下包管理器之一：

- [winget](https://github.com/microsoft/winget-cli)（Windows 10/11 自带）
- [chocolatey](https://chocolatey.org/install)
- [scoop](https://scoop.sh/)
