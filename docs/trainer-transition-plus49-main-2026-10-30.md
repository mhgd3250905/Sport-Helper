# +49 main 合入与重新验证（2026-10-30）

已按开哥明确授权从main `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6` 快进纳入已验收的 `09bc71b69ffe5b51e9691e4b424feecfce7289df`，版本保持0.1.0+49 / internal arm64 2049。SDK三包及coach override锁定 `66dd98a549c1ff5fedecb626a7c88583090a1440`，实时核实为SDK远端main，包含c97a79a5与66dd98a5。在main重新全量测试 **861/861**、0失败/跳过，analyze **0问题**；全新release arm64 **42,655,230B / 42.655MB**，同签名、ZIP/ELF16KB、JNI、无MP4门禁通过。后续只追加README/docs收束，最终main及推送核验见交付目录 `final-main-receipt.json`。release/1.0、guide-lite及其他分支不动，不打tag，不改SDK源码，不再操作手机。

## 合入前检查

App本地及远端main均为`d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`，未出现额外提交，无需rebase。`git merge --ff-only 09bc71b69ffe5b51e9691e4b424feecfce7289df`成功，无merge commit。SDK远端main=`66dd98a549c1ff5fedecb626a7c88583090a1440`，c97a79a5是其父提交；三包及coach override的声明、锁文件和实际解析根目录一致，SDK工作树保持干净。

保存全部本地/远端分支与tag的合入前快照，后续分别核验推送前和推送后状态。保护release/1.0及guide-lite等所有非main分支，不推送候选分支，不创建tag。

## main 上的全新复验

Flutter 3.44.7；全量`flutter test --no-pub --concurrency=1 --flavor internal`结果 **861/861通过，0失败/跳过**，`flutter analyze --no-pub` **0问题**。沿用正式219动作语义目录fixture，并真实校验r1-v3下载来源。严格offline/enforce-lockfile通过，锁文件与验收候选一致。

首次预检查在运行测试前发现main工作树的旧package_config仍解析旧SDK，门禁正确拦截；严格pub get刷新本地解析后重跑，未改tracked文件或依赖锁，不是测试失败或跳过。

首次release编译已生成不含MP4的42,655,230B新包，但Gradle门禁会扫描outputs/apk下所有模式，遇到4个历史debug/profile/production APK中的视频而失败。4个历史生成包连同失败日志已移动到交付目录`failed-release-r1/`保留，记录移动前后SHA；未删除文件，未改源码或放宽门禁。随后重新运行完整构建与独立复验，最终以成功回执为准。

第二次编译完成，检查阶段因新校验目录漏带`font-decision.json`停止。补入与已验收候选逐字节相同的原字体保留策略，出处和SHA见`policy-input-provenance.json`；当次日志保留在`failed-release-r2/`。之后再次完整运行构建与门禁，未改字体、源码、锁文件或门禁标准。

本次重新构建release，仅使用main源码`09bc71b69ffe5b51e9691e4b424feecfce7289df`；未复用原分支APK。公共源码及测试输入指纹和实际APK内嵌源码身份均已校验。

| 项目 | 结果 |
| --- | --- |
| 版本 | 0.1.0+49 / internal arm64 2049 |
| release APK | `E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus49-main-20261030\SmartFit-main-0.1.0+49-09bc71b-internal-arm64-v8a-release.apk` |
| 大小 | 42,655,230B / 42.655MB（上限45,000,000B） |
| SHA-256 | `b488e2aedda2088fa94e433bcbabf48866a99bc4b3d14a3f7033ef6c17c705e4` |
| 签名证书SHA-256 | `3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`，与原包相同 |
| ABI、ZIP/ELF16KB、Storage JNI | 仅arm64；全部通过 |
| 资源门禁 | AssetManifest及ZIP无MP4；原Noto、静态图片/语音保留 |
| 独立复验 | `validation-release.json`通过，源码、日志、APK和原始回执哈希一致 |

## 提交与推送凭据

本文件与版本台账为后续README/docs-only收束提交，不改变已编译源码、测试或资源。最终main完整SHA、远端一致性、其他refs未变及推送结果由仓库外`E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus49-main-20261030\final-main-receipt.json`记录，避免自引用提交哈希。

用户已明确授权在全部门禁通过后推送main。写入本文时尚未推送，最终以实际推送回执为准；不把计划推送写成既成事实。原+49真机验收沿用用户原结论，本次main新包未安装，不冒称再次真机验收。
