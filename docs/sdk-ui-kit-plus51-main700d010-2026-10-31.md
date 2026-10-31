# +51 SDK main700d010 迁移与测试报告（起始 2026-10-31，收尾 2026-11-01）

**用户已明确反馈真机验收通过，并要求停止测试。** 已按本轮出测试包的指令完成同源 +51 release，覆盖安装到手机且保留首次安装时间。0 像素量化目标仍未达：130 对帧中 13 对非零、共 299 像素，原始结果保留；Hark 独立回执未记录。不合 main、不动 release/1.0、不打 tag，不再调整动效或追测。

本报告生成时间：2026-10-31T16:02:29.829239+00:00。APK / profile / 原生观察均来自生成时已经存在的真实回执；缺失项保持 pending。

## 源码与迁移范围

三包固定 SDK `700d0100f1cb42ef122e774a6ee0076d1916b5e5`。模型实际运行源码 A 为 `7548ee00955f3811fb9c18139503bb7f04abc11a`；完整软件门禁、130 帧及包源码 B 为 `de0bd432ec85f055206792b921964630739fd137`；已推送逐帧文档 C 为 `90d31baf243899c5f41b9af2902ec6934c957dc3`。A→B 仅 11 个帧工具文件变化，14 项模型目录/引擎/配置/探针输入 SHA-256 全部一致，证明见 [source-A-B-proof.json](reports/sdk-ui-kit-plus51-main700d010-evidence/source-A-B-proof.json)。这是输入复用证明，没有重跑或冒称在 B 重新调用模型。

已删除 SF 本地 CoachTaskBubble、CoachDeliveryTransition、PlanFocusLabel 共 1648 行，以及 SDK 已覆盖的两份纯组件单测共 1080 行。Focus 保留 2 个 SF dock / clear / viewport 宿主集成测试；出卡、取消和既有训练路由集成继续保留。任务数据适配 17 行；剪影 Widget 缓存 helper 24 行。宿主使用 SDK 同名组件和 CoachTaskSummary.fromState，出卡组件维持 SDK direct-child 识别。

cutoutBuilder 复用 SfAlphaAsset 的原素材、深浅映射、legacy crop 和原语义；缓存按素材/语义/尺寸/亮度稳定复用。iconBuilder / clearIconBuilder 仍直接返回 SfIcon。任务配色沿用原 task 角色，未改 token 数值、颜色、尺寸、曲线或动画参数；SDK 4 个 RepaintBoundary 保留，宿主未额外增加或合并。

## 软件门禁

SF 全量 822/822 通过、0 失败、0 skip；analyze --fatal-infos 为 0 issue，strict lock 通过。软件门禁源 B 与当前编译输入哈希一致。日志和机器记录见 [软件门禁](reports/sdk-ui-kit-plus51-main700d010-evidence/final-software-gates.json)。软件结果不代替 Hark、用户、真机或包发布验收。

## 130 对逐帧对比

浅色和深色各 65 对；117 对像素完全一致，13 对非零，共 299 个像素。单帧最多 81 像素，最大通道差 59/255，不能归类为全量零差或仅低幅抗锯齿差。原 58 对以及新增 focus 边界帧全部为 0；新增非零都位于剪影揭示/轮换的中间帧。原始 PNG 和严格比较记录保持不变。

