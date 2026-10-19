# 智能健身助手 SmartFit

描述训练场景 → 按模板生成规范训练计划 → 用预渲染动作直接展示训练小组 → 跟练（计时 / 组 × 次数 / 休息 / 换侧 / 语音播报）。

- 包名 `com.ugk.smartfit`（与 `com.ugk.hiplab` 同族），App 名「智能健身助手」
- Flutter（沙盒 3.47.6 / Dart 3.13，`sdk: ^3.12.0`，与 HipLab 3.44.7 兼容），Android 先行，iOS 同代码库
- 完全离线、无账号、不联网（WebView 只连本机回环地址播放内置视频）

## 目录

```
lib/domain/      纯规则：exercise / plan(TrainingPlan v1) / template / scenario(描述匹配) /
                 plan_generator(模板生成 + AI 预留接口) / plan_validator / session(阶段 + 时钟)
lib/voice/       语音：session_script(台词时间线) + session_runner；voice_queue / voice_library /
                 voice_line_controller / just_audio_output 复制自 HipLab
lib/core/        复制自 HipLab（媒体播放 WebView、本地存储、屏幕常亮），文件头注明来源
lib/ui/          安全确认 → 场景描述/选择 → 训练计划(训练小组) → 跟练 → 动作库 / 关于
assets/library/  exercises.json（93 个动作）、templates.json（13 套模板）——均为生成文件
assets/drill_media/ sf-<id>.mp4/.jpg（720²，约 9 MB）+ player.html/js/css
assets/voice/    预生成中文语音 zh/*.m4a + chime/ + manifest.json
tools/library/   build_library.py（动作库）、build_templates.py（模板）
tools/media/     prepare_media.py（Pose-Hub 成片转码 / 绿幕抠像）
tools/voice/     build_voice.py（edge-tts 生成语音，商用前换 Azure）
test/            领域测试 + App 主流程测试；test_screens/ 截图（不随 flutter test 运行）
docs/            评估报告、验收清单、风险、计划 schema、截图
```

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release        # 本机工具链及验收状态见 docs/acceptance.md
# 截图：SF_CJK_FONT=<NotoSansSC.ttf> flutter test test_screens/shots_test.dart --update-goldens
```

## 数据再生成

```bash
python3 tools/library/build_library.py      # 需要同级 refs/（Pose-Hub、HipLab 只读克隆）
python3 tools/library/build_templates.py
python3 tools/media/prepare_media.py --hiplab <HipLab> --green <Drive 绿幕目录>
PYTHONPATH=<edge_tts> python3 tools/voice/build_voice.py
```

## 素材与许可

动作视频来自 Pose-Hub（mhgd3250905/3D-Pose-Hub）：46 条为 v0.2.0 深色成片（经 HipLab 冻结版本），47 条为 Pose-Hub 云盘归档的绿幕母版，本仓库抠像到同色背景。
人物派生自 Blender Studio Snow（CC BY 4.0，署名见 `assets/licenses/Drill-media-ATTRIBUTION.md`，App「关于」页展示）。
3D-Pose-Hub 与 HipLab 只作参考与素材来源，本仓库不向它们写入任何内容。
