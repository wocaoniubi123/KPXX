# KPXX

自用入口聚合应用（iOS / Flutter）。第一个入口为 51吃瓜（分类浏览 + 视频播放 + 系列选集）。

## 功能

- 入口页：大按钮 + logo，后续入口可继续在 `lib/main.dart` 添加
- 51吃瓜首页：分类 tab（今日吃瓜 / 热门大瓜 / 网红黑料 / 必看大瓜 …）+ 双列瀑布流卡片 + 无限翻页
- 搜索：文章关键词搜索
- 详情页：顶部视频播放、标题/时间、系列选集（标题带"第 N 集"自动聚合成集数值选条）、正文图片
- 播放器：内置播放（m3u8+HLS，视频源 auth_key 时效签名，过期重进详情页自动刷新）、全屏模式、**左右滑动快进/快退 ±10 秒**、进度条拖拽
- 域名回退：51cg1.com / 51cgo13.com / cg51.com / chigua.com / cgwz1.com / cgwz2.com 依次尝试

## 构建（GitHub Actions → macOS runner）

仓库须配置 Secrets（仓库 Settings → Secrets and variables → Actions）：

| Secret | 值 |
|--------|----|
| `P12_BASE64` | 证书文件的 base64（`base64 -w0 证书文件.p12`） |
| `PROFILE_BASE64` | 描述文件 base64（`base64 -w0 描述文件.mobileprovision`） |
| `P12_PASSWORD` | p12 密码（当前：`1`） |

触发 `main` push 或手动 `workflow_dispatch`，产物 `kpxx-ipa`（Artifacts）里下载 `.ipa`。

安装：iPhone 上有签名工具（AltStore / Sideloadly / 爱思助手等）用描述文件里的设备 UDID 安装。
设备被移除或更换需重新生成描述文件。

## 本地开发（需要 macOS / Flutter SDK）

```bash
flutter pub get
flutter run   # iOS 模拟器
```

`ios/` 目录不入库，由 CI `flutter create --platforms=ios` 生成。

## 签名配置（写死在 workflow）

- Bundle ID: `ysc.tool6041.sign`（必须与描述文件匹配）
- Team: `Z8J7VYHQZF`
- Export: `ad-hoc`
- 证书到期：2026-11-20（到期后需重新生成 p12/描述文件并更新 Secrets）
