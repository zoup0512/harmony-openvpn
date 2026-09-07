/**
 * FRP configuration list. Runtime ownership deliberately stays outside this
 * component: a start/stop callback must report status through FrpStatus. When
 * no runtime callback is installed, the UI records UNAVAILABLE rather than
 * presenting a false RUNNING state.
 */

import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { FileUtil } from '../../common/FileUtil';
import { Theme } from '../../common/Theme';
import { FrpConfig } from '../../core/FrpConfig';
import { FrpConfigManager } from '../../core/FrpConfigManager';
import { FrpLogEntry, FrpLogStore } from '../../core/FrpLogStore';
import { FrpStatus, FrpRunState, FrpStatusSnapshot } from '../../core/FrpStatus';
import { FrpTemplateManager } from '../../core/FrpTemplateManager';
import { FrpType } from '../../core/FrpType';
import { FrpValidator } from '../../core/FrpValidator';
import { FrpController } from '../../frp/FrpController';
import { ConfirmDialog, ConfirmDialogModel } from '../ConfirmDialog';

export type FrpRuntimeAction = (config: FrpConfig) => Promise<void> | void;

@Component
export struct FrpTab {
  @State private frpcConfigs: FrpConfig[] = [];
  @State private frpsConfigs: FrpConfig[] = [];
  @State private renderTick: number = 0;
  @State private expandedIds: string[] = [];
  private timerId: number = -1;

  onImport: () => void = () => {
    promptAction.showToast({ message: '请由宿主提供 FRP 配置导入回调' });
  };
  onNew: () => void = () => {
    promptAction.showToast({ message: '请由宿主提供 FRP 新建回调' });
  };
  onRefresh: () => void = () => {
  };
  onStart?: FrpRuntimeAction = undefined;
  onStop?: FrpRuntimeAction = undefined;