| 帧 | 差异像素 | bbox [left,top,right,bottom) | 最大通道差 | 诊断图 |
|---|---:|---|---:|---|
| `light/posehub-reveal-305ms.png` | 2 | `[188, 282, 189, 284]` | 8 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--posehub-reveal-305ms.png) |
| `light/posehub-crossfade-901ms.png` | 5 | `[119, 238, 189, 284]` | 1 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--posehub-crossfade-901ms.png) |
| `light/posehub-crossfade-1025ms.png` | 25 | `[115, 236, 188, 287]` | 37 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--posehub-crossfade-1025ms.png) |
| `light/legacy-reveal-181ms.png` | 1 | `[115, 249, 116, 250]` | 1 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--legacy-reveal-181ms.png) |
| `light/legacy-reveal-305ms.png` | 34 | `[112, 243, 190, 293]` | 21 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--legacy-reveal-305ms.png) |
| `light/legacy-crossfade-901ms.png` | 13 | `[113, 243, 189, 291]` | 8 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--legacy-crossfade-901ms.png) |
| `light/legacy-crossfade-1025ms.png` | 81 | `[111, 243, 194, 298]` | 59 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--legacy-crossfade-1025ms.png) |
| `light/legacy-crossfade-1149ms.png` | 2 | `[113, 249, 116, 279]` | 2 | [原图诊断](ui-kit-frames/sdk-main700d010/review/light--legacy-crossfade-1149ms.png) |
| `dark/posehub-reveal-305ms.png` | 3 | `[188, 281, 189, 284]` | 3 | [原图诊断](ui-kit-frames/sdk-main700d010/review/dark--posehub-reveal-305ms.png) |
| `dark/posehub-crossfade-1025ms.png` | 20 | `[115, 236, 188, 287]` | 7 | [原图诊断](ui-kit-frames/sdk-main700d010/review/dark--posehub-crossfade-1025ms.png) |
| `dark/legacy-reveal-305ms.png` | 27 | `[112, 243, 190, 293]` | 9 | [原图诊断](ui-kit-frames/sdk-main700d010/review/dark--legacy-reveal-305ms.png) |
| `dark/legacy-crossfade-901ms.png` | 11 | `[113, 246, 189, 291]` | 3 | [原图诊断](ui-kit-frames/sdk-main700d010/review/dark--legacy-crossfade-901ms.png) |
| `dark/legacy-crossfade-1025ms.png` | 75 | `[111, 243, 194, 298]` | 21 | [原图诊断](ui-kit-frames/sdk-main700d010/review/dark--legacy-crossfade-1025ms.png) |

详见 [13 帧逐项说明](ui-kit-frames/sdk-main700d010/13-frame-differences.md)、[全部严格结果](ui-kit-frames/sdk-main700d010/pixel-diff.json) 和 [来源绑定](ui-kit-frames/sdk-main700d010/source-bindings.json)。旧树在 Transform 外共用固定 ClipOval，新 slot 路径由每张图片内部 ClipOval 裁切；这是与差异位置吻合的源码推断，未做改参或 SDK 修改，也未当作已经实验证明的唯一原因。

语义严格比较保留 26 对 rect 浮点尾数差，最大 1.4210854715202004e-14 logical px；所有 label、isImage、clear label、button 和 tap 语义相同，未用容差覆盖原始结果。两树实际均为 4 个 RepaintBoundary，legacy cropPainter 数量相同。Hark 仍待逐帧裁决。

## 五次真实模型生成

同一真实 App 目录加载链（PoseHubActionLibrary → AppTestCatalog → AppTestContent → SessionEngine），5/5 独立 fresh store/empty prior conversation；5、5、5、10、20 分钟各指定 case 仅一轮，outer retry=0。原始用户句保持不变，成功也保存 request/response、实际聊天、公开 TurnResult 与会话独立性证据。

| case | 卡片 / phase 秒 | 相对目标 | LLM / HTTP | user / full turn 秒 | input / output tokens | 执行证据 |
|---|---:|---:|---:|---:|---:|---|
| 5m-01 | 287 / 287 | -4.33% | 6 / 6 | 16.372 / 16.376 | 71550 / 1733 | 手动阶段估算；未自动重放 |
| 5m-02 | 317 / 317 | +5.67% | 5 / 5 | 15.121 / 15.125 | 47708 / 1375 | SDK 自动排程时钟重放 |
| 5m-03 | 309 / 309 | +3.00% | 5 / 5 | 16.721 / 16.723 | 49508 / 1346 | SDK 自动排程时钟重放 |
| 10m-01 | 629 / 629 | +4.83% | 4 / 4 | 15.453 / 15.457 | 43026 / 1753 | SDK 自动排程时钟重放 |
| 20m-01 | 1242 / 1242 | +3.50% | 4 / 4 | 15.099 / 15.102 | 42670 / 1851 | SDK 自动排程时钟重放 |

总计 24 LLM / 24 HTTP attempts，输入 254462、输出 8058、总计 262520 tokens；LLM elapsed 合计 78.230s，探针总 wall 80.926s。HTTP attempts 为 SDK 公开计数，不是线级抓包。缓存输入 178816 已包含在 input；reasoning 完整总量未知（21/24 call 可见，已知小计 4324，另 3 call 未知），不估算且不再次相加。逐 call 耗时与所有可得 token 指标保留在五份 raw。

