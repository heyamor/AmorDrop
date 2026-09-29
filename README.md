# AmorDrop

适用于 Apple Silicon Mac 的原生文件暂存架，基于 [Dropshit](https://github.com/iamsumanp/Dropshit)。

[下载 macOS 15.6+ 预览版（DMG）](https://github.com/heyamor/AmorDrop/releases/download/amordrop-preview-macos15.6-1.2.0/AmorDrop-macOS15.6-arm64-preview-1.2.0.dmg) · [所有版本](https://github.com/heyamor/AmorDrop/releases)

## 功能

- 拖住 Finder 文件并晃动指针呼出 Shelf；可暂存文件、文件夹、图片和 PDF
- 多个 Shelf、继续追加、贴边停靠，并支持多项拖出到 Finder 或其他 App
- Quick Look、创建 ZIP、转换图片格式
- 菜单栏入口和全局快捷键 `Control-Option-Space`
- Mac 控制：保持唤醒、电源或 App 触发、低电量保护、键盘清洁锁

## 安装

需要 Apple Silicon（M 系列）和 macOS 15.6 或更高版本。此版本尚未在 macOS 15.6 实机验证。下载 DMG，打开后将 AmorDrop.app 拖到 Applications 文件夹。

此预览版使用本机临时签名，未经 Apple 公证，也没有 Developer ID。首次打开若被 macOS 拦截，请先确认 DMG 来自本仓库，再到「系统设置 → 隐私与安全性」选择「仍要打开」。不要关闭 Gatekeeper。

### 更新

应用不会自动更新。请从上方 Releases 下载最新版 DMG，退出 AmorDrop，将新版本拖入 Applications，并在提示时选择「替换」。Shelf 与设置数据保存在应用之外，替换 App 不会清除它们。朋友的 Mac 需要 Apple Silicon 和 macOS 15.6 或更高版本。

## 使用

1. 在 Finder 中拖住文件，晃动指针呼出 Shelf，再将文件放入。
2. 将更多文件拖到 Shelf 可继续追加；从 Shelf 拖出一项或多项即可放到目标 App。
3. 选中项目后按空格键预览。使用 `Control-Option-Space` 呼出或创建 Shelf。

从 Finder 放入的文件仍保存在原位置。清空 Shelf 会移除条目及 AmorDrop 自己创建的临时文件，不会删除源文件。应用不提供账号、云上传、遥测或自动更新。

键盘清洁锁需要 macOS 的输入监控权限。合盖保持运行需要单独设置特权辅助组件和管理员授权；该功能仍属实验性能力，可能增加耗电和发热。

## 从源码构建

需要 Xcode 27。运行：

```sh
bash scripts/build-private-app.sh
xcrun swift test -c release
```

## 许可证

本项目基于 [Dropshit](https://github.com/iamsumanp/Dropshit)，保留原作者 Suman Pokharel 的署名。许可证文本见 [LICENSE](LICENSE)。
