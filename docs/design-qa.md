# 设计证据状态

状态：原生 P1 `PASS`（自动视觉回归已运行；大尺寸宿主显示器限制已保留）；历史原型 QA 未复验。

## P1 原生收口证据

验证提交：`de2b76f`、`173f43a`；系统：macOS 26、arm64；截图为未缩放窗口 PNG，backing scale `2.0x`。`script/p1.sh stage` 的 light/dark 报告位于 `/private/tmp/synora-wiki-p1-stage-final/visual-report-light.json` 和 `/private/tmp/synora-wiki-p1-stage-final/visual-report-dark.json`。

| 主题 | 尺寸 | contentLayoutRect（pt） | 窗口 frame（pt） | PNG（px） | SSIM | 几何状态 |
|---|---|---:|---:|---:|---:|---|
| light | compact | 1280 × 668 | 1280 × 720 | 2560 × 1440 | 0.999986 | MATCH |
| light | default | 1440 × 848 | 1440 × 900 | 2880 × 1800 | 0.999724 | MATCH |
| light | large | 1728 × 998 | 1728 × 1050 | 3456 × 2100 | 0.999808 | CLAMPED_ENVIRONMENT |
| dark | compact | 1280 × 668 | 1280 × 720 | 2560 × 1440 | 1.000000 | MATCH |
| dark | default | 1440 × 848 | 1440 × 900 | 2880 × 1800 | 0.999629 | MATCH |
| dark | large | 1728 × 998 | 1728 × 1050 | 3456 × 2100 | 0.999744 | CLAMPED_ENVIRONMENT |

基线文件固定在 [`Tests/VisualBaselines/P1`](../Tests/VisualBaselines/P1)。六项均高于 `DESIGN.md` 的 0.95 SSIM 门槛；大尺寸请求为 1728 × 1117 pt，当前宿主显示器只提供 1050 pt 可见高度，因此只记录 67 pt 高度限制，未把它报告成 MATCH，也未放宽宽度、内容区或 SSIM 检查。

首次建立基线时对照了本机不随 Git 分发的高保真参考 `local-reference/high-fidelity/prototype/screenshots/Synora-Wiki-HiFi-Prototype-1280x720.png` 与 `local-reference/high-fidelity/Codex 图像 2026年9月5日 01_04_23.png`：原生 P1 保留侧栏、记录列表、正文编辑区、工具栏和可选检查器的信息层级；参考中的地图、天气、媒体卡片和 AI 结果属于后续 P7/P4 能力，未作为 P1 空壳的像素内容要求。由于参考与原生截图的 viewport、内容和系统 chrome 不同，不对两者直接计算 SSIM。

键盘路径、原生控件 accessibility identifier/label、状态目录和检查器切换由 `SynoraWikiUITests` 6/6 覆盖；真实 VoiceOver 旁白、多显示器移动和发布级可访问性仍未在本机运行，继续由 P9 的系统级验收承接，不宣称已完成。

| 已确认事实 | 证据 | 影响 |
|---|---|---|
| 标称 1280×720 PNG 实际为 1513×863 | `sips -g pixelWidth -g pixelHeight` 对本地高保真 PNG 的输出 | 不继承旧 viewport、SSIM 或无裁切结论 |
| 原型四列最小宽度 180+308+500+280=1268 | 归档 DESIGN §2.1；原型 styles.css grid | 1280 可容纳；旧 1240 折叠阈值需修正 |
| `#969CAB` 对白色约 2.75:1 | sRGB WCAG 相对亮度公式计算 | 不满足原定信息文本 4.5:1；仅用于装饰 |
| 原型含模拟 AI | 封存 prototype/README.md | 不能作为 provider、Wiki 或原生交互验收 |

当前可视检查只确认参考截图有四栏、图文和上下文面板，不证明真实操作、IME、权限、保存、性能或可访问性。没有重跑旧 Web QA；也没有原生工程可测。

P1 按 [DESIGN.md](DESIGN.md) 和 [TESTING.md](TESTING.md) 建立新的原生基线与证据。每次记录 HEAD、系统、内容区 pt、scale、PNG px、状态、几何/色彩差异与人工验收结果。其他交互不得从静态图推断通过。

历史原始结论完整保存在 [封存档案](archive/2026-09-05-product-baseline.zip)，只供追溯。

## 音乐卡片补充参考

2026-09-05 用户提供的音乐卡片截图可见封面、曲目信息和播放图标。仅采纳该信息结构，见 DESIGN §9.1；不从静态截图推断应用内播放、链接解析、权限或跳转已实现。截图为会话临时附件，未复制或上传到仓库，不作为持久三尺寸像素基线。音乐/天气原生视觉与交互均 NOT_RUN。
