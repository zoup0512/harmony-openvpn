/**
 * FRP configuration list. Runtime ownership deliberately stays outside this
 * component: a start/stop callback must report status through FrpStatus. When
 * no runtime callback is installed, the UI records UNAVAILABLE rather than
 * presenting a false RUNNING state.
 */

import { router, promptAction } from '@kit.ArkUI';
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
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: true }),
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

  private status(config: FrpConfig): FrpStatusSnapshot {
    return FrpStatus.get(config);
  }

  private isActive(config: FrpConfig): boolean {
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

  private latestLogs(config: FrpConfig): FrpLogEntry[] {
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
      if (target !== undefined && FrpConfigManager.remove(target)) {
        this.reload();
        promptAction.showToast({ message: '配置已删除' });
      } else {
        promptAction.showToast({ message: '配置删除失败' });
      }
    };
    this.deleteDialogController.open();
  }

  private countActive(items: FrpConfig[]): number {
    let count = 0;
    for (let config of items) {
      if (this.isActive(config)) {
        count++;
      }
    }
    return count;
  }

  private countErrors(items: FrpConfig[]): number {
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
        Text(`${this.countActive(this.frpcConfigs) + this.countActive(this.frpsConfigs)}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countActive(this.frpcConfigs) + this.countActive(this.frpsConfigs) > 0 ?
            Theme.STATUS_SUCCESS : Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      Column() {
        Text('异常')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.countErrors(this.frpcConfigs) + this.countErrors(this.frpsConfigs)}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countErrors(this.frpcConfigs) + this.countErrors(this.frpsConfigs) > 0 ?
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
  private ConfigCard(config: FrpConfig) {
    Row() {
      Toggle({ type: ToggleType.Switch, isOn: this.isActive(config) })
        .width(48)
        .height(28)
        .selectedColor(Theme.ACCENT)
        .onChange((enabled: boolean) => {
          this.handleToggle(config, enabled);
        })
        .margin({ right: 12 })

      Column() {
        Row() {
          Text(config.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.statusLabel(this.status(config).state))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor(this.status(config).state))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.statusBackground(this.status(config).state))
            .borderRadius(10)
        }
        .width('100%')
        Text(`${this.typeLabel(config.type)} · ${config.fileName}`)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(Theme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 5 })
        if (this.status(config).message !== '') {
          Text(this.shortMessage(this.status(config).message))
            .fontSize(12)
            .fontColor(this.statusColor(this.status(config).state))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 5 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.toggleExpanded(config);
      })

      Column() {
        Text('编辑')
          .fontSize(12)
          .fontColor(this.isActive(config) ? Theme.TEXT_DISABLED : Theme.PRIMARY)
          .onClick(() => {
            if (!this.isActive(config)) {
              this.edit(config);
            }
          })
        Text(this.isExpanded(config) ? '⌃' : '⌄')
          .fontSize(18)
          .fontColor(Theme.TEXT_SECONDARY)
          .margin({ top: 3 })
          .onClick(() => {
            this.toggleExpanded(config);
          })
      }
      .width(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Theme.CARD_BG)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(12)
    .margin({ top: 8 })

    if (this.isExpanded(config)) {
      Column() {
        Row() {
          Text('最近日志')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .layoutWeight(1)
          Text('查看全部')
            .fontSize(12)
            .fontColor(Theme.PRIMARY)
            .onClick(() => {
              this.showLog(config);
            })
          Text('清除')
            .fontSize(12)
            .fontColor(Theme.STATUS_ERROR)
            .margin({ left: 14 })
            .onClick(() => {
              this.clearLog(config);
            })
        }
        .width('100%')
        if (this.latestLogs(config).length === 0) {
          Text('暂无日志')
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
        } else {
          ForEach(this.latestLogs(config), (entry: FrpLogEntry) => {
            Text(this.logText(entry))
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(entry.level === 'ERROR' ? Theme.STATUS_ERROR : Theme.TEXT_SECONDARY)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 5 })
          }, (entry: FrpLogEntry, index?: number) => `${entry.timestamp}-${index}`)
        }
        Row() {
          Text('删除配置')
            .fontSize(12)
            .fontColor(this.isActive(config) ? Theme.TEXT_DISABLED : Theme.STATUS_ERROR)
            .onClick(() => {
              this.askDelete(config);
            })
          Blank()
          Text(config.autoStart ? '自启动已开启' : '自启动未开启')
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 12 })
      .backgroundColor('#FAFAFA')
      .border({ width: { left: 1, right: 1, bottom: 1 }, color: Theme.DIVIDER })
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
    }
  }

  @Builder
  private ConfigGroup(title: string, configs: FrpConfig[]) {
    if (configs.length > 0) {
      Column() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.PRIMARY)
          .width('100%')
          .margin({ top: 16, bottom: 2 })
        ForEach(configs, (config: FrpConfig) => {
          this.ConfigCard(config)
        }, (config: FrpConfig) => `${config.key}-${this.renderTick}`)
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
        Text('刷新')
          .fontSize(14)
          .fontColor(Theme.PRIMARY)
          .padding(8)
          .onClick(() => {
            this.userRefresh();
          })
        Text('新建')
          .fontSize(14)
          .fontColor(Theme.PRIMARY)
          .padding({ left: 8, top: 8, bottom: 8 })
          .onClick(() => {
            this.onNew();
          })
        Text('导入')
          .fontSize(14)
          .fontColor(Theme.PRIMARY)
          .padding({ left: 8, right: 4, top: 8, bottom: 8 })
          .onClick(() => {
            this.onImport();
          })
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
              this.ConfigGroup('frpc 客户端', this.frpcConfigs)
              this.ConfigGroup('frps 服务端', this.frpsConfigs)
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
