# AmorDrop

AmorDrop 是一款供个人使用的原生 macOS 文件暂存架，基于 Suman Pokharel 的 [Dropshit](https://github.com/iamsumanp/Dropshit)。它保留了原项目的 SwiftUI/AppKit 搁架和拖放实现，移除了自动更新器，并为这台 Mac 使用本地 App 应用包。

## 使用方法

- 在 Finder 中拖住文件并晃动指针，呼出搁架，然后将文件放到搁架上。
- 将更多文件、文件夹、图片、PDF 或文本拖到已打开的搁架中。
- 将搁架中的一个或多个项目拖到 Finder 或其他 App 的接收区域。
- 选中项目后按空格键使用 Quick Look 预览。搁架操作还支持创建 ZIP 和转换图片格式。
- 点击菜单栏图标可新建搁架并打开设置。在任意位置按 Control-Option-Space 可创建搁架。
- 如果没有可见窗口，从 Finder 再次打开 AmorDrop 会呼出一个搁架。
- 搁架会在多次启动之间保留。搁架过期时间默认为“永不”。

## 构建与安装

需要完整安装 Xcode 27，并使用匹配的 Swift 工具链和 macOS 27 SDK。本版本仅面向 Apple Silicon。在项目目录中运行：

```sh
bash scripts/build-private-app.sh
```

此脚本会构建 `build/AmorDrop.app`，其 Bundle Identifier 为 `com.amor.personal.amordrop`，仅显示在菜单栏，并使用本机临时签名。签名过程会在专用临时目录中进行，避免 Documents 文件提供器的元数据干扰签名。安装时，将 App 拷贝到 `/Applications` 后打开即可。搁架和快捷键不需要 Developer ID、Apple 公证、账号或网络连接。macOS 可能会询问是否允许访问受保护位置中的文件。

## 本机验证记录

在 Xcode 27 下，Release 构建和 44 项 XCTest 测试均通过，安装后的 App 也成功启动。实机检查覆盖了搁架创建、七种测试文件的名称和缩略图、Quick Look、清空、撤销、关闭与重新打开，以及 Finder 复制 → 搁架粘贴 → 从搁架复制 → Finder 粘贴流程，并比对了文件内容哈希。自动化测试覆盖多个搁架、文件承诺安全、ZIP 压缩包、PNG/JPEG 转换和 Shake 手势识别算法。

2026-09-26，用户确认菜单栏图标、实体键盘 Control-Option-Space、Finder 拖住文件时通过 Shake 呼出搁架、Finder → 搁架 → Finder 的真实拖放，以及贴边停靠均正常。之后再次完成 Release 构建，44 项 XCTest 全部通过，且没有修改应用源码。此版本以附注标签 `amordrop-v1.0.0` 冻结为个人版 AmorDrop V1 基线。验证范围和构建产物信息见[基线记录](docs/V1-BASELINE.md)。浏览器上传区域的拖放和长时间睡眠/唤醒行为不在这轮验收范围内。

## 当前仓库状态

`amordrop-v1.0.0` 标签标记了最后一次经人工验收的搁架基线。当前源码还包含尚在开发中的 Mac 控制和外部 App 拖放兼容性改动；这些改动尚未完成 Release 构建、全套测试或实机验收。上文的 44 项测试结果仅适用于 V1 基线。合盖保持运行属于独立的特权功能，启用前需要管理员明确授权。

## 隐私与文件处理

应用不包含数据分析、账号、云端上传或更新服务，也不会发起网络请求。从 Finder 拖入的文件仍保存在原位置，搁架条目只引用这些文件。只有明确选择“移到废纸篓”时，才会将选中的文件移入 macOS 废纸篓。搁架过期只会移除条目，不会删除对应文件；默认关闭过期清理。粘贴的文本片段和图片会使用临时文件保存。

## 上游来源与许可证

上游 README 说明 Dropshit 使用 MIT 许可证，但当前检出的上游版本没有包含 `LICENSE` 文件。本仓库附有标准 MIT 许可证文本，并注明上游作者 Suman Pokharel（GitHub：`iamsumanp`）。上游来源说明也保留在本 README 和 `LICENSE` 文件中。

## 项目范围

这是一个供本机使用的版本。Sparkle、其更新源和发布打包流程已移除。上游源码中仍保留视频转换和 OCR 功能，但它们不属于本项目当前关注的核心使用流程。
