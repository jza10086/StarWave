# 美术与音频来源

## 原创内容
- 战机、敌机、Boss、子弹、爆炸环、星空、轨道甲板、界面图形：本工程 `scripts/main.gd` 以 Godot CanvasItem 绘图 API 实时生成。为本项目原创，无外部素材依赖。
- 音效：`scripts/main.gd` 使用数学波形生成的短提示音，原创。未使用第三方音乐。
- 游戏名称及界面排版：本项目原创。玩法参考纵版弹幕射击类型，不包含东方、雷霆战机或雷电的角色、音乐、图像等资产。

## 字体
- Noto Sans SC Regular，来源 https://github.com/notofonts/noto-cjk ，SIL Open Font License 1.1。
- 字体文件沿用本地现有已许可素材集；完整许可证在 `assets/fonts/LICENSE.txt`，来源说明在 `assets/fonts/SOURCES.md`。

所有运行所需文件均随工程附带，无远程资源请求。

## Neon Geometric 美术改版（2026-10-26）
风格研究参考：Jamesika 的《激射超新星 / SHOOPER NOVA》官方 Steam 商店截图：
- https://store.steampowered.com/app/2853160/SHOOPER_NOVA/
- 官方截图 0：https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2853160/5fd924abd992abd443a289d0f17e106afea3055c/ss_5fd924abd992abd443a289d0f17e106afea3055c.1920x1080.jpg
- 官方截图 1：https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2853160/3deeb4f7067724eb512d5777cd67316156c07bcc/ss_3deeb4f7067724eb512d5777cd67316156c07bcc.1920x1080.jpg

研究时实际查看截图像素，提取深蓝紫空间、发光线框、同心圆、几何碎片与明亮拖尾等通用美术语言。没有复制参考游戏的飞船、角色、Logo、界面布局、贴图或音效；参考截图不随游戏分发。保留本作纵向 STG 与全幅 HUD，不改成参考游戏的圆形塔防玩法。

新版所有几何、背景、光晕、飞船、Boss、碎片和轨迹均由 `scripts/main.gd` 原创程序绘制。第一版曾以多层透明线条模拟辉光；第二版已替换为下述连续渐变方案，兼容 GL Compatibility。敌弹保留实色半径边界；受控光晕不参与判定；空心低透明碎片与危险弹体明确区分。

## 连续渐变 / 柔光精修（2026-10-26）
- 再次逐像素查看上述官方截图，研究柔和蓝紫空间明暗、明亮实体内部、淡出尾迹和软光晕。没有下载或复制参考游戏资产到工程。
- `assets/shaders/deep_space.gdshader`：原创解析 Gaussian 色场与低幅抖动，连续蓝紫深空渐变，支持 V 冻结动态。
- `scripts/main.gd`：启动时一次性生成 128×128 Gaussian 光晕与环形能量纹理、128×32 软边光束；加色光层位于实体后方。顶点色插值形成装甲与逐渐收细淡出的尾焰。不依赖外部图片或全屏多次模糊。
- 命中圆、暖色敌弹实心边缘、冷色友弹与最简 HUD 保持清晰；发光仅为视觉，不改变碰撞半径。
