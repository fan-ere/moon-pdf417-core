# OSC 2026 项目自查报告

## 总体判断

`moon-pdf417-core` 是一个有效的 MoonBit 项目：它定位在 PDF417 的码字层，
提供 Text / Byte / Numeric 三种压缩、按附录 P 的自动模式选择、GF(929)
Reed-Solomon 纠错与纠错修复、按附录 Q 的行列规划与行指示符，并配有反向解码
用于自校验。仓库具备 README、申报书、MIT 许可证、CI 配置、白盒与黑盒测试、
可运行的示例与命令行工具。

本报告的"已核对证据"一节是实际执行过的命令与结果；"尚未验证"一节列出的
条件没有取得证据，不能算作已通过。

## 尚未验证或需要参赛人补交的条件

- 未发布 mooncakes.io，包页面不存在。
- 是否满足当期章程的全部材料格式（例如作品展示墙、开发历程文章的提交入口）
  需要参赛人按官方通知确认。
- 本库不包含 ISO/IEC 15438 附录 A 的条空模式表，因此不能独立绘制可扫描图形；
  这一点已在 README 与申报书中明确，不应被理解为"已能生成条码图片"。
- 本库不实现 ECI，输入按 0..255 码元解释；非 Latin-1 载荷需调用方先经
  `utf8_bytes` 转换。

## 仓库与提交状态

- 仓库：<https://github.com/fan-ere/moon-pdf417-core>，公开，默认分支 `main`。
- 提交均以参赛人 `fan-ere` 署名，覆盖模块脚手架、类型与常量、Text/Numeric/Byte
  三种压缩、自动模式选择、GF(929) 纠错与修复、布局规划、符号结构、反向解码、
  命令行、测试、文档与 CI。
- GitHub Actions（run 36227163345）：lint、test(wasm)、test(wasm-gc)、
  test(js)、test(native)、cli 六个任务全部成功；wasm 任务日志中
  `Total tests: 57, passed: 57, failed: 0.`，Linux 上 `moonc v0.10.14+7d59c7ec9`。

## 已核对证据

以下命令在 Windows 上、`moon 0.1.20260920` / `moonc v0.10.14` 环境中执行：

- `moon check --deny-warn --target all`：通过，无告警。
- `moon test --deny-warn --target wasm`：全部通过。
- `moon test --deny-warn --target wasm-gc`：全部通过。
- `moon test --deny-warn --target js`：全部通过。
- `moon fmt`：无剩余差异。
- `moon info`：生成的 `.mbti` 与源码一致。
- `moon run examples/quickstart --target wasm`：输出数据码字、完整码字序列与
  `parity verified: true`。
- `moon run cmd/main --target wasm -- encode --data "HELLO WORLD 1234567890123"
  --level 2 --columns 4`：输出 `parity_verified: true`。
- `moon run cmd/main --target wasm -- structure --columns 4 --rows 4 --level 2`：
  输出 4 行的行指示符，与附录 Q 公式一致。

测试覆盖的关键断言：

- Text Compaction 参考向量：`"AB" -> [1]`、`"ABCD" -> [1, 63]`、
  `"HELLO" -> [214, 341, 449]`、`"]_" -> [876, 877]`。
- Numeric Compaction：`"1234" -> [12, 434]`，且 `"0"` 保留前导 `1` 前缀。
- Byte Compaction：六字节成组 `[1..6] -> [1, 620, 89, 74, 846]`，
  非 6 倍数使用 901 并携带字节计数。
- 纠错：0 级 `[3, 1, 2] -> [335, 565]`，2 级
  `-> [791, 65, 893, 586, 381, 161, 381, 304]`；生成多项式与附录 F 一致；
  人为损坏两个码字后可定位并修复；删除位置可将预算翻倍；超出预算时报错而非
  猜测。
- 布局：`finalize([2, 1], 0, 3)` 得到 9 个码字、长度描述符 7、4 个填充码字，
  `verify_symbol` 为真。
- 结构：三种簇的行指示符与手算值一致，且在 3..90 行、1..30 列、0..8 级的
  全部组合下落在 0..928。

## 开发过程与取舍

- 决定不做条空模式表：附录 A 是纯数据表，抄写它既不能证明实现能力，也会让
  许可证说明变得含糊。项目改为独立实现行指示符公式与模块宽度，并明确说明
  渲染器的边界。
- 纠错的解码器是本项目自己写的部分，不是移植。修正 Berlekamp-Massey 的寄存器
  阶数与伴随式幂次两处错误后，纠错从"只生成"变成"能证明可修复"，这是本项目
  最有价值的一次迭代。
- 表数据用脚本生成而不是手抄。Text Compaction 的标点表曾因手抄漏一项导致
  从位置 4 起全部错位，只有固定向量才暴露出来；`scripts/gen_text_tables.py`
  就是这次事故的直接产物。

## AI 工具使用方式

- 用 AI 检索并核对 ISO/IEC 15438 的公开结构、附录编号与参考实现的测试向量，
  把结论写进 `docs/SOURCES.md`，而不是把参考实现整段搬过来。
- 用 AI 生成测试雏形与文档草稿，但所有数值断言（参考向量、行列公式、纠错
  预算）都由本地 `moon test` 与手工推导核对。
- 用 AI 做边界枚举，例如行指示符在 3..90 × 1..30 × 0..8 组合下的取值范围。

## 建议的下一步

1. 推送仓库并等待 CI，把实际的 commit 数量与 CI 结论补进本报告。
2. 增加附录 A 模式表与 SVG/ASCII 渲染，输出可扫描图形与示例图片。
3. 支持 ECI，使非 Latin-1 载荷无需调用方预处理。
4. 视时间增加 Macro PDF417 与结构化追加。
