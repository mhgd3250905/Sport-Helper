# SmartFit Raster 同场景对照

采集轮次：`2026-10-23T09:26:03.463832Z`；有效格 8/8。

deviceManufacturer=Xiaomi；deviceModel=2602BRT18C；systemVersion=16；appVersion=0.1.0；appBuild=18；appSource=c6f09087a3dd1c3e291bc18e6722223ba52fd91f；renderer=impeller；rendererBackend=vulkan；theme=light。

只比较同一固定场景的单开关差值；不合并帧、均值或百分位。缺格和无效格用 —，不当成 0。
前 2 秒与首次进入页面窗口可重叠；尖峰本身不能确认着色器编译。超预算比例是引擎 Raster 耗时超过帧预算的比例，并非屏幕实际掉帧率。
每格已记录实际窗口尺寸、像素比和文字缩放；差值逐格核对。采样必须保持相同方向与系统外观。
主题同时核对每帧实际条件和报告元数据；采样中应保持主题不变。
glass_on/off 表示全局玻璃开关；列表卡片独立记录 scrollCardGlassEnabled，默认静态仿玻璃。不同实际卡片模式不用于本表的单开关差值。

## 稳态 Raster（首次 case 帧 +2 秒之后）

| 档位 | 固定场景 | 平均 ms | P90 ms | P99 ms | 超预算比例 | 有效性 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| glass_on_stars_on | longChatScroll | 4.891 | 5.631 | 6.911 | 0.22% | 有效 |
| glass_on_stars_on | planCardScroll | 5.874 | 7.935 | 9.215 | 3.95% | 有效 |
| glass_on_stars_off | longChatScroll | 4.761 | 5.375 | 7.167 | 0.03% | 有效 |
| glass_on_stars_off | planCardScroll | 4.860 | 5.631 | 7.679 | 0.36% | 有效 |
| glass_off_stars_on | longChatScroll | 2.497 | 2.943 | 3.455 | 0.00% | 有效 |
| glass_off_stars_on | planCardScroll | 2.909 | 3.327 | 4.607 | 0.06% | 有效 |
| glass_off_stars_off | longChatScroll | 2.272 | 2.687 | 3.455 | 0.00% | 有效 |
| glass_off_stars_off | planCardScroll | 2.708 | 3.199 | 4.863 | 0.03% | 有效 |

## 每格实际列表卡片模式

| 档位 | 固定场景 | 实际卡片模式 |
| --- | --- | --- |
| glass_on_stars_on | longChatScroll | 静态仿玻璃 |
| glass_on_stars_on | planCardScroll | 静态仿玻璃 |
| glass_on_stars_off | longChatScroll | 静态仿玻璃 |
| glass_on_stars_off | planCardScroll | 静态仿玻璃 |
| glass_off_stars_on | longChatScroll | 静态仿玻璃 |
| glass_off_stars_on | planCardScroll | 静态仿玻璃 |
| glass_off_stars_off | longChatScroll | 静态仿玻璃 |
| glass_off_stars_off | planCardScroll | 静态仿玻璃 |

## 前 2 秒与最差帧（Raster）

| 档位 | 固定场景 | 前 2 秒平均 ms | 前 2 秒最差 ms | 本格与首次进页 2 秒交集最差 ms | 稳态最差 ms | 全段最差 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| glass_on_stars_on | longChatScroll | 4.857 | 8.011 | 8.011 | 10.604 | 10.604 |
| glass_on_stars_on | planCardScroll | 6.135 | 9.591 | 9.591 | 13.080 | 13.080 |
| glass_on_stars_off | longChatScroll | 4.681 | 8.270 | — | 8.379 | 8.379 |
| glass_on_stars_off | planCardScroll | 4.805 | 8.370 | — | 16.616 | 16.616 |
| glass_off_stars_on | longChatScroll | 2.461 | 4.607 | — | 7.352 | 7.352 |
| glass_off_stars_on | planCardScroll | 2.959 | 5.968 | — | 10.608 | 10.608 |
| glass_off_stars_off | longChatScroll | 2.219 | 3.636 | — | 6.937 | 6.937 |
| glass_off_stars_off | planCardScroll | 2.723 | 6.924 | — | 8.648 | 8.648 |

## 全局首次进页前 2 秒（包含 beginCase 之前）

这组样本按本轮首次进入页面统计，不绑定某个档位，不参与四档差值；可与 case 初始窗口重叠。

| 页面 | 帧数 | Raster 平均 ms | P90 ms | P99 ms | 最差 ms | 超预算比例 | 有效性 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| performance_chat | 236 | 5.049 | 6.143 | 12.287 | 16.961 | 3.39% | 有效；仅作首进观察 |
| performance_plan_cards | 236 | 6.466 | 8.703 | 11.775 | 17.777 | 9.75% | 有效；仅作首进观察 |

## 仅同场景、单开关差值（关闭后减关闭前）

| 固定场景 | 对照 | 平均 Δms | P90 Δms | P99 Δms | 超预算 Δ百分点 | 可比性 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| longChatScroll | 关闭星尘（玻璃开） | -0.131 | -0.256 | +0.256 | -0.19 | 已记录条件一致；仍需重复采样确认 |
| longChatScroll | 关闭星尘（玻璃关） | -0.225 | -0.256 | +0.000 | +0.00 | 已记录条件一致；仍需重复采样确认 |
| longChatScroll | 关闭玻璃（星尘开） | -2.394 | -2.688 | -3.456 | -0.22 | 已记录条件一致；仍需重复采样确认 |
| longChatScroll | 关闭玻璃（星尘关） | -2.489 | -2.688 | -3.712 | -0.03 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭星尘（玻璃开） | -1.014 | -2.304 | -1.536 | -3.59 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭星尘（玻璃关） | -0.201 | -0.128 | +0.256 | -0.03 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭玻璃（星尘开） | -2.965 | -4.608 | -4.608 | -3.90 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭玻璃（星尘关） | -2.152 | -2.432 | -2.816 | -0.33 | 已记录条件一致；仍需重复采样确认 |

差值仅描述本轮同场景观测；本工具不推断根因，也不把单次波动或初始尖峰归为着色器编译。
P90/P99 沿用导出报告的直方图上界估计；平均与最差帧沿用报告精确值。
