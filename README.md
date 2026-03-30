# Claude Remote

> 一个 vibe 出来的，为 vibe coding 服务的 app

Claude Code 的移动端/其他桌面端遥控器。远程管理会话、查看对话、审批操作。

## 架构

```
┌─────────────┐     WebSocket / REST     ┌──────────────────┐
│  Flutter App │ ◄─────────────────────► │  Node.js Backend  │
│ (手机/桌面)   │    http://host:3200     │  (Fastify + SDK)  │
└─────────────┘                          └────────┬─────────┘
                                                  │
                                         Claude Agent SDK
                                                  │
                                         ~/.claude/projects/
                                        (读取/创建/resume session)
```

- **后端**：Fastify 服务，通过 Claude Agent SDK 读取本机所有 CC session、发起新对话、处理审批
- **前端**：Flutter 跨平台 app，作为遥控器连接后端

## 功能

- 查看本机所有 Claude Code 会话（CLI/IDE/SDK 创建的都能看到）
- Resume 任意历史 session 继续对话
- 实时流式输出（WebSocket 推送）
- 工具调用审批（Bash/Edit/Write 等，底部抽屉弹出）
- AskUserQuestion 交互（Claude 提问时弹出选项面板）
- 文件变动自动刷新会话列表
- Markdown 渲染（代码块、表格、链接）
- 暗色模式跟随系统

## 快速开始

### 1. 启动后端

```bash
cd backend
pnpm install
pnpm run dev
```

后端默认监听 `0.0.0.0:3200`，可通过环境变量覆盖：

```bash
HOST=100.x.x.x PORT=3200 pnpm run dev
```

> 后端依赖本机已安装的 Claude Code，使用你 CLI 的 OAuth 认证，不需要 API key。

### 2. 运行 Flutter App

```bash
flutter pub get
flutter run
```

在连接页输入后端地址：

| 场景 | 地址 |
|------|------|
| Tailscale 组网 | `http://100.x.x.x:3200` |
| 同局域网 | `http://192.168.x.x:3200` |
| Android 模拟器 | `http://10.0.2.2:3200` |
| iOS 模拟器 | `http://localhost:3200` |

### 3. 使用

1. 连接后看到所有本机 CC 会话
2. 点进任意 session 查看完整对话历史
3. 在输入框发消息 resume 该 session 继续对话
4. Claude 需要审批时底部自动弹出审批面板
5. 下拉刷新 / 文件变动自动更新列表

## 推荐用法

| 场景 | 操作 |
|------|------|
| 出门前 CLI 在跑任务 | Ctrl+C 退出 CLI，手机上 resume 继续 |
| 手机上发起新任务 | 会话列表 + 输入 prompt 和工作目录 |
| 在外面查看进度 | 点进 session 查看历史消息 |

> **注意**：只有通过本 app 后端发起/resume 的 session 才支持实时推送和审批交互。CLI 里正在跑的 session 只能只读查看历史。

## 构建发布

推 tag 触发 GitHub Actions 自动构建：

```bash
git tag v1.0.0
git push origin v1.0.0
```

产出物：

| 平台 | 产出 | 签名 |
|------|------|------|
| Android | APK | Keystore 签名 |
| Linux | AppImage | 无需签名 |
| macOS | DMG | Ad-hoc 自签（首次打开需右键打开） |
| iOS | IPA (unsigned) | 需通过 AltStore/Sideloadly 安装 |

### Android 签名配置

本地开发：编辑 `android/key.properties`（已 gitignore）：

```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=你的alias
storeFile=/path/to/your.jks
```

CI：在 GitHub repo Settings > Secrets 添加：

- `ANDROID_KEYSTORE_BASE64`：`base64 -i your.jks | pbcopy`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

## 后端 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/health` | GET | 健康检查 |
| `/api/sessions` | GET | 列出所有 session |
| `/api/sessions/:id/messages` | GET | 获取会话消息（支持分页） |
| `/api/sessions/send` | POST | 发送消息（新建或 resume） |
| `/api/sessions/:id` | DELETE | 停止运行中的 session |
| `/api/approvals` | GET | 获取待审批列表 |
| `/api/approvals/:id` | POST | 响应审批 |
| `/ws` | WebSocket | 实时推送 |

## 技术栈

- **后端**：Node.js + Fastify + TypeScript + `@anthropic-ai/claude-agent-sdk`
- **前端**：Flutter 3 + Provider + Dio + WebSocket + flutter_markdown_plus
- **CI**：GitHub Actions

## License

MIT
