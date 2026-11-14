# M10 星潮　B　依赖 G01、G03

来源：2026-11-07 架构审查及其最后实施记录。整理日期：2026-11-14。下列待办保留原状态；实施前核对本包源码与工作区，不以历史检查代替本次验收。

[共享 G01–G03 任务](../../../protocols/godot_party_default_protocol/doc/godot_party_default_protocol_development.md) · [包说明](gp_star_wave_guide.md)


包：`gp_star_wave`。定位：[game.gd](../game.gd)、[visual.gd](../visual.gd)、`arena.gd`、`game_core.gd`。

- [ ] `visual._ready()` 中音频播放器/合成音接作用域；把调用 `visual._play()` 改为明确的反馈入口。
- [ ] 保留 host arena、本机展示预测与既有 150ms 上限。改善 `render_game()` 按快照 key 对模型 `set()` 的边界：明确允许字段与接收方法，保留网络载荷校验，不把展示状态散写到任意模型属性。
- [ ] 团队第二个显示面可作为模式场景中的固定实例；敌机、弹幕、曲线尾迹及 RenderingServer 批绘继续动态。1085/813 行本身不是拆分依据，仅按音频、显示反馈和规则的真实边界整理。

验证：个人/团队视图、Boss 收尾、负分与生命 HUD、预测停止、菜单中自动开火停止、作用域音频清理。

## 人工验收待办

保留自 2026-11-05 场景审查，后续记录未明确关闭的人工事项：双团队视角待人工验收。
