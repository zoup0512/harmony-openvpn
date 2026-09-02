/**
 * Full log view for one FRP configuration.
 */

import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../common/Theme';
import { FrpConfig } from '../core/FrpConfig';
import { FrpConfigManager } from '../core/FrpConfigManager';
import { FrpLogEntry, FrpLogStore } from '../core/FrpLogStore';
import { FrpRunState, FrpStatus } from '../core/FrpStatus';
import { ConfirmDialog, ConfirmDialogModel } from '../components/ConfirmDialog';

interface FrpLogRouteParams {
  uuid: string;
}

@Entry
@Component
struct FrpLog {
  @State private entries: FrpLogEntry[] = [];
  @State private title: string = 'FRP 日志';
  @State private statusText: string = '已停止';
  @State private statusColor: string = Theme.TEXT_SECONDARY;
  @State private renderTick: number = 0;
  private config?: FrpConfig = undefined;
  private timerId: number = -1;
  private clearDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private clearDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.clearDialogModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      FrpConfigManager.init(context);
    }
    let params = router.getParams() as FrpLogRouteParams;
    if (params !== undefined && params !== null && params.uuid !== undefined) {
      this.config = FrpConfigManager.getById(params.uuid);
    }
    if (this.config !== undefined) {
      this.title = `FRP 日志 · ${this.config.name}`;
      this.refresh();
      this.timerId = setInterval(() => {
        FrpStatus.restoreFromDisk();
        this.refresh();
      }, 1000) as number;
    } else {
      promptAction.showToast({ message: 'FRP 配置不存在' });
    }
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refresh(): void {
    let config = this.config;
    if (config === undefined) {
      return;
    }
    this.entries = FrpLogStore.read(config).slice();
    let snapshot = FrpStatus.get(config);
    this.statusText = this.stateLabel(snapshot.state);
    this.statusColor = this.stateColor(snapshot.state);
    this.renderTick++;
  }

  private stateLabel(state: FrpRunState): string {
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

  private stateColor(state: FrpRunState): string {
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

  private formatEntry(entry: FrpLogEntry): string {
    let date = new Date(entry.timestamp);
    let two = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    let time = `${two(date.getHours())}:${two(date.getMinutes())}:${two(date.getSeconds())}`;
    return `${time} [${entry.level}] ${entry.message}`;
  }

  private copyLog(): void {
    let config = this.config;
    if (config === undefined) {
      return;
    }
    let text = FrpLogStore.readText(config);
    if (text === '') {
      promptAction.showToast({ message: '暂无可复制日志' });
      return;
    }
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '日志已复制' });
    }).catch(() => {
      promptAction.showToast({ message: '日志复制失败' });
    });
  }

  private copyEntry(entry: FrpLogEntry): void {
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, entry.message);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '日志已复制' });
    }).catch(() => {
    });
  }

  private askClear(): void {
    let current = this.config;
    if (current === undefined) {
      return;
    }
    let config: FrpConfig = current;
    this.clearDialogModel.title = '清除 FRP 日志';
    this.clearDialogModel.message = `确定清除“${config.name}”的全部日志吗？`;
    this.clearDialogModel.cancelText = '取消';
    this.clearDialogModel.confirmText = '清除';
    this.clearDialogModel.dangerous = true;
    this.clearDialogModel.onConfirm = () => {
      if (FrpLogStore.clear(config)) {
        this.refresh();
        promptAction.showToast({ message: '日志已清除' });
      } else {
        promptAction.showToast({ message: '日志清除失败' });
      }
    };
    this.clearDialogController.open();
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(32)
          .fontColor(Color.White)
          .width(42)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('复制')
          .fontSize(14)
          .fontColor(Color.White)
          .padding(8)
          .onClick(() => {
            this.copyLog();
          })
        Text('清除')
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 8, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            this.askClear();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      if (this.config === undefined) {
        Column() {
          Text('找不到指定配置')
            .fontSize(18)
            .fontColor(Theme.TEXT_PRIMARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Row() {
            Text('当前状态')
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .layoutWeight(1)
            Text(this.statusText)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.statusColor)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.CARD_BG)
          .border({ width: 1, color: Theme.DIVIDER })
          .borderRadius(12)
          .margin(12)

          if (this.entries.length === 0) {
            Column() {
              Text('暂无日志')
                .fontSize(16)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.entries, (entry: FrpLogEntry, index?: number) => {
                ListItem() {
                  Text(this.formatEntry(entry))
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor(entry.level === 'ERROR' ? Theme.STATUS_ERROR : Theme.TEXT_PRIMARY)
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .gesture(LongPressGesture().onAction(() => {
                      this.copyEntry(entry);
                    }))
                }
              }, (entry: FrpLogEntry, index?: number) => `${entry.timestamp}-${index}`)
            }
            .width('100%')
            .layoutWeight(1)
            .backgroundColor(Theme.CARD_BG)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Theme.WINDOW_BG)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