  private deleteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: false }),
    autoCancel: true,
    customStyle: true
  });
  private pendingDelete?: FrpConfig = undefined;

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      FrpConfigManager.init(context);
      FrpTemplateManager.init(context);
    }
    this.reload();
    this.timerId = setInterval(() => {
      FrpStatus.restoreFromDisk();
      // 子页面返回时同步名称、复制与删除结果；稳定 key 不重建卡片。
      let all = FrpConfigManager.list();
      this.frpcConfigs = all.filter((config: FrpConfig) => config.type === FrpType.FRPC);
      this.frpsConfigs = all.filter((config: FrpConfig) => config.type === FrpType.FRPS);
      this.renderTick++;
    }, 1000) as number;
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private reload(): void {
    let all = FrpConfigManager.refresh();
    this.frpcConfigs = all.filter((config: FrpConfig) => config.type === FrpType.FRPC);
    this.frpsConfigs = all.filter((config: FrpConfig) => config.type === FrpType.FRPS);
    this.renderTick++;
  }

  private userRefresh(): void {
    this.reload();
    this.onRefresh();
  }

  private status(config: FrpConfig, revision: number = 0): FrpStatusSnapshot {
    return FrpStatus.get(config);
  }

  private isActive(config: FrpConfig, revision: number = 0): boolean {
    return FrpStatus.isActive(this.status(config).state);
  }

  private statusLabel(state: FrpRunState): string {
    switch (state) {
      case FrpRunState.STARTING:
        return '启动中';
      case FrpRunState.RUNNING:
        return '运行中';
      case FrpRunState.STOPPING:
        return '停止中';
      case FrpRunState.FAILED:
        return '启动失败';
      case FrpRunState.CRASHED:
        return '异常退出';
      case FrpRunState.UNAVAILABLE:
        return '核心不可用';
      default:
        return '已停止';
    }
  }

  private statusColor(state: FrpRunState): string {
    if (state === FrpRunState.RUNNING) {
      return Theme.STATUS_SUCCESS;
    }
    if (state === FrpRunState.STARTING || state === FrpRunState.STOPPING) {
      return Theme.STATUS_CONNECTING;
    }
    if (state === FrpRunState.FAILED || state === FrpRunState.CRASHED || state === FrpRunState.UNAVAILABLE) {
      return Theme.STATUS_ERROR;
    }
    return Theme.TEXT_SECONDARY;
  }

  private statusBackground(state: FrpRunState): string {
    if (state === FrpRunState.RUNNING) {
      return Theme.STATUS_SUCCESS_BG;
    }
    if (state === FrpRunState.STARTING || state === FrpRunState.STOPPING) {
      return Theme.STATUS_CONNECTING_BG;
    }
    if (state === FrpRunState.FAILED || state === FrpRunState.CRASHED || state === FrpRunState.UNAVAILABLE) {
      return Theme.STATUS_ERROR_BG;
    }
    return Theme.STATUS_IDLE_BG;
  }

  private shortMessage(message: string): string {
    let value = message.replace(/[\r\n]+/g, ' ').trim();
    if (value.length > 150) {
      return value.substring(0, 147) + '...';
    }
    return value;
  }

  private latestLogs(config: FrpConfig, revision: number = 0): FrpLogEntry[] {
    let all = FrpLogStore.read(config, 4);
    return all.slice(Math.max(0, all.length - 4));
  }

  private logText(entry: FrpLogEntry): string {
    let stamp = new Date(entry.timestamp);
    let two = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    let time = `${two(stamp.getHours())}:${two(stamp.getMinutes())}:${two(stamp.getSeconds())}`;
    return `${time} ${entry.message}`;
  }

  private typeLabel(type: FrpType): string {
    return type === FrpType.FRPC ? 'frpc 客户端' : 'frps 服务端';
  }

  private toggleExpanded(config: FrpConfig): void {
    let index = this.expandedIds.indexOf(config.key);
    if (index === -1) {
      this.expandedIds = this.expandedIds.concat([config.key]);
    } else {
      let next = this.expandedIds.slice();
      next.splice(index, 1);
      this.expandedIds = next;
    }
  }

  private isExpanded(config: FrpConfig): boolean {
    return this.expandedIds.indexOf(config.key) !== -1;
  }

  private requestStart(config: FrpConfig): void {
    let content = FrpConfigManager.read(config);
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      let message = validation.message === '' ? '配置验证失败' : validation.message;
      FrpStatus.update(config, FrpRunState.FAILED, message);
      promptAction.showToast({ message: message });
      this.renderTick++;
      return;
    }

    let action = this.onStart;
    if (action === undefined) {
      let message = 'FRP 运行核心不可用，未启动配置';
      FrpStatus.markUnavailable(config, message);
      promptAction.showToast({ message: message });
      this.renderTick++;
      return;
    }
    try {
      Promise.resolve(action(config)).then(() => {
        // A callback must update FrpStatus after the child process really
        // starts. Do not turn a returned Promise into a false RUNNING state.
        FrpStatus.restoreFromDisk();
        this.renderTick++;
      }).catch((error: Error) => {
        let message = `FRP 运行核心不可用：${error.message}`;
        FrpStatus.markUnavailable(config, message);
        promptAction.showToast({ message: message });
        this.renderTick++;
      });
    } catch (error) {
      let message = `FRP 运行核心不可用：${(error as Error).message}`;
      FrpStatus.markUnavailable(config, message);
      promptAction.showToast({ message: message });
      this.renderTick++;
    }
  }

  private requestStop(config: FrpConfig): void {
    let action = this.onStop;
    if (action === undefined) {
      let message = 'FRP 运行核心不可用，未停止配置';
      FrpStatus.markUnavailable(config, message);
      promptAction.showToast({ message: message });
      this.renderTick++;
      return;
    }
    try {
      Promise.resolve(action(config)).then(() => {
        // Stopped is only displayed after the runtime callback persists it.
        FrpStatus.restoreFromDisk();
        this.renderTick++;
      }).catch((error: Error) => {
        let message = `FRP 停止失败：${error.message}`;
        FrpStatus.update(config, FrpRunState.FAILED, message);
        promptAction.showToast({ message: message });
        this.renderTick++;
      });
    } catch (error) {
      let message = `FRP 停止失败：${(error as Error).message}`;
      FrpStatus.update(config, FrpRunState.FAILED, message);
      promptAction.showToast({ message: message });
      this.renderTick++;
    }
  }

  private handleToggle(config: FrpConfig, enabled: boolean): void {
    if (enabled) {
      if (!this.isActive(config)) {
        this.requestStart(config);
      }
    } else if (this.isActive(config)) {
      this.requestStop(config);
    }
  }

  private edit(config: FrpConfig): void {
    if (this.isActive(config)) {
      promptAction.showToast({ message: '配置运行中，停止后才能编辑' });
      return;
    }
    router.pushUrl({ url: 'pages/FrpConfigEdit', params: { 'uuid': config.key } });
  }

  private async saveConfig(config: FrpConfig): Promise<void> {
    try {
      let content = FrpConfigManager.read(config);
      if (content === '') {
        throw new Error('配置为空或无法读取');
      }
      await FileUtil.saveText(config.fileName, content, '.toml',
        this.getUIContext().getHostContext() as common.UIAbilityContext);
      promptAction.showToast({ message: '配置已保存到手机' });
    } catch (error) {
      if ((error as Error).message !== 'cancelled') {
        promptAction.showToast({ message: `保存失败：${(error as Error).message}` });
      }
    } finally {
      this.reload();
    }
  }

  private copyConfig(config: FrpConfig): void {
    try {
      // 使用安全的独立文件名，刷新索引后顺延编号，绝不覆盖原配置。
      let all = FrpConfigManager.refresh();
      let base = FrpConfig.removeExtension(config.fileName).substring(0, 100);
      let index = 1;
      let fileName = `${base}_copy.toml`;
      while (all.some((item: FrpConfig) => item.type === config.type && item.fileName === fileName)) {
        index++;
        fileName = `${base}_copy_${index}.toml`;
      }
      FrpConfigManager.copy(config, fileName, `${config.name} 副本${index === 1 ? '' : ` ${index}`}`);
      promptAction.showToast({ message: '已创建配置副本（自启动关闭）' });
    } catch (error) {
      promptAction.showToast({ message: `复制失败：${(error as Error).message}` });
    } finally {
      this.reload();
    }
  }

  private shareConfig(config: FrpConfig): void {
    router.pushUrl({ url: 'pages/FrpConfigShare', params: { 'uuid': config.key } });
    this.reload();
  }

  private copyLog(config: FrpConfig): void {
    let text = FrpLogStore.readText(config);
    if (text === '') {
      promptAction.showToast({ message: '暂无可复制日志' });
      return;
    }
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
      .then(() => promptAction.showToast({ message: '日志已复制' }))
      .catch(() => promptAction.showToast({ message: '日志复制失败' }));
  }

  private showLog(config: FrpConfig): void {
    router.pushUrl({ url: 'pages/FrpLog', params: { 'uuid': config.key } });
  }

  private clearLog(config: FrpConfig): void {
    if (FrpLogStore.clear(config)) {
      promptAction.showToast({ message: '日志已清除' });
    } else {
      promptAction.showToast({ message: '日志清除失败' });
    }
    this.renderTick++;
  }

  private askDelete(config: FrpConfig): void {
    if (this.isActive(config)) {
      promptAction.showToast({ message: '配置运行中，停止后才能删除' });
      return;
    }
    this.pendingDelete = config;
    this.deleteDialogModel.title = '删除 FRP 配置';
    this.deleteDialogModel.message = `确定删除“${config.name}”及其日志吗？`;
    this.deleteDialogModel.cancelText = '取消';
    this.deleteDialogModel.confirmText = '删除';
    this.deleteDialogModel.dangerous = true;
    this.deleteDialogModel.onConfirm = () => {
      let target = this.pendingDelete;
      this.pendingDelete = undefined;
      FrpStatus.restoreFromDisk();
      if (target !== undefined && this.isActive(target)) {
        promptAction.showToast({ message: '配置运行中，停止后才能删除' });
        this.reload();
        return;
      }
      if (target !== undefined && FrpConfigManager.remove(target)) {
        this.reload();
        promptAction.showToast({ message: '配置已删除' });
      } else {
        promptAction.showToast({ message: '配置删除失败' });
      }
    };
    this.deleteDialogController.open();
  }

  private countActive(items: FrpConfig[], revision: number): number {
    let count = 0;
    for (let config of items) {
      if (this.isActive(config)) {
        count++;
      }
    }
    return count;
  }

  private countErrors(items: FrpConfig[], revision: number): number {
    let count = 0;
    for (let config of items) {
      let state = this.status(config).state;
      if (state === FrpRunState.FAILED || state === FrpRunState.CRASHED || state === FrpRunState.UNAVAILABLE) {
        count++;
      }
    }
    return count;
  }

  @Builder
  private StatusSummary() {
    Row() {
      Column() {
        Text('配置')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.frpcConfigs.length + this.frpsConfigs.length}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      Column() {
        Text('运行中')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.countActive(this.frpcConfigs, this.renderTick) + this.countActive(this.frpsConfigs, this.renderTick)}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countActive(this.frpcConfigs, this.renderTick) + this.countActive(this.frpsConfigs, this.renderTick) > 0 ?
            Theme.STATUS_SUCCESS : Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      Column() {
        Text('异常')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.countErrors(this.frpcConfigs, this.renderTick) + this.countErrors(this.frpsConfigs, this.renderTick)}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countErrors(this.frpcConfigs, this.renderTick) + this.countErrors(this.frpsConfigs, this.renderTick) > 0 ?
            Theme.STATUS_ERROR : Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD_BG)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(12)
  }

  @Builder
  private ActionButton(icon: Resource, label: string, selected: boolean, danger: boolean,
    action: () => void, enabled: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 }) {
        Row() {
          Image(icon).width(18).height(18).objectFit(ImageFit.Contain)
            .fillColor(!enabled ? Theme.TEXT_DISABLED :
              (selected ? Theme.WHITE : (danger ? Theme.FRP_DANGER : Theme.FRP_ACCENT)))
        }
        .width('100%').height(20)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        Text(label).fontSize(10).maxLines(1)
          .width('100%').height(14).lineHeight(14).textAlign(TextAlign.Center)
          .fontColor(!enabled ? Theme.TEXT_DISABLED :
            (selected ? Theme.WHITE : (danger ? Theme.FRP_DANGER : Theme.FRP_ACCENT)))
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .constraintSize({ maxWidth: 40 })
    .height(40)
    .padding(0)
    .borderRadius(8)
    .backgroundColor(selected ? Theme.FRP_ACCENT :
      (danger ? Theme.FRP_DANGER_BG : Theme.FRP_ACTION_BG))
    .enabled(enabled)
    .accessibilityText(label)
    .accessibilityDescription(selected ? `${label}，已选中` : label)
    .onClick(action)
  }

  @Builder
  private ConfigCard(config: FrpConfig) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Column({ space: 5 }) {
          Text(config.name)
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor(Theme.FRP_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.typeLabel(config.type)} · ${config.fileName}`)
            .fontSize(12).fontColor(Theme.FRP_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.statusLabel(this.status(config, this.renderTick).state))
          .fontSize(11).fontColor(this.statusColor(this.status(config, this.renderTick).state))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.statusBackground(this.status(config, this.renderTick).state))
          .borderRadius(Theme.FRP_CHIP_RADIUS)
      }.width('100%')
      if (this.status(config, this.renderTick).message !== '') {
        Text(this.shortMessage(this.status(config, this.renderTick).message))
          .fontSize(12).fontColor(this.statusColor(this.status(config, this.renderTick).state))
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (config.type === FrpType.FRPS) {
        Text('当前核心仅支持运行 frpc；frps 配置管理可用')
          .fontSize(11).fontColor(Theme.FRP_TEXT_SECONDARY).width('100%')
      }
      Row({ space: 4 }) {
        this.ActionButton(this.isActive(config, this.renderTick) ? $r('app.media.ic_frp_stop') : $r('app.media.ic_frp_play'),
          this.isActive(config, this.renderTick) ? '停止' : '启动', this.isActive(config, this.renderTick), false,
          () => this.handleToggle(config, !this.isActive(config)),
          this.status(config, this.renderTick).state !== FrpRunState.STARTING &&
          this.status(config, this.renderTick).state !== FrpRunState.STOPPING)
        this.ActionButton($r('app.media.ic_frp_edit'), '编辑', false, false, () => this.edit(config), !this.isActive(config, this.renderTick))
        this.ActionButton($r('app.media.ic_frp_log'), '日志', this.isExpanded(config), false, () => this.toggleExpanded(config))
        this.ActionButton($r('app.media.ic_frp_save'), '保存', false, false, () => { this.saveConfig(config); })
        this.ActionButton($r('app.media.ic_frp_share'), '分享', false, false, () => this.shareConfig(config))
        this.ActionButton($r('app.media.ic_frp_copy'), '复制', false, false, () => this.copyConfig(config))
        this.ActionButton($r('app.media.ic_frp_delete'), '删除', false, true, () => this.askDelete(config), !this.isActive(config, this.renderTick))
      }.width('100%').justifyContent(FlexAlign.Center)
      if (this.isExpanded(config)) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('最近日志').fontSize(13).fontColor(Theme.FRP_TOML_TEXT).layoutWeight(1)
            Button('全部').fontSize(11).height(32).backgroundColor(Theme.TRANSPARENT)
              .fontColor(Theme.FRP_TOML_TEXT).onClick(() => this.showLog(config))
            Button('复制').fontSize(11).height(32).backgroundColor(Theme.TRANSPARENT)
              .fontColor(Theme.FRP_TOML_TEXT).onClick(() => this.copyLog(config))
            Button('清空').fontSize(11).height(32).backgroundColor(Theme.TRANSPARENT)
              .fontColor(Theme.FRP_TOML_TEXT).onClick(() => this.clearLog(config))
          }.width('100%')
          if (this.latestLogs(config, this.renderTick).length === 0) {
            Text('暂无日志').fontSize(12).fontColor(Theme.FRP_TOML_TEXT).width('100%')
          } else {
            ForEach(this.latestLogs(config, this.renderTick), (entry: FrpLogEntry) => {
              Text(this.logText(entry)).fontSize(12).fontFamily('monospace')
                .fontColor(entry.level === 'ERROR' ? Theme.DARK_DANGER : Theme.FRP_TOML_TEXT)
                .width('100%').copyOption(CopyOptions.LocalDevice)
            }, (entry: FrpLogEntry, index?: number) => `${entry.timestamp}-${index}-${entry.message}`)
          }
        }.width('100%').padding(12).backgroundColor(Theme.FRP_TOML_BG)
        .borderRadius(Theme.FRP_INPUT_RADIUS).alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%').padding(12).backgroundColor(Theme.FRP_CARD_BG)
    .border({ width: 1, color: Theme.FRP_BORDER }).borderRadius(Theme.FRP_CARD_RADIUS)
    .margin({ top: 10 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ConfigGroup(title: string, type: FrpType) {
    // 在更新闭包内读取 @State，避免按值传入数组后仍持有 reload 前的快照。
    if ((type === FrpType.FRPC ? this.frpcConfigs : this.frpsConfigs).length > 0) {
      Column() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.PRIMARY)
          .width('100%')
          .margin({ top: 16, bottom: 2 })
        ForEach(type === FrpType.FRPC ? this.frpcConfigs : this.frpsConfigs, (config: FrpConfig) => {
          this.ConfigCard(config)
        }, (config: FrpConfig) => config.key)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private EmptyState() {
    Column() {
      Text('还没有 FRP 配置')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
      Text('导入 TOML 文件，或从模板/空白配置开始')
        .fontSize(14)
        .fontColor(Theme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 10 })
      Row() {
        Button('导入 TOML')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.WHITE)
          .backgroundColor(Theme.PRIMARY)
          .height(40)
          .borderRadius(20)
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            this.onImport();
          })
        Button('新建配置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.PRIMARY)
          .backgroundColor(Theme.CARD_BG)
          .height(40)
          .border({ width: 1, color: Theme.PRIMARY })
          .borderRadius(20)
          .padding({ left: 18, right: 18 })
          .margin({ left: 10 })
          .onClick(() => {
            this.onNew();
          })
      }
      .margin({ top: 20 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      if (!FrpController.probeCapability().available) {
        Row() {
          Text('运行核心未就绪')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.STATUS_CONNECTING)
          Text('配置管理可用，启动功能待接入 HarmonyOS FRP 核心')
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
            .layoutWeight(1)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(Theme.NOTICE_LIGHT_BG)
        .border({ width: 1, color: Theme.STATUS_CONNECTING })
        .borderRadius(12)
        .margin({ left: 12, right: 12, top: 8 })
      }

      Row() {
        Text('FRP 配置')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      if (this.frpcConfigs.length + this.frpsConfigs.length === 0) {
        this.EmptyState()
      } else {
        Column() {
          this.StatusSummary()
          Scroll() {
            Column() {
              this.ConfigGroup('frpc 客户端', FrpType.FRPC)
              this.ConfigGroup('frps 服务端', FrpType.FRPS)
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
