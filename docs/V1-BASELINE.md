# AmorDrop V1 可用基线

冻结日期：2026-09-26。分支：`amor-drop-private`。

Git annotated tag：`amordrop-v1.0.0`，指向新增的 V1 验收文档提交。
应用源码基于 `8be017a951bec1cb06dd7954f2d0cd3c5be62f32`；本轮仅更新本文档与 README，没有修改应用源码、测试、构建脚本或依赖。

## 核心人工验收

由本机使用者实际验收并确认：

| 项目 | 结果 |
|---|---|
| 菜单栏图标 | 正常；使用者已明确补充确认 |
| Control-Option-Space | 正常 |
| Finder 拖住文件后 Shake 呼出 Shelf | 正常 |
| Finder → Shelf → Finder 真实拖放 | 正常 |
| Shelf 贴边停靠 | 正常 |

本轮没有失败项目，因此没有进行功能修复、重构或 UI 修改。保留当前 Shake 与拖放逻辑、参数及交互。

## 自动验证

- 使用完整 Xcode 27.0（27A266a）、Swift 6.4、macOS 27 SDK。
- `bash scripts/build-private-app.sh`：Release 构建成功，仅 arm64。
- 对同一应用源码再次运行全部 Release XCTest：44 项，0 失败，没有修改或跳过测试。
- `/Applications/AmorDrop.app` 严格代码签名验证通过。
- 新构建与现有安装版的可执行文件完全一致，无需重新替换已人工验收的安装版本。
- 可执行文件 SHA-256：`c4ed6988f9c8fa0b2a2c17458439ece7f8ea2ea674f88507eba4d415e2082d32`。

构建产物：`build/AmorDrop.app`。
安装路径：`/Applications/AmorDrop.app`。
Bundle Identifier：`com.amor.personal.amordrop`。

## 冻结范围与维护

该版本适合作为本机日常使用的 AmorDrop V1 基线。无第三方包依赖；没有 Sparkle、遥测、云服务或自动更新。保留上游署名及当前 LICENSE 信息。

当前核心功能不需要再次人工验收。浏览器上传区域拖放、ZIP/图片转换的菜单操作，以及长时间运行、休眠唤醒和多空间等场景并未在本轮新增实机验收，不因本次冻结而标记通过。

后续 UI 或功能修改应在此 tag 之后独立提交。可使用 `git show amordrop-v1.0.0` 查找基线，并从该 tag 创建维护分支；保留该 tag，不移动或覆盖它。

本轮构建和测试日志保存在项目忽略目录 `.build/v1-release-build.log`、`.build/v1-tests.log`，另有任务输出目录中的副本。标签与本文档是长期回溯记录，构建日志不是版本控制的组成部分。
