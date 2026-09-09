1. 修改 `entry/src/main/ets/components/tabs/ProfilesTab.ets`，保留现有 `VpnStatus` 刷新和卡片状态逻辑，不引入新的状态模型。
2. 移除 `ConnectionStatusSummary()` 及其在“OpenVPN 配置”标题下的一行彩色圆点/动态连接文案调用。
3. 按 `FrpTab.ets` 的 `StatusSummary()` 视觉结构新增 OpenVPN 摘要 Builder：
   - “配置”：显示 `this.profiles.length`；
   - “运行中”：统计当前 `ProfileCardView.active` 的数量，颜色在数量大于 0 时使用 `Theme.STATUS_SUCCESS`；
   - “异常”：根据当前全局 `VpnStatus.lastState` 是否为 `AUTH_FAILED` 或 `SESSION_EXPIRED`，并确认存在对应活动/最近连接配置后显示 1，否则显示 0，数量大于 0 时使用 `Theme.STATUS_ERROR`。
   - 复用 FRP 的 12sp 标签、22sp 粗体数字、16vp 内边距、卡片背景、分隔线和 12vp 圆角，保证两类配置列表一致。
4. 在非空 OpenVPN 配置列表分支中调用新的三列摘要 Builder，保持空列表页面和配置卡片不变。
5. 检查 ArkTS 类型/响应式依赖，确保摘要会随现有 2 秒轮询、状态监听和 `reload()` 更新；然后运行项目已有测试/静态检查，并执行 HarmonyOS 构建验证。若构建仅出现仓库基线告警，将区分记录告警与本次改动错误。