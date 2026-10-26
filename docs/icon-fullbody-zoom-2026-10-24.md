# SmartFit 全身稍放大版 A2

开哥 2026-10-24 的要求取代此前 B 半身方案：回到最初的全身 A，在画面内适度放大，并保留完整双脚。A2 已制作并通过真机核验，**开哥已明确确认“采用 A2，合入 main 并推送”**。品牌改动以已合入的流畅度版本 `d362084976387b2b2fc331a0da8974dc112c02bf` 为基础；实际合入与推送结果见 Git 和 Cockpit 检查点。

## 图像与构图

[A2 1024 原图](../assets/brand/source/smartfit-icon-v3-fullbody-zoom.png) 基于原 `smartfit-icon-v3.png` 用内置 image_gen 编辑，提示词目标约 15% 放大。独立目测为一成多；抬起手臂、双腿、两只鞋以及机器人和天线均完整，鞋底下仍有约 50px 留白。不是精确像素变换承诺。没有改页面布局、颜色 token、SDK 或星尘、列表或其他页面渲染代码；额外仅同步 App/报告版本元数据到+22。

工具输出 1254×1254 RGB，经统一等比缩到所需 1024×1024，没有裁切或追加缩放构图。完整 prompt、参考图和输出 hash 见 [来源记录](../tools/branding/fullbody-zoom-provenance.json)。原 A/B 源图、78 份候选资源及原内测 APK 留存。

按开哥追加要求，原始全身底图、半身候选、A2 的1024源图均保留在 `assets/brand/source/`；A2 的1254原始生成文件也按原字节归档至 `tools/branding/archive/smartfit-icon-v3-fullbody-zoom-generated-1254.png`。归档不作为 App 打包资源，后续可从底图重新调整构图。

新 [三行遮罩对照](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) 依次为原全身 A、裁切 B、放大全身 A2；A2 的双脚在圆形及圆角遮罩下均完整。Android 前景仍为整图 46dp，含四角的对角线约 65.05dp，完整落在 66dp 安全圆内；放大来自画面内构图，未放大图层突破安全区。

## 包与真机

源码 `b50722329145a267b098f8f0e6e64054936fd4e0`。arm64 internal release 包名 `com.ugk.smartfit.internal`，versionName `0.1.0`、versionCode `2022`，与先前 +21 同签名；可以覆盖安装，无需卸载。

文件：`.buildlog/icon-a2-22/install/SmartFit-0.1.0+22-internal-iconA2.apk`；50,060,399 字节；SHA-256 `eeacfbb71bb065aaef35e36b55b50d8a00c7da256d1b3b9553f114667fbba7d4`。

已在 Xiaomi 2602BRT18C / Android16 真机覆盖安装，安装 APK hash 与交付包一致，启动与进程存活检查通过。重启手机前，返回桌面并重启桌面/应用信息进程后，系统图标仍与旧 B 截图的图标区域逐像素相同；+21 同版本安装与+22正常升级均如此，因此版本升级本身未解决这次缓存显示。

开哥自行重启手机并告知完成后，再次核验 Android 启动完成、versionCode 仍为2022、已安装 APK hash 仍与上述 A2 包一致；本次没有重新安装。**系统应用信息页已显示 A2 全身稍放大版，两只鞋、抬起的手臂以及机器人和天线完整。** 主审与独立只读复核均将新截图与原 A、裁切 B、A2 源图比较：主体比例与构图符合 A2，双腿不再像 B 一样截断；结论不只依据图标像素发生变化。系统截图及核验回执保存在本地 `.buildlog/icon-a2-22/post-reboot-app-info.png` 和 `post-reboot-check.json`。App 与桌面数据始终未清除；没有再次重启手机。此检查不是性能采样；核验后开哥已确认采用 A2 并批准品牌合入与推送。

## 验证范围

新运行图标 Python **14 项通过**、118 份生成文件及38份本地默认资源校验通过，三种候选的五种 Android 密度与安全区通过。APK 的选中 A2 图标逐像素匹配，原 A/B legacy 图标不存在；源码身份、同签名 v2、非 debuggable、仅 arm64、最终 DEX/JNI 及内测记录器保留检查通过。

Dart 业务/渲染逻辑与上轮已验证品牌版本一致，仅两个版本元数据常量由21改22。沿用其全量420通过/13跳过、材质专项23通过/4跳过；本轮额外运行版本/导出专项18通过/1跳过，重新静态分析零问题，没有重跑或声称重跑全量。前次 production 内测代码剔除证据来自 `216c7b3`，本轮未重新生成 A2 production APK；Dart/原生性能行为未变，额外仅版本元数据同步。未启动模拟器。

Android/iOS 默认资源为开哥选定的 A2，选择元数据已更新为 `user_selected_default`；图标默认选择与品牌合入均已批准，不代表发布新的 production 二进制包。iOS 所有19个现有槽位已生成，Windows 未执行 macOS 编译/签名。

同版本+21尝试的包与安装hash均正确，但系统仍显示旧B缓存，不作为观感通过依据。新版使用+22正常升级；历史+21 A/B包留存，Android可能阻止从+22降回+21，不为回退而卸载或清数据。

机器可读证据：[交付 JSON](reports/icon-fullbody-zoom-delivery-2026-10-24.json)。真机图标核验与用户采用确认已完成；按批准执行品牌分支合入 main 及推送。
