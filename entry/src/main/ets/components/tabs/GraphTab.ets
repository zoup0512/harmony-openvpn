/**
 * Traffic dashboard with current-session totals and per-profile history.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnStatus } from '../../core/VpnStatus';
import { Format } from '../../common/Format';
import { ProfileManager } from '../../core/ProfileManager';
import { VpnProfile } from '../../core/VpnProfile';
import { TrafficAmount, TrafficDay, VpnTrafficStore } from '../../core/VpnTrafficStore';

class TrafficProfileView {
  uuid: string = '';
  name: string = '';
  server: string = '';
  today: TrafficAmount = new TrafficAmount();
  month: TrafficAmount = new TrafficAmount();
  days: TrafficDay[] = [];
}

@Component
export struct GraphTab {
  @State sessionInBytes: number = 0;
  @State sessionOutBytes: number = 0;
  @State hasSessionTraffic: boolean = false;
  @State profiles: TrafficProfileView[] = [];
  private timerId: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timerId = setInterval(() => {
      VpnStatus.restoreFromSnapshot();
      VpnTrafficStore.restoreFromDisk();
      this.refresh();
    }, 1500) as number;
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refresh(): void {
    let last = VpnStatus.trafficHistory.lastSecond();
    if (last !== undefined && last !== null && VpnStatus.lastState === 'CONNECTED') {
      this.sessionInBytes = last.inBytes;
      this.sessionOutBytes = last.outBytes;
      this.hasSessionTraffic = true;
    } else {
      this.sessionInBytes = 0;
      this.sessionOutBytes = 0;
      this.hasSessionTraffic = false;
    }

    let next: TrafficProfileView[] = [];
    let source = ProfileManager.getProfiles().slice();
    source.sort((a: VpnProfile, b: VpnProfile) => a.getName().localeCompare(b.getName()));
    for (let profile of source) {
      let row = new TrafficProfileView();
      row.uuid = profile.getUUID();
      row.name = profile.getName();
      row.server = this.serverName(profile);
      let stats = VpnTrafficStore.getProfileStats(row.uuid);
      row.today = stats.today;
      row.month = stats.month;
      row.days = VpnTrafficStore.getDailyBreakdown(row.uuid, 7);
      next.push(row);
    }
    this.profiles = next;
  }

  private serverName(profile: VpnProfile): string {
    for (let connection of profile.mConnections) {
      if (connection.mEnabled && connection.mServerName.trim() !== '') {
        return connection.mServerName.trim();
      }
    }
    for (let connection of profile.mConnections) {
      if (connection.mServerName.trim() !== '') {
        return connection.mServerName.trim();
      }
    }
    return R.s('no_data');
  }

  private byteText(bytes: number): string {
    return Format.humanReadableByteCount(bytes, false);
  }

  private totalText(amount: TrafficAmount): string {
    return this.byteText(amount.total());
  }

  private shortProfileId(uuid: string): string {
    return uuid.substring(0, Math.min(8, uuid.length));
  }

  private dayLabel(day: string): string {
    let parts = day.split('-');
    if (parts.length !== 3) {
      return day;
    }
    let month = Number(parts[1]);
    let date = Number(parts[2]);
    if (Number.isNaN(month) || Number.isNaN(date)) {
      return day;
    }
    return R.s('traffic_date_short', `${month}`, `${date}`);
  }

  private maxDayTotal(days: TrafficDay[]): number {
    let max = 0;
    for (let day of days) {
      max = Math.max(max, day.total());
    }
    return max;
  }

  private dayBarWidth(day: TrafficDay, maxTotal: number): number {
    if (maxTotal <= 0 || day.total() <= 0) {
      return 0;
    }
    return Math.min(100, day.total() * 100 / maxTotal);
  }

  private dayDownloadWidth(day: TrafficDay, maxTotal: number): number {
    let totalWidth = this.dayBarWidth(day, maxTotal);
    if (totalWidth <= 0 || day.total() <= 0) {
      return 0;
    }
    return totalWidth * day.inBytes / day.total();
  }

  private dayUploadWidth(day: TrafficDay, maxTotal: number): number {
    let totalWidth = this.dayBarWidth(day, maxTotal);
    if (totalWidth <= 0 || day.total() <= 0) {
      return 0;
    }
    return totalWidth * day.outBytes / day.total();
  }

  private hasHistory(row: TrafficProfileView): boolean {
    for (let day of row.days) {
      if (day.total() > 0) {
        return true;
      }
    }
    return false;
  }

  @Builder
  MetricIcon(isDownload: boolean, size: number, iconSize: number) {
    Column() {
      Image(isDownload ? $r('app.media.ic_download') : $r('app.media.ic_upload'))
        .width(iconSize)
        .height(iconSize)
        .fillColor(isDownload ? Theme.DATA_IN : Theme.DATA_OUT)
    }
    .width(size)
    .height(size)
    .backgroundColor(isDownload ? Theme.DATA_IN_BG : Theme.DATA_OUT_BG)
    .borderRadius(size / 2)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SessionMetric(isDownload: boolean, value: number) {
    Column() {
      Row() {
        this.MetricIcon(isDownload, 34, 18)
        Text(R.s(isDownload ? 'traffic_download' : 'traffic_upload'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.byteText(value))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(isDownload ? Theme.DATA_IN : Theme.DATA_OUT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(isDownload ? Theme.DATA_IN_BG : Theme.DATA_OUT_BG)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  CurrentSessionCard() {
    Column() {
      Row() {
        Column() {
          Image($r('app.media.ic_chart'))
            .width(22)
            .height(22)
            .fillColor(Theme.PRIMARY)
        }
        .width(38)
        .height(38)
        .backgroundColor(Theme.INFO_SURFACE)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        Column() {
          Text(R.s('traffic_current_session'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .width('100%')
          Text(R.s(this.hasSessionTraffic ? 'traffic_session_active' : 'traffic_session_idle'))
            .fontSize(12)
            .fontColor(this.hasSessionTraffic ? Theme.STATUS_SUCCESS : Theme.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.hasSessionTraffic) {
        Column({ space: 8 }) {
          this.SessionMetric(true, this.sessionInBytes)
          this.SessionMetric(false, this.sessionOutBytes)
        }
        .width('100%')
        .margin({ top: 14 })
      } else {
        Row() {
          Text(R.s('traffic_session_no_data'))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .padding({ top: 18, bottom: 18 })
        .margin({ top: 14 })
        .backgroundColor(Theme.SURFACE_SUBTLE)
        .borderRadius(12)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD_BG)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(14)
  }

  @Builder
  SummaryDirection(isDownload: boolean, value: number) {
    Row() {
      Image(isDownload ? $r('app.media.ic_download') : $r('app.media.ic_upload'))
        .width(14)
        .height(14)
        .fillColor(isDownload ? Theme.DATA_IN : Theme.DATA_OUT)
      Text(R.s(isDownload ? 'traffic_download' : 'traffic_upload'))
        .fontSize(11)
        .fontColor(Theme.TEXT_SECONDARY)
        .margin({ left: 4 })
        .layoutWeight(1)
      Text(this.byteText(value))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(isDownload ? Theme.DATA_IN : Theme.DATA_OUT)
        .maxLines(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SummaryTile(title: string, amount: TrafficAmount) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
      Text(this.totalText(amount))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 5, bottom: 10 })
      this.SummaryDirection(true, amount.inBytes)
      Column()
        .height(6)
      this.SummaryDirection(false, amount.outBytes)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Theme.SURFACE_SUBTLE)
    .borderRadius(10)
  }

  @Builder
  DailyRow(day: TrafficDay, maxTotal: number, showDivider: boolean) {
    Column() {
      Row() {
        Text(this.dayLabel(day.day))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.byteText(day.total()))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Start }) {
        Rect()
          .width('100%')
          .height(6)
          .fill(Theme.DATA_TRACK_BG)
          .borderRadius(3)
        if (day.total() > 0) {
          Row() {
            Rect()
              .width(`${this.dayDownloadWidth(day, maxTotal)}%`)
              .height(6)
              .fill(Theme.DATA_IN)
              .borderRadius({ topLeft: 3, bottomLeft: 3 })
            Rect()
              .width(`${this.dayUploadWidth(day, maxTotal)}%`)
              .height(6)
              .fill(Theme.DATA_OUT)
              .borderRadius({ topRight: 3, bottomRight: 3 })
          }
          .width('100%')
          .height(6)
        }
      }
      .width('100%')
      .height(6)
      .margin({ top: 8 })

      Column() {
        Row() {
          Image($r('app.media.ic_download'))
            .width(13)
            .height(13)
            .fillColor(Theme.DATA_IN)
          Text(`${R.s('traffic_download')} ${this.byteText(day.inBytes)}`)
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .margin({ left: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        Row() {
          Image($r('app.media.ic_upload'))
            .width(13)
            .height(13)
            .fillColor(Theme.DATA_OUT)
          Text(`${R.s('traffic_upload')} ${this.byteText(day.outBytes)}`)
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .margin({ left: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .margin({ top: 7 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: Theme.DIVIDER })
  }

  @Builder
  ProfileTrafficCard(row: TrafficProfileView) {
    Column() {
      Column() {
        Text(row.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(row.server)
          .fontSize(13)
          .fontColor(Theme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
        Text(`${R.s('traffic_profile_id')} · ${this.shortProfileId(row.uuid)}`)
          .fontSize(11)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 4 })
          .accessibilityText(`${R.s('traffic_profile_id')} ${row.uuid}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        this.SummaryTile(R.s('traffic_today'), row.today)
        this.SummaryTile(R.s('traffic_this_month'), row.month)
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        Text(R.s('traffic_last_7_days'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
        Row() {
          Rect()
            .width(8)
            .height(8)
            .fill(Theme.DATA_IN)
            .borderRadius(4)
          Text(R.s('traffic_download'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .margin({ left: 4, right: 10 })
          Rect()
            .width(8)
            .height(8)
            .fill(Theme.DATA_OUT)
            .borderRadius(4)
          Text(R.s('traffic_upload'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 16, bottom: 2 })

      if (this.hasHistory(row)) {
        ForEach(row.days, (day: TrafficDay, index?: number) => {
          this.DailyRow(day, this.maxDayTotal(row.days), index !== row.days.length - 1)
        }, (day: TrafficDay) => `${row.uuid}-${day.day}`)
      } else {
        Column() {
          Image($r('app.media.ic_chart'))
            .width(28)
            .height(28)
            .fillColor(Theme.TEXT_DISABLED)
          Text(R.s('traffic_no_history'))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ top: 18, bottom: 12 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 12 })
    .backgroundColor(Theme.CARD_BG)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(14)
  }

  @Builder
  EmptyState() {
    Column() {
      Column() {
        Image($r('app.media.ic_chart'))
          .width(34)
          .height(34)
          .fillColor(Theme.PRIMARY)
      }
      .width(68)
      .height(68)
      .backgroundColor(Theme.INFO_SURFACE)
      .borderRadius(34)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Text(R.s('traffic_empty_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .margin({ top: 16 })
      Text(R.s('traffic_no_profiles'))
        .fontSize(14)
        .lineHeight(21)
        .fontColor(Theme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .padding({ left: 20, right: 20, top: 9 })
    }
    .width('100%')
    .padding({ top: 46, bottom: 46 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.CurrentSessionCard()

        Row() {
          Image($r('app.media.ic_info'))
            .width(18)
            .height(18)
            .fillColor(Theme.PRIMARY)
          Text(R.s('traffic_stats_summary'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(Theme.TEXT_SECONDARY)
            .layoutWeight(1)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(Theme.INFO_SURFACE)
        .borderRadius(10)
        .alignItems(VerticalAlign.Top)

        if (this.profiles.length === 0) {
          this.EmptyState()
        } else {
          Text(R.s('traffic_by_profile'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .width('100%')
            .margin({ top: 2 })
          ForEach(this.profiles, (row: TrafficProfileView) => {
            this.ProfileTrafficCard(row)
          }, (row: TrafficProfileView) => row.uuid)
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(Theme.WINDOW_BG)
  }
}
