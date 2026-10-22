# 语音 AAC 32kbps 试听（待开哥选择）

状态：只生成 10 条试听，尚未批量转换、修改生产清单、合并或推送。

试听目录：`E:/AII-3D/3D-Sport-AI/voice-audition-aac32-2026-10-22`。
打开该目录的 `index.html`。30 个 M4A 在同一层：10 原件、10 LC、10 HE v1。
播放器使用对应 M4A 完整解码的 WAV，避免浏览器不支持 HE；实际压缩文件由下载链接取得。

| 10 条合计，含 M4A 封装 | 字节 | 十进制 kB | 相比原件 |
|---|---:|---:|---:|
| 原件 AAC-LC，44.1kHz，单声道，约 64kbps | 258,193 | 258.193 | — |
| AAC-LC，22.05kHz，单声道，目标 32kbps | 148,587 | 148.587 | -42.45% |
| HE-AAC v1，44.1kHz，单声道，目标 32kbps | 148,827 | 148.827 | -42.36% |

单位统一使用 1 kB = 1,000 B。短音频有固定封装和编码延迟开销，不能直接把目标码率减半等同于文件减半。
这 10 条偏重极端时长和动作名，不能据此直接外推全部 695 条或 APK 体积。

| 编号 | 原文 | 原件秒 | 原件 B | LC B | HE v1 B |
|---|---|---:|---:|---:|---:|
| 01 | 一 | 0.38 | 4,306 | 4,183 | 4,251 |
| 02 | 十 | 0.49 | 5,164 | 4,627 | 4,707 |
| 03 | 六十 | 0.67 | 6,731 | 5,372 | 5,367 |
| 04 | 卷腹 | 0.62 | 6,330 | 5,194 | 5,207 |
| 05 | 站姿宽距体前屈，扶椅 | 2.25 | 19,572 | 11,828 | 11,820 |
| 06 | 坐椅弹力带髋内旋 | 1.71 | 15,259 | 9,580 | 9,637 |
| 07 | 放松一下。下一组记住，双手撑稳凳面，身体成一条直线，胸口贴近再推起 | 7.09 | 58,875 | 31,647 | 31,709 |
| 08 | 放松一下。下一组记住，背挺直，臀部向后推，感到大腿后侧拉紧再起身 | 6.89 | 59,456 | 30,860 | 30,842 |
| 09 | 左侧同样，坐直，后腿膝盖慢慢抬离地面，再慢慢放下 | 5.15 | 43,426 | 23,707 | 23,723 |
| 10 | 放松一下。下一组记住，直腿抬起离地，停 1 秒 | 4.62 | 39,074 | 21,589 | 21,564 |

01 是全库唯一最短，07 是唯一最长，08 是第二长，04/05 分别是最短/最长动作名。
另含三条报数、换侧以及提示中的数字。比较起音、数字辨识、动作名、齿音和尾音即可。

## 编码与复现

两种方案均使用 FDK AAC 2.0.3 / fdkaac 1.0.9，CBR 32,000 bit/s，afterburner 开启。
LC 的音频对象类型为 2，HE v1 为 5；没有生成 Opus 或 HE v2。
M4A 同时带 iTunSMPB 和 ISO gapless 信息。没有做响度归一、变速、变调或静音裁剪。
保留源 AAC 解码的全部 PCM，因此样件声明时长比原件最多增加 20.839ms 的帧尾填充；
原件、样件声明时长和完整解码时长逐条记录在 JSON，未将解码填充掩盖成零差异。

编码工具源：[nu774/fdkaac](https://github.com/nu774/fdkaac)，固定提交
`cdfd8a555c31ffa7d0c2e303e84bb197ba518ed8`，依赖 [fdk-aac v2.0.3](https://github.com/mstorsjo/fdk-aac/tree/v2.0.3)。
构建只放在 `.buildlog/voice-tools/`，没有替换系统 FFmpeg。

FDK 输出的 mono HE ASC 默认省略 PS=false；FFmpeg 对此会做隐式 PS 上混。
`tools/voice/fdkaac-mono-he-signaling.patch` 在限定的 mono/dual-rate HE v1 ASC 后写入
`0x548 + psPresentFlag=0`，本批 ASC 为 `138856e5a54800`。
这是封装信令补全；核验修正前后全部 11 个测试 AAC 数据包的大小和 SHA-256 一致，
解码 PCM 与原双声道输出任一声道逐样本一致，未重新修改编码帧。
FDK 解码器与 [FFmpeg 配置解析器](https://github.com/FFmpeg/FFmpeg/blob/n7.0/libavcodec/mpeg4audio.c)
均有该显式标志的解析路径。

复现步骤：将 fdkaac 固定至上述提交，执行 `git apply` 应用补丁，用 CMake 的
`-DFDKAAC_BUILD_FDK_AAC=ON` 构建，再运行（输出目录必须不存在且在 App checkout 外）：

```powershell
python tools/voice/build_aac_audition.py `
  --output E:/AII-3D/3D-Sport-AI/voice-audition-aac32-2026-10-22 `
  --fdkaac .buildlog/voice-tools/fdkaac-mono-he.exe `
  --ffmpeg D:/ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe `
  --ffprobe D:/ffmpeg-master-latest-win64-gpl/bin/ffprobe.exe
```

## 已验证及后续门槛

30/30 M4A 本机 FFmpeg 完整解码无错误，20/20 新样件为预期 profile、采样率和单声道。
10/10 原件拷贝与源文件字节相同。
全部 695 条源语音（15,662,531 B）转换前后规范化 SHA-256 均为
`770d3dd7037f5f38d7cac8d5dbf2a88d5dd93f806cc7013813bf0b892821b29d`。
逐条参数、文件 SHA-256 和工具 SHA-256 见 `reports/voice-aac-audition-2026-10-22.json`。

Android/iOS 实际播放器验收尚未执行，浏览器的 WAV 试听也不代替目标平台验收。
等开哥选定 LC 或 HE 后，才允许在新目录转换全部 695 条、更新清单与哈希、做平台验证、构建 arm64 release。
最终测试通过且开哥同意后再合并 main 并推送。此前批准的 SDK/App 合并不涵盖本轮语音分支。
真机 20 分钟训练按用户要求等有设备再做。

## 字体：跳过进一步子集

`assets/fonts/NotoSansSC.ttf` 已是 GB2312 加应用字符的子集：4,110,060 B、7,652 个 Unicode 映射、6,764 个 CJK 字符。
SHA-256：`93c0808b4374c84021581cd80ad5d5cae67303d91411d81211e77126d1e5b5ca`。
扫描 `lib/**/*.dart` 与 `assets/**/*.json` 的 167 个文件，静态集合只覆盖现有字体的 997 个字符。
再子集会移除 6,655 个映射，包含聊天动态文字可能用到的“熬、咖啡、姨妈、怀、哺乳、焦虑、骑车”等。

App 在 `app_theme.dart` 全局使用该字体，聊天输入和 AI 回复不受静态字符集合约束。
不能保证 Android/iOS 系统字体回退仍有一致的显示和布局，故不满足“不影响聊天里的动态文字”的前提，保留字体。
