# 五分钟澄清的离线诊断

原始真实采样见 [plan-5-minutes.json](../plan-5-minutes.json)。本目录按相同工具回复和真实 App 目录/profile做FakeLlm公开协议重放，未发新模型请求、未回答问题、未改变剂量/目标/动作。重放问句与原采样相同，不能冒称原HTTP采样已记录完整draft响应体。

重放SDK回执为 `status=infeasible`、`reason=minimum_exceeds_target`，目标300秒、容差10%，合法估时下界336秒、上界14044秒。336秒高于330秒验收上限，所以在搜索前进入澄清，不存在一次配时搜索失败的fitLog。用户没有dose锁；动作由模型选择。

下界：椅起立168＋深蹲24＋上斜俯卧撑20＋早安24＋胸拉伸30＋准备10＋过渡60＝336秒。椅起立在目录固定3组×12次、组休30秒，而且为手动计次；3秒/次是规划默认估值。该结论只针对选定组合的规划下界，不能推为全库五分钟方案不可行或真实执行最短时间。

[诊断说明](diagnosis.md)、[完整SDK回执](offline-replay.json)、[独立算术ledger](independent-bound-ledger.json)、[草稿前状态](requests-and-pre-call-states.json)及[来源哈希](diagnostic-provenance.json)保留原始内容。两份Windows生成JSON仅将CRLF换为LF，JSON结构值逐项一致；原始字节仍留在本机delivery。脚本及日志使用`.txt`封装，防止文档证据进入App测试扫描；[publication-map.json](publication-map.json)逐一映射原文件名、原始SHA、公开文件SHA及行尾转换。原说明中的本机来源路径只用于溯源。

`publishedSha256`以Git提交中的blob为准。Git另将diagnosis.md与两份日志文本的CRLF规范为LF，结构内容不变；工作树行尾可因平台而异，原始SHA与提交SHA均已列明。
