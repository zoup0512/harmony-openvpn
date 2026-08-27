/**
 * Log window — port of LogWindow + LogFragment: collapsible options panel,
 * status line, auto scrolling log list with long-press copy, and the bottom
 * bytecount status bar.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { GP } from '../common/GP';
import { VpnStatus } from '../core/VpnStatus';
import { LogItem, LogLevel, logLevelName } from '../core/LogItem';
import { Format } from '../common/Format';
import { VpnController } from '../vpn/VpnController';
import { ProfileManager } from '../core/ProfileManager';
import { pasteboard } from '@kit.BasicServicesKit';

@Entry
@Component
struct LogWindow {
  @State optionsVisible: boolean = false;
  @State logLevel: number = 1;
  @State timeFormat: number = 1;
  @State clearLogConnect: boolean = true;
  @State entries: LogItem[] = [];
  @State speedStatus: string = '';
  @State lastStatus: string = '';
  @State byteIn: number = 0;
  @State byteOut: number = 0;
  private scroller: Scroller = new Scroller();
  private timerId: number = -1;

  aboutToAppear(): void {
    this.logLevel = GP_getInt('verbositylevel', 1);
    this.timeFormat = GP_getInt('logtimeformat', 1);
    this.clearLogConnect = GP.getBool('clearlogconnect', true);
    this.refresh();
    this.timerId = setInterval(() => {
      VpnStatus.restoreFromSnapshot();
      this.refresh();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refresh(): void {
    let all = VpnStatus.getlogbuffer();
    let shown: LogItem[] = [];
    for (let li of all) {
      let v = li.getVerbosityLevel();
      if (li.level === LogLevel.ERROR || li.level === LogLevel.WARNING || v <= this.logLevel ||
        this.logLevel >= VpnProfile_MAXLOGLEVEL()) {
        shown.push(li);
      }
      if (shown.length > 1000) {
        shown.shift();
      }
    }
    this.entries = shown.slice();
    this.lastStatus = VpnStatus.lastCleanLogMessage();
    if (this.lastStatus === '') {
      this.speedStatus = R.s('speed_waiting');
    } else {
      this.speedStatus = this.lastStatus;
    }
    let last = VpnStatus.trafficHistory.lastSecond();
    if (last !== undefined && last !== null) {
      this.byteIn = last.inBytes;
      this.byteOut = last.outBytes;
    }
  }

  private formatEntry(li: LogItem): string {
    let time = Format.formatTime(li.logtime, this.timeFormat);
    return `${time}${li.message}`;
  }

  private copyEntry(li: LogItem): void {
    let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, li.message);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      promptAction.showToast({ message: R.s('copied_entry') });
    }).catch(() => {
    });
  }

  private sendLog(): void {
    let lines: string[] = [];
    for (let li of VpnStatus.getlogbuffer()) {
      let iso = Format.formatTime(li.logtime, 2);
      lines.push(`${iso} ${logLevelName(li.level)} ${li.message}`);
    }
    let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      promptAction.showToast({ message: R.s('log_copied_clipboard') });
    }).catch(() => {
    });
  }

  private clearLog(): void {
    VpnStatus.clearLog();
    VpnStatus.logMessage(LogLevel.INFO, R.s('log_cleared'));
    this.refresh();
  }

  private disconnectVpn(): void {
    VpnController.stopVpn().catch(() => {
    });
    VpnStatus.updateStateString('NOPROCESS', R.s('state_disconnected'));
  }

  private editVpn(): void {
    let uuid = ProfileManager.getLastConnectedProfile();
    if (uuid === undefined || uuid === null) {
      promptAction.showToast({ message: R.s('log_no_last_vpn') });
      return;
    }
    let params: Record<string, Object> = { 'uuid': uuid };
    let opt: router.RouterOptions = {
      url: 'pages/ProfileEdit',
      params: params
    };
    router.pushUrl(opt);
  }

  private statusSummary(): string {
    if (VpnStatus.isVPNActive()) {
      return this.speedStatus;
    }
    return R.s('state_disconnected');
  }

  build() {
    Column() {
      // ---- Toolbar ----
      Row() {
        Image($r('app.media.ic_back'))
          .width(24).height(24).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            router.back();
          })
        Text(R.s('openvpn_log'))
          .fontSize(18)
          .fontColor(Color.White)
          .layoutWeight(1)
          .padding({ left: 12 })
        Image($r('app.media.ic_view'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 8 })
          .onClick(() => {
            this.optionsVisible = !this.optionsVisible;
          })
        Image($r('app.media.ic_delete'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            this.clearLog();
          })
        Image($r('app.media.ic_share'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            this.sendLog();
          })
        Image($r('app.media.ic_close'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            this.disconnectVpn();
          })
        Image($r('app.media.ic_edit'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            this.editVpn();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Options panel ----
      if (this.optionsVisible) {
        Column() {
          Text(R.s('log_verbosity_level'))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
          Slider({ value: this.logLevel, min: 1, max: 4, step: 1, style: SliderStyle.InSet })
            .width('100%')
            .selectedColor(Theme.PRIMARY)
            .showTips(true)
            .onChange((value: number) => {
              this.logLevel = Math.round(value);
              GP_setInt('verbositylevel', this.logLevel);
              this.refresh();
            })

          Text(R.s('timestamps'))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Row() {
            Radio({ value: 'none', group: 'timeformat' })
              .checked(this.timeFormat === 0)
              .onChange((c: boolean) => {
                if (c) {
                  this.timeFormat = 0;
                  GP_setInt('logtimeformat', 0);
                }
              })
            Text(R.s('timestamps_none'))
              .fontSize(13)
              .margin({ left: 4 })
            Radio({ value: 'short', group: 'timeformat' })
              .checked(this.timeFormat === 1)
              .margin({ left: 16 })
              .onChange((c: boolean) => {
                if (c) {
                  this.timeFormat = 1;
                  GP_setInt('logtimeformat', 1);
                }
              })
            Text(R.s('timestamps_short'))
              .fontSize(13)
              .margin({ left: 4 })
            Radio({ value: 'iso', group: 'timeformat' })
              .checked(this.timeFormat === 2)
              .margin({ left: 16 })
              .onChange((c: boolean) => {
                if (c) {
                  this.timeFormat = 2;
                  GP_setInt('logtimeformat', 2);
                }
              })
            Text(R.s('timestamps_iso'))
              .fontSize(13)
              .margin({ left: 4 })
          }
          .width('100%')

          Row() {
            Checkbox()
              .select(this.clearLogConnect)
              .selectedColor(Theme.PRIMARY)
              .onChange((v: boolean) => {
                this.clearLogConnect = v;
                GP.setBool('clearlogconnect', v);
              })
            Text(R.s('clear_log_on_connect'))
              .fontSize(13)
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#EEEEEE')
        .alignItems(HorizontalAlign.Start)
      }

      // ---- Status line ----
      Text(this.speedStatus)
        .fontSize(14)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .maxLines(2)

      // ---- Log list ----
      List({ scroller: this.scroller }) {
        ForEach(this.entries, (li: LogItem, index?: number) => {
          ListItem() {
            Text(this.formatEntry(li))
              .fontSize(12)
              .fontColor(li.level === LogLevel.ERROR ? Theme.WARNING_RED :
                (li.level === LogLevel.WARNING ? '#FF8F00' : Theme.TEXT_PRIMARY))
              .width('100%')
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .alignSelf(ItemAlign.Start)
              .gesture(LongPressGesture().onAction(() => {
                this.copyEntry(li);
              }))
          }
        }, (li: LogItem, index?: number) => `${li.logtime}-${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .onReachEnd(() => {
      })

      // ---- Bottom status bar (vpnstatus include) ----
      Row() {
        Column() {
          Text(R.s('uploaded_data'))
            .fontSize(10)
            .fontColor(Theme.TEXT_SECONDARY)
          Text(Format.humanReadableByteCount(this.byteOut, false))
            .fontSize(12)
            .fontColor(Theme.TEXT_PRIMARY)
        }
        .layoutWeight(1)
        Column() {
          Text(R.s('downloaded_data'))
            .fontSize(10)
            .fontColor(Theme.TEXT_SECONDARY)
          Text(Format.humanReadableByteCount(this.byteIn, false))
            .fontSize(12)
            .fontColor(Theme.TEXT_PRIMARY)
        }
        .layoutWeight(1)
        Column() {
          Text(R.s('vpn_status'))
            .fontSize(10)
            .fontColor(Theme.TEXT_SECONDARY)
          Text(this.statusSummary())
            .fontSize(11)
            .fontColor(Theme.TEXT_PRIMARY)
            .maxLines(1)
        }
        .layoutWeight(1.5)
      }
      .width('100%')
      .padding(6)
      .backgroundColor('#DDDDDD')
    }
    .width('100%')
    .height('100%')
  }
}

function VpnProfile_MAXLOGLEVEL(): number {
  return 4;
}

function GP_getInt(key: string, def: number): number {
  return GP.getInt(key, def);
}

function GP_setInt(key: string, value: number): void {
  GP.setInt(key, value);
}
