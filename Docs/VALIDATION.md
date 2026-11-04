# Underpass 1.0.0 验证记录

2026-11-04，Apple Silicon 本机。工作目录保持 `/Users/Admin/personal_work/MusicRelay`。旧应用与旧会话未结束；未改 v2rayN 文件，未执行特权 TUN 或系统代理变更。

## 已通过

`zsh build.sh`：SwiftUI 主程序与 supervisor 编译、图标生成、两个随附核心、预装包复制、ad-hoc 签名及 `codesign --verify --deep --strict`。最终产物标识 `local.underpass.desktop`、arm64，未公证。构建已改为先暂存再替换，另一次注入编译器退出码 73 的故障测试确认原签名应用未改变、临时目录被清理。最终打包核心的字节与通过集成测试时相同。首次编译遇到 Swift 宏插件的嵌套 sandbox 限制，已使用编译器自带 `-disable-sandbox` 选项处理；不改变运行时授权方式。

`zsh test.sh --real-config` 的最终结果：

```text
PASS: real node read-only snapshot validates in both bundled cores; credentials removed with test directory
PASS: 46 behavior checks (packages, merge, conflicts, deletion, restore, storage, recovery ownership, stale callbacks, rollback, core config)
PASS 10: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS 11: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS 01: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS 00: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS: 75 integration assertions; same sing-box PID throughout, affected connections closed and other service retained
```

46 项行为检查覆盖包校验、作用范围、未知能力拒绝、增量追加、相同内容重复、同版本修订、旧版跳过、三方字段冲突、显式旧规则删除、本地新增保留、同名目标选择、排序/开关偏好、预装墓碑、手动恢复、撤销、落盘失败不破坏旧目录、旧目录兼容、旧会话回调隔离、代理恢复字段所有权、真实 Clash processPath 格式解析、重载/缓存失败回退及回退失败升级、认证入口、源配置不变、凭据权限、两核心配置检查、原路径选择与 PAC/其他会话拒绝。

75 项内核集成断言使用随附 sing-box 1.13.14，所有端点都是临时 127.0.0.1 假出口：

- QQ / Bilibili 四种组合，网页、接口、视频 CDN、图片、无关域名及伪后缀域名的 HTTP 与 TLS CONNECT 路由。
- 使用本地自签名 TLS 假服务，不在真实网络中关闭证书校验。应用正式连通性测试仍正常校验 HTTPS。
- 本地 UDP 原 DNS 与通过假节点的 TLS DoH 分流、缓存清除后的来源切换。
- 文件原子替换后，生产代码的 `EngineClient.confirm` 确认两个规则集的代际探针，内核 PID 不变。
- 开启两个通道并保留实际未结束的连接，关闭 QQ 规则并使用生产 `EngineClient.settle` 后，QQ 连接移除、Bilibili 原连接仍在。
- 动态第三个通道生效；无效规则文件不替换旧有效规则；重新写回有效规则后恢复。

本测试曾发现默认 DNS 规则中域名与 rule_set 条件组合会误匹配，已改为显式 logical/and。最终四组 DNS 与 TLS 测试均在修正后重跑通过。普通受限 shell 不允许绑定回环端口，集成测试使用了已获执行审查许可的本机测试进程；未调用 supervisor。

原生 UI 已通过电脑工具查看浅色、深色及修改间距后的真实 macOS 渲染，核对默认窗口中诊断按钮可见。行内菜单、配置查看、默认通道的重复导入预览/取消、移除 Bilibili/撤销均实际点击验证，最后恢复为两个安装项、全部关闭、跟随系统外观。窗口最小尺寸、滚动、减少动态效果和可访问性标签已实现；该桌面采集环境的边缘拖动未改变窗口尺寸，因此没有声称完成全尺寸或 VoiceOver 实测。

## 尚需现场验证

1. 管理员授权后的真实 TUN 创建、路由撤销、系统代理恢复，及实际网络切换/GUI 崩溃/子内核故障注入。恢复策略的纯逻辑已测，特权副作用尚未实测。
2. QQ 音乐新版的未缓存歌曲播放、拖动进度、歌词。旧版 QQ 音乐已由用户跑通，是本次规则回归基线，不替代新版实测。
3. Bilibili 在公司网络下的登录状态、首页/API/图片、视频播放、拖动与切清晰度，及实际遇到的补充 CDN。
4. 真实 TUN 的进程归属、系统 DNS 缓存刷新、浏览器独立 DoH/ECH、QUIC/UDP 与 IPv6 实际出站。回环 TLS 与模拟 DNS 成功不能证明这些已通过。

建议现场顺序：先手动关闭旧音乐通道，确认原代理正常；分别开启 QQ、Bilibili，再双开；依次关闭/移除一项观察另一项继续可用，最后关闭全部核对原代理。记录实际播放与核心就绪/网页可达三个不同结论。测试期间如更换节点或网络，等待本次会话停止后手动重新开启。

## 实现依据

- [sing-box 1.13.14 本地 rule-set 文档](https://github.com/SagerNet/sing-box/blob/v1.13.14/docs/configuration/rule-set/index.md)：文件修改可自动重载；本次另外验证了实际二进制行为。
- [对应本地规则集实现](https://github.com/SagerNet/sing-box/blob/v1.13.14/route/rule/rule_set_local.go)、[DNS 缓存 API](https://github.com/SagerNet/sing-box/blob/v1.13.14/experimental/clashapi/cache.go)、[DNS 查询 API](https://github.com/SagerNet/sing-box/blob/v1.13.14/experimental/clashapi/dns.go)。未把 `/configs PUT` 当作完整配置重载。
- [Bilibili 公开维护域名列表](https://github.com/MetaCubeX/meta-rules-dat/blob/meta/geo/geosite/bilibili.list)：选取网页、接口、图片与视频范围的相关条目，不代表穷尽所有 CDN。
