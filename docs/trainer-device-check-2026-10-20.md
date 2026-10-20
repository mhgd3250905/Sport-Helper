# ugk_trainer 安卓真机验证

设备：型号 `2602BRT18C`，Android 16 / API 36。2026-10-20（Asia/Shanghai）。

## 包与数据

安装 `SmartFit-ugk-trainer-0.1.0+2-debug.apk`，SHA-256 `7fd8c50b521090dd9bf60e2a332f266729c44bdab3e10936ff6de8e7bb4d24fd`。对应 SmartFit 运行代码 `bbf0f6e93cb720fc5e03565be4eafca6d5ff20e0`、SDK `ea00ff7f2a4b7f46274b70708a45b435f269f993`。使用 `adb install -r` 从 versionCode 1 升至 2，未清空数据；安装前的偏好快照只存本机忽略目录。

启动后原有安全确认、2 条历史与 1 套已保存计划存在。复用原「睡前放松」计划：7 个动作，每动作 2 组，含计次、计时及双侧动作，计划活动时间约 696 秒，未使用跳过或提前结束。测试过程中暂停过一次。

## 已观察

| 检查 | 证据 |
| --- | --- |
| 安装和启动 | 覆盖安装成功，实际包 versionName `0.1.0`、versionCode `2`；浅色播放页和示范已显示 |
| 真实出声 | 用户反馈「我听到声音了」；开始时设备媒体音量为 0，因此不以最初的 AudioTrack 日志单独证明听感 |
| 后台持续运行 | HOME 后约一分钟，服务 `isForeground=true`，同一进程持续产生 AudioTrack 播放事件；返回原训练，没有重新开始 |
| 手动锁屏 | 20:53:48 熄屏，20:54:58 采样仍为 Dozing，`ugk_trainer:training` 部分唤醒锁与前台服务存在，锁屏期间有新的 AudioTrack start 事件 |
| 锁屏听感 | 用户反馈「正常」「还在运行」；普通解锁后回到同一训练，已推进到第 3 个动作左侧，没有跳回起点 |
| 暂停/继续 | 第 5 动作后的过渡休息暂停，两次 UI 语义快照完全相同，倒数停在 14；点击继续后恢复，未跳过动作 |
| 错误日志 | 前台、后台及解锁采样未发现 `FATAL EXCEPTION`、`Unhandled Exception`、`PlayerException` 或前台服务启动异常 |

## 完成与重启保存

本轮 **完整训练、出声、后台/锁屏、暂停恢复、完成保存与重启读取通过**。开始时间 20:51:24，结束 21:03:24，活动时间 696 秒（暂停时间不计入），完成页显示 12 分钟、7/7。

保存的 `sessionId` 为 `s-mvgomjt7-f54bccb360fd`，`endedEarly=false`，`completedExercises=totalExercises=7`。7 个 `items` 全部为 `completed`，每项 `completedSets=plannedSets=2`。只生成 1 条新结果，历史从 2 条增至 3 条；原有两条历史逐项相等，原有已存计划数量与安全确认保持不变。

结束后服务已退出，`ugk_trainer:training` 唤醒锁已释放。点击完成返回聊天，出现「练完『睡前放松』了」反馈。随后停止并重新启动 App，完整结果与历史完全相同，没有重复条目；从界面点击「上次练了什么」，实际读回本次 12 分钟的已完成训练。这些验证使用同一 APK，没有为测试改剂量、改时钟或写入合成结果。

## 通知与范围

本机 `POST_NOTIFICATION` app-op 为 `ignore`，当前 manifest 未申请 `POST_NOTIFICATIONS`。因此本次没有把通知抽屉/锁屏中的通知可见性记为通过，也没有用 ADB 授予权限。服务实际处于前台，锁屏语音正常。Android 13+ 通知授权与前台服务启动是独立条件，拒绝通知时前台服务仍可运行，普通服务通知不显示在通知抽屉，见 [Android 官方通知权限说明](https://developer.android.com/develop/ui/views/notifications/notification-permission)。

本次没有来电/闹钟或真实耳机拔出测试，没有离线断网、耗电/发热长期测试，没有提交 Play Console 声明，也没有合入 main 或推送。

原始截图、UI 快照、偏好文件与进程日志只存本机 `.buildlog/device-trainer-20261020/`，不提交包含用户数据的偏好文件或原始日志。
