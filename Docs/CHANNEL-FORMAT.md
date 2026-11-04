# Underpass 通道包 v1

单个 UTF-8 JSON 对象，文件名以 `.channel.json` 结尾，最多 2 MB；一次最多导入 100 个，安装目录最多 200 项。预装包与导入包格式完全相同。

```json
{
  "schemaVersion": 1,
  "id": "org.example.service",
  "version": "1.0.0",
  "name": "示例服务",
  "icon": "globe",
  "summary": "网页与接口",
  "match": {
    "domains": ["api.example.com"],
    "domainSuffixes": ["media.example.com"],
    "processNames": [],
    "applicationPaths": []
  },
  "dns": "node",
  "entry": {"kind": "url", "value": "https://api.example.com/"},
  "tests": [{"name": "接口", "url": "https://api.example.com/"}],
  "sources": []
}
```

所有数组必须出现，可以为空。`entry` 可省略或设为 `null`。其他顶层字段必填；未知字段被拒绝，避免把未实现能力误当成已生效。主程序管理节点、凭据、端口、TUN 和生命周期；包没有脚本、核心配置、凭据、远程规则拉取或任意出站能力。

| 字段 | v1 支持的语义 |
|---|---|
| schemaVersion | 仅 `1`；不猜测未来格式 |
| id | 稳定主键，3–96 位小写 ASCII 字母、数字、点、连字符 |
| version | 三段非负整数 major.minor.patch；旧版跳过，相同版本内容变化仍预览 |
| name / summary | 名称最长 80，简介最长 500；同名不视为同 ID |
| icon | SF Symbols：music.note、play.rectangle、globe、network、cloud、books.vertical、gamecontroller、bubble.left.and.bubble.right；其他名称回退 network |
| domains | 精确域名；不包含子域名 |
| domainSuffixes | 域名本身及点边界下的子域名；不接受通配符、URL、IP、单独顶级域、`.invalid`、`.local`；ASCII/Punycode |
| processNames | 进程名精确匹配，需要真实特权进程识别；不接受路径 |
| applicationPaths | 绝对 `.app` 路径，匹配该包 `/Contents/` 内的进程；不是 bundle ID |
| dns | `node`：匹配的域名经所选节点 DoH；`system`：原 DNS。进程规则自身不决定域名 DNS |
| entry | `url` 仅 HTTPS；`application` 仅 `/Applications/` 下 `.app`；打开操作仅由用户点击触发 |
| tests | 最多 8 个匹配本包域名的 HTTPS 端点；测试发 GET，无脚本、Cookie、token 或媒体播放推断 |
| sources | 最多 16 个 HTTPS 来源链接，仅作记录，不自动下载 |

匹配总量最多 4096 条。匹配类型、同类型数组和多个开启通道之间均取“或”（并集），不是依次覆盖。命中流量强制送入同一个选定节点。DNS 中有任一开启通道声明 node 即优先使用节点 DNS。未命中流量按会话启动前受支持的系统代理路径处理，TUN 未命中流量按原直连路径处理。应用/进程匹配可能覆盖该进程的全部网络请求，导入前应审阅其作用范围。

## 更新语义

安装项分别保存上游基线、原始包字节、本地有效配置、上次启用偏好；列表顺序独立保留。

- 同 ID、相同规范化内容跳过。顺序和空白差异不构成规则变化。
- 新 ID 默认追加且关闭。同名不同 ID 先选择另建或明确的合并目标。
- 标量字段：本地未改则跟随新包；本地与新包都偏离旧包且不一致时保留本地并列出冲突。
- 规则数组：新包相对旧包的新增去重加入；明确删除旧项会在预览列出并应用；本地新增保留，本地删除不被未改的上游重新加入。
- 多字段合并若产生不合法配置，整次导入拒绝，原列表与运行规则保留。可调整本地配置后重新预览。
- 未在导入中出现的通道和规则不受影响。不自动降级。相同版本但内容变化仍须用户审阅。
- 导入确认后，更新当前开启通道的规则；新项不启动。内核与缓存操作失败回退；持久化失败也回退运行状态。跨规则文件不承诺内核级原子切换或零中断。
- 移除只删安装副本，预装包留下墓碑；撤销恢复顺序、本地配置与偏好，但不会自动启动。

可直接复制 `Resources/Channels/` 中的包作为起点，改用自己的稳定 ID。不要通过共享包分发节点凭据或运行会话。
