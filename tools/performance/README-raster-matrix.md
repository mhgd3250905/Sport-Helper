# 实色界面原始帧十格工具

仅接受 schema 3、material=solid。浅深主题各采计划卡滚动、长聊天、进入动作库页面、底栏入口→抽屉→动作库→返回、真实训练播放页。底栏流程使用既有入口，不是导航Tab。旧材质实验实现和对应schema工具已移除。

采样入口为内测设置“性能报告”→“浅深主题×五场景”。两滚动场景保留72条隔离离线会话、32秒、每4秒3200逻辑像素往返；进页3秒、底栏20秒、播放22秒，后两项前2秒另列。切换主题使用原设置，保持同一星尘偏好、字号、缓存与实际刷新率。

    python tools/performance/raster_matrix.py <原始报告.json> -o <新矩阵.md> --json-output <新矩阵.json>
    python tools/performance/raster_matrix.py <浅色单格.json> <其他九格.json> -o <新矩阵.md>
    python -m unittest discover -s tools/performance -p test_raster_matrix.py -v

工具重新计算原始整数微秒的exact nearest-rank，不采信预先填写的分位。120Hz Raster P99严格<8330us；>8330us与duration*120>1000000分别计数。P99门槛始终固定8330us，不因60Hz放宽；实际周期另列，非120Hz样本不足以代表120Hz设备验收。没有样本、缺格、原始帧溢出、条件混合、源码或设备不同均不能得到十格P99通过结论。超预算数量和比例需单独审阅，不自动宣告总体验收通过。旧4.607ms仅作另一构建的历史参考，不合并百分位或计算因果收益。

完整报告使用一个rawFrames表；每格rawFrameIndices引用同一表，不复制原始时间。VM逐格导出则在该格内保留rawFrames，工具两者都识别。分位因原始帧容量不足变为null，不回退到直方图估计。App和Android内测分享上限一致为64MiB，以UTF-8字节数计，JSON紧凑编码；超过上限保留原统计，改用本地逐格导出。

构建必须传真实SMARTFIT_BUILD_SOURCE与SMARTFIT_SOURCE_FINGERPRINT。指纹算法及保留数据的构建/采集步骤在工作区deliveries/flat-release-20261026。指纹覆盖公共Android构建输入，不读取私密defines或签名密钥。

VM扩展仅在internal profile注册：status为轻量状态，armCase在真实目标路由准备采样，case按固定caseId导出单格，endCase/cancelCase结束或取消，snapshot/reset/scenario/endScenario保留通用能力。正式release只有设置导出路径；生产构建没有内测诊断。

这些数据不证明硬件呈现FPS、屏幕掉帧率或GPU完成时间。原生renderer解析器Kotlin验证保留，使用tools/performance/test_renderer_evidence.kt；保持同一实际renderer/backend后比较。
