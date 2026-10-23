# SmartFit Raster 同场景对照

采集轮次：`2026-10-23T08:23:42.382467Z`；有效格 8/8。

deviceManufacturer=Xiaomi；deviceModel=2602BRT18C；systemVersion=16；appVersion=0.1.0；appBuild=17；appSource=7718e619a11250097aa27e629063935922beed0c；renderer=impeller；rendererBackend=vulkan；theme=light。

只比较同一固定场景的单开关差值；不合并帧、均值或百分位。缺格和无效格用 —，不当成 0。
前 2 秒与首次进入页面窗口可重叠；尖峰本身不能确认着色器编译。超预算比例是引擎 Raster 耗时超过帧预算的比例，并非屏幕实际掉帧率。
每格已记录实际窗口尺寸、像素比和文字缩放；差值逐格核对。采样必须保持相同方向与系统外观。
主题同时核对每帧实际条件和报告元数据；采样中应保持主题不变。

## 稳态 Raster（首次 case 帧 +2 秒之后）

| 档位 | 固定场景 | 平均 ms | P90 ms | P99 ms | 超预算比例 | 有效性 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| glass_on_stars_on | longChatScroll | 4.885 | 5.631 | 6.911 | 0.08% | 有效 |
| glass_on_stars_on | planCardScroll | 9.175 | 11.263 | 13.311 | 74.02% | 有效 |
| glass_on_stars_off | longChatScroll | 4.952 | 5.631 | 6.911 | 0.00% | 有效 |
| glass_on_stars_off | planCardScroll | 9.194 | 11.263 | 13.311 | 74.91% | 有效 |
| glass_off_stars_on | longChatScroll | 2.481 | 2.943 | 3.455 | 0.00% | 有效 |
| glass_off_stars_on | planCardScroll | 2.825 | 3.327 | 4.351 | 0.00% | 有效 |
| glass_off_stars_off | longChatScroll | 2.255 | 2.687 | 3.071 | 0.00% | 有效 |
| glass_off_stars_off | planCardScroll | 2.593 | 3.071 | 3.839 | 0.00% | 有效 |

## 前 2 秒与最差帧（Raster）

| 档位 | 固定场景 | 前 2 秒平均 ms | 前 2 秒最差 ms | 本格与首次进页 2 秒交集最差 ms | 稳态最差 ms | 全段最差 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| glass_on_stars_on | longChatScroll | 4.869 | 9.060 | 9.060 | 9.712 | 9.712 |
| glass_on_stars_on | planCardScroll | 9.234 | 15.368 | 15.368 | 19.397 | 19.397 |
| glass_on_stars_off | longChatScroll | 4.849 | 8.033 | — | 8.303 | 8.303 |
| glass_on_stars_off | planCardScroll | 9.165 | 15.333 | — | 19.475 | 19.475 |
| glass_off_stars_on | longChatScroll | 2.444 | 6.010 | — | 7.017 | 7.017 |
| glass_off_stars_on | planCardScroll | 2.762 | 4.047 | — | 8.315 | 8.315 |
| glass_off_stars_off | longChatScroll | 2.223 | 3.027 | — | 7.856 | 7.856 |
| glass_off_stars_off | planCardScroll | 2.608 | 3.471 | — | 7.267 | 7.267 |

## 全局首次进页前 2 秒（包含 beginCase 之前）

这组样本按本轮首次进入页面统计，不绑定某个档位，不参与四档差值；可与 case 初始窗口重叠。

| 页面 | 帧数 | Raster 平均 ms | P90 ms | P99 ms | 最差 ms | 超预算比例 | 有效性 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| performance_chat | 234 | 5.174 | 6.399 | 15.871 | 19.315 | 4.70% | 有效；仅作首进观察 |
| performance_plan_cards | 205 | 9.495 | 11.775 | 18.431 | 30.793 | 74.63% | 有效；仅作首进观察 |

## 仅同场景、单开关差值（关闭后减关闭前）

| 固定场景 | 对照 | 平均 Δms | P90 Δms | P99 Δms | 超预算 Δ百分点 | 可比性 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| longChatScroll | 关闭星尘（玻璃开） | +0.067 | +0.000 | +0.000 | -0.08 | 已记录条件一致；仍需重复采样确认 |
| longChatScroll | 关闭星尘（玻璃关） | -0.226 | -0.256 | -0.384 | +0.00 | 已记录条件一致；仍需重复采样确认 |
| longChatScroll | 关闭玻璃（星尘开） | -2.404 | -2.688 | -3.456 | -0.08 | 已记录条件一致；仍需重复采样确认 |
| longChatScroll | 关闭玻璃（星尘关） | -2.697 | -2.944 | -3.840 | +0.00 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭星尘（玻璃开） | +0.019 | +0.000 | +0.000 | +0.89 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭星尘（玻璃关） | -0.232 | -0.256 | -0.512 | +0.00 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭玻璃（星尘开） | -6.350 | -7.936 | -8.960 | -74.02 | 已记录条件一致；仍需重复采样确认 |
| planCardScroll | 关闭玻璃（星尘关） | -6.600 | -8.192 | -9.472 | -74.91 | 已记录条件一致；仍需重复采样确认 |

差值仅描述本轮同场景观测；本工具不推断根因，也不把单次波动或初始尖峰归为着色器编译。
P90/P99 沿用导出报告的直方图上界估计；平均与最差帧沿用报告精确值。
