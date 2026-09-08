<div align="center">

<img src="docs/images/logo.png" width="100" alt="Herden sheep logo" />

# Herden

**让 coding agent 持续运行的终端 runtime，并配有原生 iPhone 控制台。**

[安装 Host](#安装-host) · [配对 iPhone](#配对-iphone) · [Host 指南](docs/guides/install-host.md) · [构建 iOS 应用](docs/guides/build-ios.md)

[![iOS CI](https://github.com/3loc/herden/actions/workflows/ci.yml/badge.svg)](https://github.com/3loc/herden/actions/workflows/ci.yml)
[![Linux CI](https://github.com/3loc/herden/actions/workflows/ci-linux.yml/badge.svg)](https://github.com/3loc/herden/actions/workflows/ci-linux.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/3loc/herden?style=flat)](https://github.com/3loc/herden/stargazers)

[English](./README.md) | 简体中文

</div>

Herden 是 coding agent 的持久化 runtime。它在你控制的电脑上保留 Agent
的终端、工作区和进程，即使没有客户端连接也会继续运行。原生 iPhone 应用
连接到 Herden Host，而不是直接连接 Claude Code 或 Codex。

本项目结合了 [herdr](https://github.com/herdrdev/herdr) 和
[Heeler](https://github.com/ZingerLittleBee/Heeler)。Rust runtime、CLI、工作区
模型和 socket API 以 herdr 为基础。Herden 加入原生 iPhone 控制台，并把安全
配对做成 Host 的内置功能。

如果你熟悉 herdr，使用方式很简单：原来运行 `herdr` 的地方改为运行
`herden`，要添加 iPhone 时运行 `herden pair`。

## 与上游相比的主要变化

- **统一的 Herden 产品：** Host runtime 和 iOS 控制台在同一个仓库维护。
  公共命令、状态路径、socket 和界面文案都使用 Herden 名称。
- **内置配对：** `herden pair` 生成短期、单次使用的 Bootstrap Key，并直接
  在终端显示 Pairing Code。配对不需要 Node、插件操作或 Herden 账户。
- **原生 iOS 控制台：** SwiftUI 应用使用 libghostty 渲染真实终端，通过仓库
  内的 HerdenSSH 实现连接 Host。支持直接输入、听写、文件上传和 Host 切换。
- **SSH 传输：** API 通过 OpenSSH direct-streamlocal 连接 Unix socket，交互
  终端通过带 PTY 的 exec channel 连接。没有中心应用服务器，也不需要 socat。
- **私有网络优先：** 推荐使用 Tailscale 或 Headscale，但任何能够访问普通
  OpenSSH 的网络路径都可以使用。
- **通知可选：** Node Host 扩展和无状态 Push Relay 提供端到端加密的 APNs
  通知。配对和终端访问不依赖它们。
- **兼容性优先：** 为避免破坏现有客户端和集成，部分 `HERDR_*` 环境变量和
  wire 标识会继续保留。它们是兼容接口，不是产品名称。

Herden Host 从未经修改的 herdr 0.8.2 开始开发。准确的来源 commit 记录在
[runtime/UPSTREAM.md](runtime/UPSTREAM.md)。

## 上游策略

- **Heeler 只作为历史来源。** Herden 保留其 iOS 基础和归属说明，但不计划
  持续合并或追踪后续 Heeler 开发。
- **herdr 是 Host 的活跃上游。** Herden 尽量缩小 runtime 差异，让上游更新
  容易审查和采用。

目前仓库在 GitHub 上是独立项目，并把 herdr 放在 `runtime/` 下，因此不能使用
GitHub 的 **Sync fork** 按钮。启用该工作流需要把仓库迁移成真正的 herdr fork，
并采用兼容的默认分支历史和目录结构。这不影响公开发布 Herden；Host 更新目前
采用明确、经过审查的导入方式。

## 安装 Host

在 Linux 或 macOS Host 上运行：

```sh
curl -fsSL https://raw.githubusercontent.com/3loc/herden/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
herden
```

安装器会选择当前系统和 CPU 对应的 release binary，验证 SHA-256 后安装到
`~/.local/bin`。源码构建方式见 [Host 指南](docs/guides/install-host.md#build-from-source)。

## 配对 iPhone

iPhone 必须能访问 Host 的普通 OpenSSH 服务。推荐使用 Tailscale 或 Headscale，
不需要开放公网路由器端口。

在 Host 的普通 shell 中运行：

```sh
herden pair
```

然后在 iPhone 上打开 **Herden → Hosts → Add Host**，扫描 Pairing Code，并确认
Host 指纹。配对码两分钟后过期，且只能添加一台手机。添加另一台设备时重新
运行命令即可。

## 安装 iPhone 应用

构建原生 iOS 应用需要安装 Xcode 26 或更高版本的 Mac。Simulator 不需要付费
Apple 会员；真机版本需要开发团队，以及属于该团队的 App Group。

```sh
git clone https://github.com/3loc/herden.git
cd herden
make sim
```

签名、真机安装和 Wi-Fi 部署见 [iOS 构建指南](docs/guides/build-ios.md)。

## 开发

```sh
make help          # 查看所有任务
make host-check    # 检查 Host 构建依赖
make host-install  # 构建并安装 Host
make sim           # 在 Simulator 中构建并启动 iOS 应用
make test          # 运行 iOS 和 HerdenSSH 测试
```

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。隐私和通知的安全边界见
[PRIVACY.md](PRIVACY.md)。

## 来源和许可证

Heeler 的贡献者在
[issue #282](https://github.com/ZingerLittleBee/Heeler/issues/282) 中批准了
Apache-2.0 重新许可，该 commit 已保留在 Herden 历史中。完整来源记录和维护
策略见 [UPSTREAM.md](UPSTREAM.md)。整个 Herden 仓库采用
[Apache License 2.0](LICENSE)。
