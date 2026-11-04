# 暗渡 · Underpass

原生 macOS 服务通道工具，复用 v2rayN 当前选中的 Xray 节点，将命中通道规则的流量交给该节点。内置 QQ 音乐和 Bilibili 通道，也可通过 `.channel.json` 文件添加其他服务。

## 功能

- 独立开启或关闭各个通道，多个通道共用一个网络会话。
- 双栏界面，支持搜索、筛选，以及查看所选通道的概览、连接和配置。
- 导入前预览变更，支持编辑、导出、排序、移除通道及撤销最近一次移除。
- 提供 HTTPS 连通性测试和当前连接记录。
- 支持跟随系统、浅色和深色外观。

## 环境要求

- Apple Silicon Mac，macOS 13 或更高版本。
- 已安装 v2rayN，并使用 Xray 节点。
- 从源码构建需要 Xcode Command Line Tools 和 Python 3。

构建脚本从 `~/Library/Application Support/v2rayN/bin/` 读取 `sing_box/sing-box` 和 `xray/xray`，并将两个核心复制进应用包。

## 构建与运行

在项目根目录执行：

```sh
zsh build.sh
open outputs/暗渡.app
```

更新正在运行的应用前，请先关闭全部通道并退出应用，再重新构建。

## 使用方法

1. 在 v2rayN 中选中节点并保持运行，关闭 v2rayN 的 TUN 模式及其他接管默认路由的 VPN。
2. 打开暗渡，确认顶部已识别当前节点。
3. 开启左侧需要的通道，按系统提示完成管理员授权。
4. 等待通道显示“已开启”，再打开对应应用或网页。首次开启后，建议重开应用或网页以建立新连接。
5. 在右侧查看连接记录，或点击“测试连通性”检查通道配置中的 HTTPS 端点。

关闭通道会撤销它的额外规则；与其他开启通道重叠的规则仍会生效。最后一个通道关闭后，应用恢复由它接管的系统代理设置并结束会话。

每次启动应用时，通道均保持关闭。节点或网络发生变化导致会话停止后，需要手动重新开启。

## 自定义通道

点击顶部“导入”，或将 `.channel.json` 文件拖入左侧列表，审阅预览后合并导入。新通道默认关闭；更新已有通道时，未涉及的通道保留，本地修改按合并规则处理。

通道包可配置域名、进程或应用匹配规则、DNS 策略、打开入口及 HTTPS 测试地址。可参考预装包创建自己的通道：

- [QQ 音乐](Resources/Channels/01-qqmusic.channel.json)
- [Bilibili](Resources/Channels/02-bilibili.channel.json)
- [通道格式与更新规则](Docs/CHANNEL-FORMAT.md)
- [JSON Schema](Resources/channel.schema.json)

## 测试与打包

```sh
zsh test.sh
zsh package.sh
```

`test.sh` 运行行为检查和本机回环集成测试；添加 `--real-config` 可额外校验当前 v2rayN 节点配置的只读副本。`package.sh` 需要先完成构建，生成的应用归档、源码归档及校验文件位于 `outputs/`。

## 使用说明与限制

- 支持原系统代理未开启，或指向当前 v2rayN 本地端口的情况。PAC、自动发现代理及其他代理端点暂不支持。
- HTTPS 测试结果仅表示配置中的端点可达，歌曲或视频播放需要实际验证。已有连接、浏览器加密 DNS 等也可能影响规则命中。
- 通道配置保存在 `~/Library/Application Support/Underpass/channels.json`。同目录的 `Sessions/` 包含临时运行数据，可能涉及节点凭据，请勿上传。
- 构建产物使用本地 ad-hoc 签名，未经 Apple 公证。特权 TUN 启停、代理恢复及实际播放的验证范围见[验证记录](Docs/VALIDATION.md)；界面验证见[布局验证记录](Docs/VALIDATION-1.1.md)。

第三方核心与规则来源见 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。
