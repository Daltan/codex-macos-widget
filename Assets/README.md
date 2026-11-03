# Visual identity / 视觉资产

## Application icon

`AppIcon.svg` is the editable vector master for this independent project: a mint quota dial, terminal prompt and status dot on a deep ink background. The arc is an identity element, not a live quota measurement. It is not the official Codex app icon.

`AppIcon.svg` 是本项目独立设计的矢量母版：深墨绿底、薄荷绿额度环、命令提示符与状态点。图案不代表实时额度，也不是官方 Codex 应用图标。

Regenerate all ten macOS AppIcon representations from the SVG (full Xcode required):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Scripts/render-icon.swift Assets/AppIcon.svg Sources/App/Assets.xcassets/AppIcon.appiconset
```

Xcode compiles the PNG representations into the native application icon. Both application and widget targets share the template-rendered vector `CodexMark` image set, which follows the system foreground color.

## Codex mark provenance

- Source: [Lobe Icons — codex.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/codex.svg)
- Retrieved: 2026-11-04 (Asia/Shanghai).
- Upstream license: MIT; full notice in [LobeIcons-LICENSE](LobeIcons-LICENSE).
- Original path geometry preserved in `Assets/CodexMark.svg` (width, height and fill normalized for Apple rendering). The shipped image set uses a vector PDF exported through WebKit to avoid CoreSVG path parsing differences..
- The source is a third-party icon collection, not a claim of an official OpenAI brand license. Codex/OpenAI marks belong to their respective owner. This community utility is not affiliated with or endorsed by OpenAI.

Rebuild the Codex vector PDF:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Scripts/render-codex-mark.swift Assets/CodexMark.svg Sources/Core/Assets.xcassets/CodexMark.imageset/codex.pdf
```
