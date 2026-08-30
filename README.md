# OpenVPN for HarmonyOS

基于开源 Android 客户端 [ics-openvpn](https://github.com/schwabe/ics-openvpn/)（`_ref/ics-openvpn`）移植的 HarmonyOS（ArkTS/ArkUI）版本。

- bundleName：`com.razor.tools.openvpn`
- 目标版本：HarmonyOS 6.1.0 (API 23)（使用 DevEco Studio 6.1 构建，编译 SDK 24）
- 界面与功能对照 Android 原版复刻，Material 配色（primary `#3F51B5` / dark `#303F9F` / accent `#FFA726`）
- 资源：英文（base）+ 简体中文（zh_CN），文案对照原版 strings.xml / values-zh-rCN

## 构建与运行

命令行（使用 DevEco 自带工具链）：

```bash
export PATH="/c/Program Files/Huawei/DevEco Studio/tools/node:$PATH"
export DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
"/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名，需在 DevEco Studio 中配置签名后安装运行；或直接用 DevEco Studio 打开工程运行）。

## 已实现（对照 Android 版）

**核心数据层（忠实移植）**
- `core/VpnProfile.ets`：全部 70+ 字段、认证类型（9 种）、X509 校验类型、`checkProfile` 全部校验规则、`clearDefaults`、`openVpnEscape`/`insertFileData`/`cidrToIPAndNetmask` 等纯逻辑；序列化改为显式 JSON
- `core/ConfigParser.ets`：`.ovpn/.conf` 解析器完整移植（OpenVPN C 解析器的字符级状态机、内联文件 `<ca>...</ca>`、全部指令映射表、ignore/unsupported 选项表、`<connection>` 块递归解析、AS 元信息）
- `core/Connection.ets`：多服务器条目（UDP/TCP、HTTP/SOCKS5/Orbot 代理、代理认证、超时、自定义选项、`getConnectionBlock`）
- `core/ConfigGenerator.ets`：`getConfigFile()` 生成 OpenVPN 配置文本（管理接口、setenv、路由/DNS/证书/压缩/TLS-auth/自定义选项等全部分支）
- `core/ProfileManager.ets`：profile 增删改查、按名称/LRU 排序、lastConnected/默认 VPN、JSON 持久化（filesDir/<uuid>.json）
- `core/CIDRIP.ets`、`PasswordCache.ets`、`X509Utils.ets`（DER 扫描提取证书 CN）

**状态层**
- `core/VpnStatus.ets`：日志缓冲（1000 条）、状态机（OpenVPN state → level 映射）、Log/State/ByteCount 监听器、跨进程快照持久化
- `core/TrafficHistory.ets`：秒/分/时三级流量采样（图表数据源）

**界面（对照原版布局/菜单/交互复刻）**
- 主界面三个 Tab：Profiles（配置列表：连接/断开、铅笔编辑、默认 VPN 与红色警告副标题、空列表引导、通知权限提示）/ Graph（三张流量图：红=下行 蓝=上行、对数刻度开关）/ Settings（应用行为 + VPN 行为全部设置项）；About 页面包含 15 条可展开 FAQ
- VPNPreferences 编辑页八个 Tab：Basic（认证类型驱动的动态区块）/ Server List（服务器卡片+随机开关+FAB）/ IP and DNS / Routing / Authentication-Encryption / Advanced / Allowed Apps / Generated Config（实时生成+复制）；顶栏删除/复制
- 导入：工具栏 添加(+)/导入(.ovpn)/排序/URL导入（AS/URL+Basic Auth）→ ConfigConverter（解析、重名处理、兼容模式、TLS profile、设为默认、缺失文件手动补选、导入日志）
- 日志窗口：日志级别滑条(1-4)、时间戳格式（无/短/ISO）、连接时清空、长按复制单条、整份日志复制、断开、编辑 VPN；底部上传/下载/状态栏
- 断开确认、配置错误对话框、凭据缺失提示等交互流程

**VPN 服务（HarmonyOS 平台 API）**
- `vpnservice/VpnServiceAbility.ets`：`type:"vpn"` 的 VpnExtensionAbility；连接流程（校验→生成配置→状态机→TCP 可达性探测→通知），`startTun`（`vpnExtension.createVpnConnection`/`create`/protect 架构就绪）

## 已知限制（与 Android 版差异）

- **原生 OpenVPN 引擎未捆绑**：隧道建立需要 native 库（openvpn/libovpnexec.so 或 openvpn3），本工程为纯 ArkTS。连接尝试会执行真实的 TCP 可达性探测并在日志中明确报告“native 引擎不可用”。配置管理、导入、解析、生成等全部功能可正常使用；接入引擎时无需改动 UI。
- 系统 KeyChain 证书（Android Certificate/外部认证器类型）：HarmonyOS 无对应公开 API，界面保留但提示不可用（建议使用证书/PKCS12 文件认证）。
- 分应用 VPN：三方应用无法枚举已装应用，改为手动输入包名列表（存储结构与原版一致，并映射到 `trustedApplications`/`blockedApplications`）。
- 开机自启（Keep VPN connected）：保留设置项；HarmonyOS 三方应用无开机广播。
- OpenSSL 速度测试：仅保留入口提示（需 native OpenSSL）。
