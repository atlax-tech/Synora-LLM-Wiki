# ADR-H003 — 免费本地能力、音乐与天气服务

状态：ACCEPTED / CONFIRMED（用户范围与目标方案，不是实现证据）；日期：2026-09-05。
来源：本轮用户明确要求更新所有相关文档，不购买 Apple Developer Program，不使用 CloudKit/iCloud、MusicKit 或 WeatherKit；截图只作为音乐卡片参考。

## 决策与影响

- 唯一产品边界见 [PRODUCT §5.3](../PRODUCT.md#53-当前服务与交付边界)。这是用户明确调整范围，不是工程人员为简化实现削减需求。
- 所有依赖付费 Apple Developer Program 的功能，以及全部跨设备同步，移出当前及已规划后续阶段；不要求预先配置 Apple 开发者账号，不以缺账号阻塞 P0 或其他独立本地任务。GitHub/其他同步方案尚未选定；不预建替代同步引擎。
- P0-06、P7-01…05、P7-11/12 与 FR-SYNC-02/03、FR-MEDIA-07 保留 ID，状态 DEFERRED，不算失败或未完成的必交付项。P0-10 解除对 P0-06 的依赖，原同步 ADR 仅记录本次范围决定。P8-02 解除 P7-04 依赖；阶段级依赖只含适用任务。
- P7 保留免费本地照片、地点/地图、系统入口，天气改为 CoreLocation + Open-Meteo，音乐改为自有 Music Picker + iTunes Search/Lookup 和 Apple Music 分享链接。P9 改为本机自用构建/打包，Developer ID、公证/App Store 分发暂缓。
- 本地 operation log、tombstone、备份/恢复、Skill 包签名、App Sandbox/Hardened Runtime、AI/BYOK 与编辑器等要求保留。Skill 签名不是 Apple 开发者证书依赖。免费框架与付费云服务分别判断，不能因一个集成需要付费而停止整个阶段。
- 音乐目标是记录“当时在听什么”，并非读取播放历史或在 Synora 内播放。原生卡片支持搜索选择及粘贴链接；MusicKit 仅未来可选增强，恢复需用户另行授权。
- 本轮仅修改治理/产品文档，仓库仍无原生业务实现，P0–P9 未启动；不从“继续开发”推断新增阶段已获准。

## 文档映射与替代关系

| 文件 | 本轮职责变化 |
|---|---|
| AGENTS、PRODUCT | 固定免费本地边界与 DEFERRED 语义，保留 FR ID |
| ARCHITECTURE | 移除云模块/字段/映射，增加音乐与天气契约、隐私和错误回退 |
| DESIGN、design-qa | 音乐卡片信息结构、天气来源与离线展示；截图不是功能证据 |
| SPEC、PLAN | 解除 P0/P8 阻塞依赖，重写 P7，调整 P9 分发出口 |
| DEVELOPMENT、TESTING、ACCEPTANCE | 账号非前置条件；排除暂缓项，增加公开 API/卡片真实验收 |
| UNRESOLVED、INDEX | U-002 按范围关闭，保留真实集成验证问题 |

ADR-H001/H002 与既有开发日志保留历史原文；其“全部任务保留/最终范围”、原同步技术选型仅代表当时基线，受本 ADR 的明确范围调整取代。归档 ZIP 和原始哈希不改写，任何历史 CloudKit/MusicKit/WeatherKit 或付费签名要求不作为当前规范。

## 公开依据与证据状态

以下页面于 2026-09-05 查阅；公开文档支持接口设计，不证明本机实现已通过。

- CONFIRMED：[Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 区分免费开发资源与会员权益；[macOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-macos) 供实现时核对具体能力。无需付费会员的本地构建路径是目标，实际签名/权限组合由 P0/P7 验证，不能冒称已经运行。
- CONFIRMED：[iTunes Search 参数](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/Searching.html) 支持 `media=music&entity=song`、country 与 limit；文档提示请求限流会变动，采用防抖/取消/退避，不将配额视作永久保证。
- CONFIRMED：[Lookup](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html) 支持基于 ID 查询；[结果字段](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html) 包含 trackName、artistName、collectionName、artwork 与内容 URL。接口不要求 Apple Music Developer Token；用户 Apple Music 订阅不赋予开发者权限。
- CONFIRMED：[iTunes API Overview / Promo Content 条款](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html) 对封面等素材的展示用途和邻近商店标识/链接有约束；公开可访问不等于无限素材授权。按条款显示来源商店入口，不引入音频预览下载或播放。
- INFERRED / UNRESOLVED：从 Apple Music 分享 URL 提取歌曲 ID 后使用 Lookup 是目标实现策略，不保证每个地区和链接都存在 iTunes 映射。P7-09/13 验证，失败保留卡片/原 URL、可重选或手工补全。
- CONFIRMED：[NSWorkspace.open](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)) 提供系统 URL 打开入口；实际交接本机 Music 与 fallback 属 U-011，打开成功不等于自动播放成功。
- CONFIRMED：[Open-Meteo 文档](https://open-meteo.com/en/docs) 提供按坐标查询 current 与 daily 字段，日出日落按时区处理；数据是天气模型产物，不宣称 Mac 实测天气。
- CONFIRMED：[Open-Meteo 条款](https://open-meteo.com/en/terms) 提供非商业免费 API，受调用限额与 CC BY 4.0 约束；坐标可能进入服务日志。个人非商业用途采用免费入口并展示 attribution，查询前明确坐标外发；不因 API 免费隐去隐私说明。

## 验证与回滚

验证记录见 [开发日志](../development-log/2026-09-05-free-local-services.md)。音乐搜索、链接解析、外部 Music 交接、天气定位及原生 build/test 均 NOT_RUN；只将文档一致性判定为可检查结果。未来恢复暂缓功能必须新增用户决定及对应阶段/验收调整，不通过恢复旧文档或采购账号隐式启用。