五个 card/phase 排程均在目标 ±10%，全部交付，question=null，实际 chat/events 也无已送达反问；full turn 全部≤20s、LLM 全部≤8 次。首 case 的 h-kneeling-pushup 为 self_paced、10 reps、估算 30 秒；按本轮用户授权标注估算且不判失败。其自然执行需要用户完成，未证明真实自然时钟落在 ±10%；其余四例完成 SDK 自动时钟重放，这也不等同于真机训练验收。

首 case 共 6 calls：response 3 的 draft_plan 缺 goal，返回 missing_parameters；response 4 set_params 补 goal，response 5 draft 成功，response 6 show_plan 交付。该例两次 draft，其余各一次，不能称五例都首 draft 通过。此修复与配时恢复分开记录。

离线按 case/response occurrence/规范化 toolCallId 关联去重：新增 duration_fit_failed=0、blocked ask_user=0、失败后 redraft 请求/实际执行=0/0、其他 infeasible recovery=0、ask_user 请求=0。覆盖 36 份中间 receipt 与 5 次终态成功 proof，无映射冲突或缺口。本轮没有触发 duration recovery，不能宣称真实覆盖了失败后恢复能力。原材料分析前后 SHA 不变，见 [恢复审计](reports/sdk-ui-kit-plus51-main700d010-evidence/release-preparation/recovery-analysis/summary.json) 和 [参数修复详账](reports/sdk-ui-kit-plus51-main700d010-evidence/release-preparation/recovery-analysis/first-case-parameter-repair.md)。

## 测试包与原生 profile 观察

| 包 | 状态 | 版本 / versionCode | 字节 | SHA-256 |
|---|---|---|---:|---|
| release | artifact_verified | 0.1.0+51 / 2051 | 42687662 | `c85b2344ecaf8eecbc9d7e07ed891515f582e50f2b20990e25df7baf01c74aad` |
| profile | artifact_verified | 0.1.0+51 / 2051 | 53645862 | `facc62cb42d142a72a6b29d0cff0ea839d564397fde20ee9b045288eb20456d9` |

release 的大小门禁为严格小于 45,000,000 bytes；profile 的调试/VM service 运行时体积不套用此 release 门禁。签名方案按实录保留，V3=false 不写成 V3 通过。

机器报告仅在真实包文件、回执和独立验证三者哈希一致时写 artifact_verified。签名/16KB ELF/zipalign/JNI 只报告实际检查结果，尚无回执的模式保持 pending。APK 保留于本机交付目录，不入仓。

用户明确反馈“你不用测了我验收通过了”，已停止后续测试。反馈时手机安装的是同源 B 的 profile；随后已用同签名 release B 覆盖安装并读回核对，首次安装时间保留。本轮未取得有效转圈态 overlay 截图，不报告等待状态 UI/raster 最大值或红条结论，也不再补采。

## 当前验收边界

用户在本会话明确表示“你不用测了我验收通过了”，按 user-reported passed 记录，反馈时安装的是 profile B；同源 release B 随后已覆盖安装。此为用户反馈，不冒充代理完成了全部设备测量。Hark 独立逐帧回执仍未记录，0 像素目标为 false。用户停止测试后不再采集 overlay 或完整视频，也不继续触发模型请求。不合 main、不动 release/1.0、不打 tag，等待后续安排。

仓内只发布 synthetic 模型材料、软件门禁、软件帧，以及清洗后的包/数值摘要。原生手机截图/录屏、设备序列号、APK、私钥、认证信息和 VM URI 全部排除。旧 gap 与 prepared patch 说明作为历史保留，当前 SDK700 slots 已真实接入；旧 pin 的暂缓切换和旧 Hark-before-APK 条件不能覆盖本轮更新授权。

机器记录：[sdk-ui-kit-plus51-main700d010.json](reports/sdk-ui-kit-plus51-main700d010.json)。公开证据复制清单：[public-copy-manifest.json](reports/sdk-ui-kit-plus51-main700d010-evidence/public-copy-manifest.json)。
