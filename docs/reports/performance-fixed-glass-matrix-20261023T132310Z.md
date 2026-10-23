# SmartFit 固定玻璃拆分实验

轮次 `2026-10-23T13:15:04.217786Z`；标准格有效 9/9。

deviceModel=2602BRT18C；systemVersion=16；appSource=761d979f7844cc6b36369e2f3212852cb0278363；theme=dark；renderer=impeller；rendererBackend=vulkan

只做同场景、同设备/刷新率/主题/星尘/列表卡片模式比较；不合并帧或百分位。缺格和无效格为 —，不作 0。
顶栏：N/A；底栏：N/A。当前承载页实际固定玻璃只有输入框和建议条，不能生成不存在元素的假对照。
预热 succeeded 仅表示完成了离屏绘制尝试，不证明所有驱动着色器已编译。

| 配置 | 场景 | Raster 平均 ms | P99 ms | 超预算比例 | 有效性 |
| --- | --- | ---: | ---: | ---: | --- |
| baseline | planCardScroll | 5.699 | 8.703 | 1.556% | 有效 |
| input_static | planCardScroll | 4.496 | 7.679 | 0.528% | 有效 |
| suggestions_static | planCardScroll | 3.576 | 5.119 | 0.000% | 有效 |
| no_saturation | planCardScroll | 5.169 | 8.703 | 1.028% | 有效 |
| half_blur | planCardScroll | 4.580 | 6.911 | 0.195% | 有效 |
| no_saturation_half_blur | planCardScroll | 4.482 | 6.911 | 0.167% | 有效 |
| all_static | planCardScroll | 3.266 | 4.607 | 0.028% | 有效 |
| baseline_prewarmed | planCardScroll | 5.125 | 8.703 | 1.029% | 有效 |
| chat_baseline | longChatScroll | 4.426 | 6.911 | 0.111% | 有效 |

## 仅计划卡同场景对照 baseline

| 配置 | 平均变化 ms | P99 变化 ms | 超预算变化百分点 | 可比性 |
| --- | ---: | ---: | ---: | --- |
| input_static | -1.204 | -1.024 | -1.028 | 可比 |
| suggestions_static | -2.123 | -3.584 | -1.556 | 可比 |
| no_saturation | -0.531 | +0.000 | -0.528 | 可比 |
| half_blur | -1.119 | -1.792 | -1.362 | 可比 |
| no_saturation_half_blur | -1.217 | -1.792 | -1.389 | 可比 |
| all_static | -2.433 | -4.096 | -1.529 | 可比 |
| baseline_prewarmed | -0.575 | +0.000 | -0.527 | 可比 |

## 每配置进入目标页前 2 秒（独立于滚动稳态）

同一轮后跑的预热格已经受前面页面访问影响，不能当作冷/暖因果证据。冷/暖首次进入需分别重启 App 后首先跑 baseline / baseline_prewarmed，各自导出；本工具不跨启动合并帧或百分位。报告重置不会清除进程内页面访问历史。

本进程首次进入目标页也不保证 GPU 全冷：前页可能已经绘制共享组件，报告没有 Timeline 着色器编译事件。

| 配置 | 最差 Raster ms | 预热实际状态 | 预热绘制尺寸@像素比 | 本进程此前进过目标页 | entry 序号 | entry 有效性 |
| --- | ---: | --- | --- | --- | ---: | --- |
| baseline | 16.960 | disabled | — | False | 1 | 有效 |
| input_static | 12.365 | disabled | — | True | 2 | 有效 |
| suggestions_static | 10.099 | disabled | — | True | 3 | 有效 |
| no_saturation | 13.494 | disabled | — | True | 4 | 有效 |
| half_blur | 12.492 | disabled | — | True | 5 | 有效 |
| no_saturation_half_blur | 13.506 | disabled | — | True | 6 | 有效 |
| all_static | 8.436 | disabled | — | True | 7 | 有效 |
| baseline_prewarmed | 32.715 | succeeded | 393.84615384615387×480.0@3.25 | True | 8 | 有效 |
| chat_baseline | 19.654 | disabled | — | False | 1 | 有效 |

## 每格实际材质

| 配置 | 输入框 | 建议条 | 模糊 sigma | 饱和度 |
| --- | --- | --- | ---: | ---: |
| baseline | 真玻璃 | 真玻璃 | 1.2 | 1.15 |
| input_static | 静态仿玻璃 | 真玻璃 | 1.2 | 1.15 |
| suggestions_static | 真玻璃 | 静态仿玻璃 | 1.2 | 1.15 |
| no_saturation | 真玻璃 | 真玻璃 | 1.2 | 1.0 |
| half_blur | 真玻璃 | 真玻璃 | 0.6 | 1.15 |
| no_saturation_half_blur | 真玻璃 | 真玻璃 | 0.6 | 1.0 |
| all_static | 静态仿玻璃 | 静态仿玻璃 | — | — |
| baseline_prewarmed | 真玻璃 | 真玻璃 | 1.2 | 1.15 |
| chat_baseline | 真玻璃 | 真玻璃 | 1.2 | 1.15 |

绝对性能目标只以真机数据判断。P99 是直方图上界估计；超预算比例表示引擎 Raster 耗时超过 1000/Hz 的比例，并非屏幕实际掉帧率。
最终默认配置仍待本表实测结果确认；进入尖峰单独记录，不阻断稳态方案选择。
