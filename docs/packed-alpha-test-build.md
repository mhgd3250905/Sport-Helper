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
