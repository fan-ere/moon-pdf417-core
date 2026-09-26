# OSC 2026 项目自查报告

## 总体判断

`moon-pdf417-core` 定位在 PDF417 的码字层：Text / Byte / Numeric 三种压缩、按
附录 P 的自动模式选择、GF(929) Reed-Solomon 纠错与纠错修复、按附录 Q 的行列
规划与行指示符，并配有反向解码用于自校验。仓库具备 README、申报书、MIT
许可证、CI 配置、白盒与黑盒测试、可运行示例与命令行工具。

## 尚未验证的条件

- 未发布 mooncakes.io，包页面不存在。
- 是否满足当期章程的全部材料格式（作品展示墙、开发历程文章的提交入口等）
  需要按官方通知确认。
- 本库不包含 ISO/IEC 15438 附录 A 的条空模式表，不能独立绘制可扫描图形。
- 本库不实现 ECI，输入按 0..255 码元解释，非 Latin-1 载荷需先经 `utf8_bytes`。

## 已核对证据

- `moon check --deny-warn --target all`、`moon fmt`、`moon info` 均无差异。
- `moon test --deny-warn` 在 wasm、wasm-gc、js 三个目标上全部通过。
- `moon run examples/quickstart --target wasm` 输出完整码字序列与
  `parity verified: true`。
- `cmd/main` 的 `encode`、`inspect`、`capacity`、`structure` 四个子命令均可运行。

测试覆盖的关键断言：

- Text Compaction 参考向量：`"AB" -> [1]`、`"ABCD" -> [1, 63]`、
  `"HELLO" -> [214, 341, 449]`、`"]_" -> [876, 877]`。
- Numeric Compaction：`"1234" -> [12, 434]`，`"0"` 保留前导 `1` 前缀。
- Byte Compaction：`[1..6] -> [1, 620, 89, 74, 846]`，非 6 倍数使用 901 并
  携带字节计数。
- 纠错：0 级 `[3, 1, 2] -> [335, 565]`，2 级
  `-> [791, 65, 893, 586, 381, 161, 381, 304]`，生成多项式与附录 F 一致；
  损坏两个码字后可定位并修复，删除位置可将预算翻倍，超预算时报错而不是猜测。
- 布局：`finalize([2, 1], 0, 3)` 得到 9 个码字、长度描述符 7、4 个填充码字，
  `verify_symbol` 为真。
- 结构：三种簇的行指示符与手算一致，且在 3..90 行、1..30 列、0..8 级的全部
  组合下落在 0..928。
