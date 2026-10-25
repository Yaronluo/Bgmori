# Bgmori 白底漫画图标

当前图标：纯白底、黑白线描的软萌女性角色。使用普通 PNG appiconset，没有玻璃、渐变、圆形底片、高光或人造阴影。

- `bgmori-white-original.png`：内置 image_gen 根据已选少女线稿生成的白底图稿。
- `bgmori-white.png`：1024 像素不透明 iOS 图标。
- `bgmori-white-mac.png`：Mac 预览，纯白圆角图标和标准透明边距。
- `source/mascot-lineart.png`：已选角色的原始透明线稿。
- `Bgmori/Resources/Assets.xcassets/AppIconFlat.appiconset`：项目实际使用的图标集合。
- `scripts/generate-flat-icons.swift`：用系统 CoreGraphics 适配各平台的像素尺寸与外形，不添加材质效果。
- `archive/`：本地保留的旧图标草稿，不入库，也不参与应用构建。

在仓库根目录运行以下命令，可重新生成全部图标尺寸：

```bash
swift scripts/generate-flat-icons.swift
```

## 本次编辑提示词

方式：内置 image_gen，引用已选角色线稿，关闭透明背景。

> Edit target: the supplied black-and-white cute anime girl line-art cutout. Make the finished FLAT app icon by placing this EXACT same drawing centered on a completely uniform pure WHITE (#FFFFFF) square canvas. Preserve the girl's identity, expression, pose, hair silhouette and precise linework as faithfully as possible. Scale the supplied square drawing to approximately 78% of the final square canvas, centered both horizontally and vertically, leaving generous plain white margin. The entire background from edge to edge must be exactly pure white, with no gray tint, gradient, texture, vignetting or lighting. The hair and face stay white with black outlines, keeping the illustration black-and-white. No glass, no Liquid Glass, no highlights around the icon tile, no bevel, no circular plate, no border, no drop shadow, no 3D, no rounded corners baked into the canvas, no text or extra decoration. It must look like a simple cute manga line drawing printed on plain white paper. Exact square, opaque background. Do not invent another character or change the artwork design.

## 验证

iOS 与 macOS Debug 构建通过，安装产物使用 `AppIconFlat`。iPhone 桌面图标点击启动测试通过；Mac 已重新安装并重启，运行进程的图标核对为白底平面图稿。
