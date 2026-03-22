# 🕳️ Black Hole — Godot 4.6 Interstellar Shader

基于 [Shadertoy 原版](https://www.shadertoy.com/view/lstSRS)移植的星际穿越(Interstellar)风格黑洞效果着色器，运行在 Godot 4.6 (C# / .NET 10) 上。

## 效果特性

- **引力透镜 (Gravitational Lensing)** — 光线在黑洞引力场中弯曲
- **吸积盘 (Accretion Disc)** — 带噪声细节和旋转动画的发光气体盘
- **Bloom 辉光** — 通过 screen texture mipmap LOD 采样实现的多层级辉光
- **Tonemapping & 色彩分级** — 电影级色调映射和色彩调整

## 运行

1. 用 **Godot 4.6 (.NET 版)** 打开项目
2. 菜单 **Project → Build** (或 `Alt+B`) 编译 C# 代码
3. 按 **F5** 运行
4. 移动鼠标改变观察角度

## 项目结构

| 文件 | 说明 |
|---|---|
| `black_hole.gdshader` | 主着色器 — 光线行进 + 引力弯曲 + 吸积盘 + Tonemapping |
| `bloom_composite.gdshader` | Bloom 叠加层 — 多级 mipmap 辉光 |
| `BlackHole.cs` | C# 控制脚本 — 分辨率/鼠标传递 |
| `black_hole.tscn` | 场景文件 |
| `黑洞/` | Shadertoy 原始源码备份 |

## 致谢

原始 Shadertoy 着色器: https://www.shadertoy.com/view/lstSRS
