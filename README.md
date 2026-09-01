# OpenVPN for HarmonyOS

基于开源 Android 客户端 [ics-openvpn](https://github.com/schwabe/ics-openvpn/)（`_ref/ics-openvpn`）移植的 HarmonyOS（ArkTS/ArkUI）版本。

- bundleName：`com.razor.tools.openvpn`
- 目标版本：HarmonyOS 6.1.0 (API 23)（使用 DevEco Studio 6.1 构建，编译 SDK 24）
- 界面与功能对照 Android 原版复刻，品牌配色以桌面图标蓝为核心（primary `#1456B8` / dark `#1E3862` / accent `#1F7EFA`）；橙色 `#F5821F` 仅用于连接中和提醒状态
- 资源：英文（base）+ 简体中文（zh_CN），文案对照原版 strings.xml / values-zh-rCN

## 构建与运行

命令行（使用 DevEco 自带工具链）：

```bash
export PATH="/c/Program Files/Huawei/DevEco Studio/tools/node:$PATH"
export DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
"/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名，需在 DevEco Studio 中配置签名后安装运行；或直接用 DevEco Studio 打开工程运行）。

## 核心引擎与架构（OpenVPN3）

VPN 数据面使用**官方 OpenVPN3 C++ 客户端核心**，编译为 arm64 动态库 `libovpnexec.so` 经 NAPI 供 ArkTS 调用：

- **第三方库**（`native/third_party/` git 子模块）：`openvpn3`（固定 `release/3.10` 分支）、OpenSSL 3.4.1（TLS/加密后端）、asio 1.32.0（异步网络 I/O）、lz4（压缩）、fmt
- **调用链**：ArkTS `vpnservice/OvpnEngine.ets` → NAPI 封装层 `entry/src/main/cpp/ovpn_napi.cpp` → openvpn3 C++ 核心
- **职责划分**：openvpn3 核心负责连接建立（TLS 握手、认证挑战含 CR_TEXT/OTP 交互、数据通道加解密）；核心通过 `tun_builder_*` 回调向 `VpnServiceAbility`（VpnExtensionAbility）提供路由/DNS/TUN 参数，由鸿蒙 VPN Extension 建立虚拟网卡
- **统计**：隧道建立后引擎每秒经 `getTunStats()` 读取 TUN 收发字节，回传 ArkTS 层（`VpnStatus.updateByteCount` → `VpnTrafficStore` 按配置/按日持久化）
- **协议兼容性**："OpenVPN 3" 是实现而非新线缆协议——线上协议与 OpenVPN 2.x 服务端完全兼容（UDP/TCP 传输、TLS 握手、NCP 密码套件协商如 AES-GCM），标准 `.ovpn` 配置文件通用，可直连常见 OpenVPN 2.x 服务器（如 openvpn 官方镜像容器）

Native 构建前置（改动 `native/` 下代码时需要，纯 ArkTS 改动可跳过）：

```bash
git submodule update --init
bash native/scripts/build-openssl.sh   # 交叉编译 OpenSSL 到 native/build/openssl-ohos/install
```

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
- 主界面三个 Tab：Profiles（配置列表：连接/断开、铅笔编辑、默认 VPN 与红色警告副标题、空列表引导、通知权限提示）/ Graph（实时速率行 + 每个 VPN 配置的流量统计卡片：今日/本月用量、最近 7 天逐日明细，下载红/上传蓝）/ Settings（应用行为 + VPN 行为全部设置项）；About 页面包含 15 条可展开 FAQ
- VPNPreferences 编辑页八个 Tab：Basic（认证类型驱动的动态区块）/ Server List（服务器卡片+随机开关+FAB）/ IP and DNS / Routing / Authentication-Encryption / Advanced / Allowed Apps / Generated Config（实时生成+复制）；顶栏删除/复制
- 导入：工具栏 添加(+)/导入(.ovpn)/排序/URL导入（AS/URL+Basic Auth）→ ConfigConverter（解析、重名处理、兼容模式、TLS profile、设为默认、缺失文件手动补选、导入日志）
- 日志窗口：日志级别滑条(1-4)、时间戳格式（无/短/ISO）、连接时清空、长按复制单条、整份日志复制、断开、编辑 VPN；底部上传/下载/状态栏
- 断开确认、配置错误对话框、凭据缺失提示等交互流程

**VPN 服务（HarmonyOS 平台 API）**
- `vpnservice/VpnServiceAbility.ets`：`type:"vpn"` 的 VpnExtensionAbility；连接流程（校验→生成配置→状态机→TCP 可达性探测→通知），`startTun`（`vpnExtension.createVpnConnection`/`create`/protect 架构就绪）

## 已知限制（与 Android 版差异）

- ~~原生 OpenVPN 引擎未捆绑~~（已解决）：native 层现已捆绑官方 OpenVPN3 核心（见「核心引擎与架构」），可真实建立隧道；构建时需先初始化子模块并交叉编译 OpenSSL。
- 系统 KeyChain 证书（Android Certificate/外部认证器类型）：HarmonyOS 无对应公开 API，界面保留但提示不可用（建议使用证书/PKCS12 文件认证）。
- 分应用 VPN：三方应用无法枚举已装应用，改为手动输入包名列表（存储结构与原版一致，并映射到 `trustedApplications`/`blockedApplications`）。
- 开机自启（Keep VPN connected）：保留设置项；HarmonyOS 三方应用无开机广播。
- OpenSSL 速度测试：仅保留入口提示（需 native OpenSSL）。
