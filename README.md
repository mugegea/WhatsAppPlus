# WhatsAppPlus

WhatsApp 功能增强插件（iOS 越狱 / TrollStore）

## 功能

### 🌐 发送翻译
- 输入中文停顿 1.5 秒，自动翻译为双语显示在输入框
- 点发送即发出，可选双语（中英对照）或只发英语
- 三引擎链路：Google Cloud 官方 API → Google 免费接口 → MyMemory 兜底
- 翻译缓存，相同内容不重复请求

### 🎨 图标与外观
- 自由更换应用桌面图标
- 解锁 Meta 实验室 Liquid Glass 毛玻璃 UI

## 安装

### 越狱设备（Dopamine / palera1n）
1. 下载 Release 中的 `.deb` 包
2. 用 Sileo / Zebra 安装

### TrollStore
1. 下载 Release 中的 trollstore 包
2. 用 TrollStore 安装

## 设置

进入 WhatsApp 设置页，找到「WhatsAppPlus 设置」：
- **发送时自动翻译**：输入中文自动转英语
- **双语发送**：开=中英双语发出，关=只发英语
- **发送目标语言**：默认英语
- **翻译引擎**：Google 免费 / Google Cloud（需自配 API Key）

## 兼容性

- iOS 15.0+（Dopamine 无根越狱，arm64 / arm64e）
- TrollStore（用 trollstore 包）
- WhatsApp 官方版（App Store）

## 构建

需要 theos 环境：

```bash
# 安装 theos 后
make package          # 打包 deb
make package install  # 打包并安装到已连接设备（需配置 THEOS_DEVICE_IP）
```

GitHub Actions 会自动构建并发布 Release。

## 作者

telegram@bengege — https://t.me/bengege

