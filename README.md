# AmorDrop

AmorDrop 是一款原生 macOS 文件暂存架，基于 Suman Pokharel 的 [Dropshit](https://github.com/iamsumanp/Dropshit)。当前预览版面向 Apple Silicon，最低支持 macOS 15.6，供本人和朋友试用。它保留了原项目的 SwiftUI/AppKit 搁架和拖放实现，并移除了自动更新器。

## 使用方法

- 在 Finder 中拖住文件并晃动指针，呼出搁架，然后将文件放到搁架上。
- 将更多文件、文件夹、图片、PDF 或文本拖到已打开的搁架中。
- 将搁架中的一个或多个项目拖到 Finder 或其他 App 的接收区域。
- 选中项目后按空格键使用 Quick Look 预览。搁架操作还支持创建 ZIP 和转换图片格式。
- 点击菜单栏图标可新建搁架并打开设置。在任意位置按 Control-Option-Space 可创建搁架。
- 如果没有可见窗口，从 Finder 再次打开 AmorDrop 会呼出一个搁架。
- 搁架会在多次启动之间保留。搁架过期时间默认为“永不”。

## 构建与安装

需要完整安装 Xcode 27，并使用匹配的 Swift 工具链和 macOS SDK。本版本仅面向 Apple Silicon，最低系统版本为 macOS 15.6。在项目目录中运行：

```sh
bash scripts/build-private-app.sh
```

此脚本会构建 `build/AmorDrop.app`，其 Bundle Identifier 为 `com.amor.personal.amordrop`，仅显示在菜单栏，并使用本机临时签名。签名过程会在专用临时目录中进行，避免 Documents 文件提供器的元数据干扰签名。安装时，将 App 拷贝到 `/Applications` 后打开即可。发布包没有 Developer ID 签名或 Apple 公证；macOS 可能会拦截首次打开。只有确认来源可信时，才在“系统设置 → 隐私与安全性”选择“仍要打开”。

## 本机验证记录

在 Xcode 27 下，`amordrop-v1.0.0` 基线的 Release 构建和 44 项 XCTest 测试通过，且完成了针对 macOS 27 的人工验收。当前 macOS 15.6 兼容预览版的构建与测试状态见对应 GitHub Release；当前主机运行 macOS 27，尚未在 macOS 15.6 实机上完成人工验证。

2026-09-26，用户确认菜单栏图标、实体键盘 Control-Option-Space、Finder 拖住文件时通过 Shake 呼出搁架、Finder → 搁架 → Finder 的真实拖放，以及贴边停靠均正常。之后再次完成 Release 构建，44 项 XCTest 全部通过，且没有修改应用源码。此版本以附注标签 `amordrop-v1.0.0` 冻结为个人版 AmorDrop V1 基线。验证范围和构建产物信息见[基线记录](docs/V1-BASELINE.md)。浏览器上传区域的拖放和长时间睡眠/唤醒行为不在这轮验收范围内。

## 当前仓库状态

`amordrop-v1.0.0` 标签标记了最后一次经人工验收的搁架基线。当前 macOS 15.6 兼容版以预览版发布；Mac 控制与合盖保持运行仍需谨慎试用。合盖保持运行属于独立的特权功能，启用前需要管理员明确授权。macOS 15.6 的实机行为尚未验证。

## 隐私与文件处理

应用不包含数据分析、账号、云端上传或更新服务，也不会发起网络请求。从 Finder 拖入的文件仍保存在原位置，搁架条目只引用这些文件。只有明确选择“移到废纸篓”时，才会将选中的文件移入 macOS 废纸篓。搁架过期只会移除条目，不会删除对应文件；默认关闭过期清理。粘贴的文本片段和图片会使用临时文件保存。

## 上游来源与许可证

上游 README 说明 Dropshit 使用 MIT 许可证，但当前检出的上游版本没有包含 `LICENSE` 文件。本仓库附有标准 MIT 许可证文本，并注明上游作者 Suman Pokharel（GitHub：`iamsumanp`）。上游来源说明也保留在本 README 和 `LICENSE` 文件中。

## 项目范围

这是供本人和朋友试用的私人分支，不是 App Store 或商业发行版本。Sparkle、其更新源和原发布打包流程已移除。上游源码中仍保留视频转换和 OCR 功能，但它们不属于本项目当前关注的核心使用流程。
