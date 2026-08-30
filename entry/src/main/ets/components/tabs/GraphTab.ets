/**
 * Graph tab — live throughput line plus the full per-profile traffic
 * dashboard (today/month totals and 7-day history for every VPN profile).
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
  @State statusLine: string = '';
  @State profiles: TrafficProfileView[] = [];
  @State refreshTick: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timerId = setInterval(() => {
      VpnStatus.restoreFromSnapshot();
      VpnTrafficStore.restoreFromDisk();
      this.refresh();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refresh(): void {
    let last = VpnStatus.trafficHistory.lastSecond();
    if (last !== undefined && last !== null) {
      this.statusLine = `↓ ${Format.humanReadableByteCount(last.inBytes, false)}` +
        ` - ↑ ${Format.humanReadableByteCount(last.outBytes, false)}`;
    } else {
      this.statusLine = '';
    }
    let next: TrafficProfileView[] = [];
    for (let profile of ProfileManager.getProfiles()) {
      let row = new TrafficProfileView();
      row.uuid = profile.getUUID();
      row.name = profile.getName();
      row.server = this.serverName(profile);
      let stats = VpnTrafficStore.getProfileStats(row.uuid);
      row.today = stats.today;
      row.month = stats.month;
      row.days = stats.days;
      next.push(row);
    }
    this.profiles = next;
    this.refreshTick++;
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

  private totalText(amount: TrafficAmount): string {
    return Format.humanReadableByteCount(amount.total(), false);
  }

  @Builder
  SummaryTile(title: string, amount: TrafficAmount) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
      Text(this.totalText(amount))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 4 })
      Row() {
        Text(`↓ ${Format.humanReadableByteCount(amount.inBytes, false)}`)
          .fontSize(12)
          .fontColor(Theme.DATA_IN)
          .layoutWeight(1)
        Text(`↑ ${Format.humanReadableByteCount(amount.outBytes, false)}`)
          .fontSize(12)
          .fontColor(Theme.DATA_OUT)
          .textAlign(TextAlign.End)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor('#F7F8FC')
    .borderRadius(8)
  }

  @Builder
  DailyRow(day: TrafficDay) {
    Row() {
      Text(day.day)
        .fontSize(13)
        .fontColor(Theme.TEXT_PRIMARY)
        .layoutWeight(1)
      Text(`↓ ${Format.humanReadableByteCount(day.inBytes, false)}`)
        .fontSize(12)
        .fontColor(Theme.DATA_IN)
        .textAlign(TextAlign.End)
        .margin({ right: 12 })
      Text(`↑ ${Format.humanReadableByteCount(day.outBytes, false)}`)
        .fontSize(12)
        .fontColor(Theme.DATA_OUT)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 1 }, color: Theme.DIVIDER })
  }

  @Builder
  ProfileTrafficCard(row: TrafficProfileView) {
    Column() {
      Row() {
        Column() {
          Text(row.name)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.server)
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        Text(row.uuid.substring(0, Math.min(8, row.uuid.length)))
          .fontSize(11)
          .fontColor(Theme.TEXT_SECONDARY)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        this.SummaryTile(R.s('traffic_today'), row.today)
        this.SummaryTile(R.s('traffic_this_month'), row.month)
      }
      .width('100%')
      .margin({ top: 14 })

      Text(R.s('traffic_last_7_days'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 16, bottom: 2 })

      ForEach(row.days, (day: TrafficDay) => {
        this.DailyRow(day)
      }, (day: TrafficDay) => `${row.uuid}-${day.day}`)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 12 })
    .backgroundColor(Theme.CARD_BG)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  build() {
    Scroll() {
      Column() {
        Text(this.statusLine)
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ top: 8, bottom: 4 })

        Text(R.s('traffic_stats_summary'))
          .fontSize(13)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .margin({ bottom: 12 })

        if (this.profiles.length === 0) {
          Text(R.s('traffic_no_profiles'))
            .fontSize(16)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 32 })
        } else {
          ForEach(this.profiles, (row: TrafficProfileView) => {
            this.ProfileTrafficCard(row)
          }, (row: TrafficProfileView) => `${row.uuid}-${this.refreshTick}`)
        }
      }
      .padding(8)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }
}
