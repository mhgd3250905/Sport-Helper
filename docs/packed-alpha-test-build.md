# 拼接透明素材测试构建

素材来源为 `F:\PoseHub-v2-production\app-test-pack-r1\` 的 manifest 与 catalog。全部是 App 测试版、未审；旧样片目录不再使用。素材与动作训练定义分别校验，视频的 8 秒循环不是训练剂量。

```powershell
python tools/media/import_app_test_pack.py --source F:\PoseHub-v2-production\app-test-pack-r1 --allow-unreviewed-internal --apply
```

导入器检查完整文件、SHA、编码尺寸和 alpha 通道。输出内容寻址资源及完整目录快照，不改 Pose-Hub 源文件。等待播放的透明图由同一视频第 0 帧合成，cover 与 thumbnail 仍采用交付的选帧；不能互相替代。

0.1.0+28 首轮只开启 `--flavor internal --dart-define=SMARTFIT_APP_TEST_PACK=true`，同时沿用已有内测媒体与 AI 构建配置。锁远端 `ugk_trainer-v0.2.9`。导入索引包含 5 个就绪动作，其中现有动作库匹配 `h-squat`、`h-chair-tspine`、`w-bird-dog`；其他目录项将在后续完整动作库接线后显示。普通 MP4 保留为回退。

`SMARTFIT_ALPHA_CARDS` 和 `SMARTFIT_ACTION_ISSUES` 是后两项分步交付的开关，本轮首包不启用。问题记录基础已接入独立本地存储和内部 Android Download 导出，不会在首包显示入口。完整目录接线将保留缺训练说明的动作供浏览与标记，仅按训练字段完整性准入 AI，不填假剂量。

## 定向验证

同一 Android 真机，Flutter 3.44.7 / Impeller Vulkan / profile，AI 开启、保留数据。稳态各 20 秒（视频已开始），切换各 14 秒（上一/下一各 5 次）。

| 场景 | Raster P99 | 最慢 Raster | 超 16.67ms |
| --- | ---: | ---: | ---: |
| 浅色稳态 | 8.427ms | 15.900ms | 0 |
| 浅色切换 | 8.312ms | 11.259ms | 0 |
| 深色稳态 | 8.059ms | 11.003ms | 0 |
| 深色切换 | 7.086ms | 10.013ms | 0 |

原始 FrameTiming、timeline 与截图保存在工作区 `deliveries/packed-alpha-20261025/`。这是 Raster 线程耗时，不能据此声称硬件呈现帧率。未跑全量测试。

SDK 媒体相关定向 28 项通过，随后增加的 packed-only 静帧回退组件回归也通过（组件共 7 项）。App 使用正式远端 tag 后，素材接入与训练切换 10 项通过；导入器 20 项通过。问题标记和静态卡另有独立测试，待相应开关启用后分别真机交付。

## 0.1.0+29 透明卡片

锁定远端 `ugk_coach_ui-v0.1.3`（`159dadf058ef47f701e36a496668265f9fd3fc0d`），trainer 仍为 `ugk_trainer-v0.2.9`。构建增加 `SMARTFIT_ALPHA_CARDS=true`。封面、动作库预览和缩略图使用 alpha WebP；源文件不变，使用导入时的 alpha 非零边界绘制。边界记录必须匹配当前索引的源 SHA 与尺寸，失配自动回退原图。视频第一帧保持原镜头构图，不使用封面边界。

SDK media builder 同时覆盖紧凑封面、展开飞行静帧和缩略图；卡片背景面下移 14dp，保留点击坐标。浅深主题实图像素断言验证人物突出卡面上沿 12–16dp。SDK 新增 5 项和原套路卡 13 项、App 边界/卡片 8 项定向测试通过。正式远端 Pub 严格锁文件校验通过，hosted 依赖未升级。

同一红米 Profile 验证包同时开启透明卡片与问题入口，四个受影响场景复测结果如下；未跑整页混合或全量测试。这里测量 Raster 线程耗时，不代表显示呈现帧率。

| 场景 | Raster P99 | 最慢 Raster | 超 16.67ms |
| --- | ---: | ---: | ---: |
| 浅色稳态 | 8.048ms | 10.992ms | 0 |
| 浅色切换 | 8.746ms | 14.725ms | 0 |
| 深色稳态 | 8.147ms | 10.554ms | 0 |
| 深色切换 | 7.239ms | 7.982ms | 0 |

## 内部目录与问题标记开关

`SMARTFIT_ACTION_ISSUES=true` 在内部构建显示训练页与动作详情标记入口。记录动作 ID、目录修订号、真实播放器秒数（不可用则明确 null 原因）、UTC 时间及可选标签/备注；设置直接保存至 Download/SmartFit，导出不清空本地标记。

`SMARTFIT_FULL_TEST_CATALOG=true` 仅与内部 App test pack 同时启用时生效。动作库显示全部目录条目；缺少训练字段的条目显示“训练说明待补”，已有素材仍可播放、标记。AI 只接收字段结构完整的训练定义，更新 catalog 后重新判断，不维护固定准入 ID 清单。原始器材 ID、hold 与执行节奏保留，8 秒视频循环不充当训练剂量；陌生器材不会转换为徒手。源目录声明的 semantic catalog 按字节数、SHA 和版本校验后内容寻址内置，不访问运行机器的绝对源目录。

目录解析/映射 14 项、目录页 6 项、含语义文件打包的导入器 21 项定向测试通过。完整目录与问题标记按独立构建开关分步启用；+29 release 仅启用透明卡片，不启用完整目录和问题入口。

## 0.1.0+30 问题标记

在 +29 的内部构建参数上增加 `SMARTFIT_ACTION_ISSUES=true`，完整目录开关仍关闭。两个入口已在同一红米 Profile 包实际验证：播放页抓取 `h-chair-tspine` / 修订 `h-chair-tspine` / 3.948 秒，动作详情抓取 `h-squat` / 修订 `h-squat-r2` / 4.549 秒。标签和备注可保存，恢复原输入法后，设置一键输出 `Download/SmartFit/SmartFit-action-issues-*.json`，无需文件选择器。

两条设备验收记录均注明自动验证、非素材缺陷。两次导出不清空本机标记；JSON 带 `schemaVersion`、UTC 标记时间与实际视频秒数，不包含 AI Key。运行性能沿用上方已开启问题入口的四场景 Profile 结果；本次只启用已验证的构建开关，不重复跑全量测试。

## 0.1.0+31 完整目录首批

增加 `SMARTFIT_FULL_TEST_CATALOG=true`。本次固定快照包含 219 个目录条目、142 个完整训练定义和 12 套就绪透明素材。77 个动作的训练字段仍不完整：不能因为源目录声明已更新，就将含 null 的组数、次数、时长、间歇或难度放入 AI 白名单。动作库保留这些条目并标注“训练说明待补”；素材到齐的条目可以播放和标记问题。Pose-Hub 补齐后重新导入 catalog，即按字段重新判断准入。

当前 12 个透明动作：`abs-A`、`abs-B`、`abs-C`、`adductors-A`、`adductors-B`、`adductors-C`、`chest-A`、`chest-B`、`h-bent-knee-calf-raise`、`h-chair-tspine`、`h-squat`、`w-bird-dog`。其余 207 个目录条目的新透明视频尚未内置；现有旧版离线素材继续回退，不将待交付视频伪装成下载失败。

本批 catalog SHA-256 为 `2bdb9a3d96f77287b2b7ee522586f077caef840d99433719c1d4a6d9602292e6`，训练语义源为 `40610dbb71b58886ebe001409ae15161761747b4f776e74a252e7b1f8df6e983`。实际内置文件测试验证 219/142/12 数量、全部 93 个历史动作仍保留，以及待补动作不会进入 AI。素材与内容定向测试 13 项通过，依赖外部源目录的可选用例未在该次执行；四个变更文件的静态检查通过。SDK tag 沿用 trainer v0.2.9、coach_ui v0.1.3。

红米 Profile 实测：目录显示 219 个动作，设置显示 142 个说明齐全 / 77 个待补 / 12 个透明动作。`abs-A` 在浅深主题均可透明播放；待补的 `h-bent-knee-calf-raise` 仍可播放，问题记录取得修订 `h-bent-knee-calf-raise-rr7` 和真实视频时间 4.494 秒。设置成功导出三条记录（均注明自动验证、非素材缺陷），原有两条未丢失。新增待补条目的记录也不依赖可用于训练的 Exercise 对象。原浅色主题和输入法已恢复。

真实对话请求指定空心体支撑与徒手深蹲后，生成“三分钟两动作”：徒手深蹲 10 次、空心体支撑 20 秒，新增完整动作已可进入计划。此交付只启用目录及新素材，不改已验收的 SDK 渲染实现，性能沿用 +29 的同机浅深主题稳态/切换结果，不重复全量测试。
