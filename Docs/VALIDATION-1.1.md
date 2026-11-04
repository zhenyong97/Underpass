# Underpass 1.1.0 布局验证

2026-11-04，原生 macOS SwiftUI。将长页面改为固定工具栏、紧凑通道列表和选中通道详情，默认 820 × 580 pt、最小 700 × 480 pt。

## 范围

- 变更：`UnderpassViews`、新 `ChannelDetailView`、搜索/筛选逻辑、窗口尺寸与场景 ID、隔离预览宿主、版本化打包与文档。
- 主程序的包格式、合并存储、路由生成、SessionController、EngineClient、规则事务和特权助手未改动；当时已与布局调整前快照逐文件比较。快照随后按用户要求清理，当前源码由 Git 管理。
- 预览模式的可写数据目录调整为进程独立临时目录，恢复网络操作被禁用；QA 宿主使用独立 bundle ID，未加载或修改用户的通道目录。

## 构建与回归

`zsh build.sh` 编译成功，签名检查通过，版本 `1.1.0`，build `3`，arm64、ad-hoc 签名。

`zsh test.sh --real-config`：

```text
PASS: real node read-only snapshot validates in both bundled cores; credentials removed with test directory
PASS: 53 behavior checks (packages, merge, conflicts, deletion, restore, storage, recovery ownership, stale callbacks, rollback, core config)
PASS 10: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS 11: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS 01: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS 00: atomic hot reload + HTTP/TLS domains + original/node DNS selection
PASS: 75 integration assertions; same sing-box PID throughout, affected connections closed and other service retained
```

新增七项搜索/筛选行为检查：名称大小写、稳定 ID、简介匹配、空查询保留安装顺序、按实际开启状态筛选、查询与状态取交集、未运行的偏好不冒充开启状态。

回归测试仍只使用本机回环假出口与只读节点快照，不启动特权助手、不改系统代理、不访问外网。

## 原生 UI

通过 `zsh Tests/preview-layout.sh` 构建实际产品视图的隔离宿主，然后用电脑工具实际查看和操作：

- Standard：820 × 580、两个默认通道。查看浅色原生布局，选择 Bilibili 后右侧同步切换；配置页提供元数据、折叠规则与 JSON 编辑入口。
- Compact：700 × 480、二十个通道、长名称及明确标记的长示例测试结果。左侧和右侧分别滚动后，工具栏、打开/测试按钮、详情分段与页脚仍在原位置；名称截断/两行标题没有挤掉按钮。
- 在 Compact 中输入查询、切换“已开启”筛选、显示全部，确认筛选结果与空态正确，右侧选择保持稳定。只在点击结果行时切换诊断对象。
- Dark：820 × 580、深色预设独立宿主。已查看实际渲染，检查文字、选中行、图标、分段控件与分隔线；⌘F 后输入查询能筛选列表。
- 所有预览开关均不建立网络会话；预览中的长结果和额外通道是布局示例，不是连通性或播放证据。

网络保护核对：调整前记录原应用/核心 PID、系统代理输出哈希与 v2rayN 源配置哈希；构建及测试后原 PID 仍存活，两个哈希相同。没有退出当前正式应用。需要用户方便时先关闭通道、退出旧实例，再打开新版本，以加载新界面。

## 边界

本次没有重做真实管理员 TUN、系统代理恢复、QUIC、公司网络歌曲和 Bilibili 播放测试，也未声称完成完整 VoiceOver 实测。既有证据与限制见 `VALIDATION.md`。本次布局采用原生列表和独立开关，所有控件带可访问性名称；细项依旧可以从右侧更多菜单访问。

版本管理：项目现已初始化 Git，基线为 `v1.1.0`。旧源码副本、旧应用和 1.0 归档已按用户要求清理。构建只在替换过程中保留临时回退副本，成功后删除。源码归档采用白名单，不含 `.git`、用户运行数据、节点配置、构建缓存、QA 临时目录。
