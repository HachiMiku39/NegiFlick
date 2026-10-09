NegiFlick 逻辑测试

在项目根目录使用匹配所装 Xcode SDK 的 Swift 编译器。模块缓存可放 work/module-cache，产物放 work。

swiftc -module-cache-path work/module-cache ChartLogic.swift InputLanguage.swift Tests/RulesTests.swift -o work/rules-tests
work/rules-tests

swiftc -module-cache-path work/module-cache ChartLogic.swift InputLanguage.swift CustomChart.swift Tests/CustomChartTests.swift -o work/custom-tests
work/custom-tests Demo/authoring.json

swiftc -module-cache-path work/module-cache ChartLogic.swift InputLanguage.swift CustomChart.swift Tests/InputLanguageTests.swift -o work/language-tests
work/language-tests

swiftc -module-cache-path work/module-cache ChartLogic.swift InputLanguage.swift CustomChart.swift Tools/CompileChart.swift -o work/compile-chart
work/compile-chart Examples/english/authoring.json work/english-chart.json
work/compile-chart Examples/pinyin/authoring.json work/pinyin-chart.json

RulesTests：31 时序边界、21 档 BPM 校准、假名方向、难度/间奏掩码、媒体时钟效果、按下/释放/错误方向/错误按键、得分、连击、Crimax、BTL、评级、失败。
CustomChartTests：五档启用掩码、精确命中 tick、Crimax 配对、重复命中拒绝、NaN/不允许命令/参数/路径越界/符号链接越界拒绝。
InputLanguageTests：声明优先、旧谱日语、假名/拉丁识别、汉字歧义、未知语言拒绝、26 字母一一映射、中文每字首字母、英文每词首字母、多音字覆盖、词提示序列化、无效输入单位拒绝及 30 Hz 判定不变。

ArchiveTests.py、DownloadTests.swift、PerformanceTests.swift 保留与现有导入/下载/性能功能的回归测试。某些历史 InterfaceTests 对旧 UI 文案的断言已不适用于中性分支，不把它们记作本轮通过。

这些测试不证明真机触摸手感或每个折叠形态的布局。实际 UI 验证范围记录于 VALIDATION.txt。
