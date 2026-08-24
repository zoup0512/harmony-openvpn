/**
 * Graph tab — replicates GraphFragment: status line, log scale checkbox and
 * three traffic charts (last 5 minutes / average per minute / per hour).
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { GP } from '../../common/GP';
import { VpnStatus } from '../../core/VpnStatus';
import { TrafficHistory, TrafficDatapoint, RatePoint } from '../../core/TrafficHistory';
import { Format } from '../../common/Format';
import { TrafficChart } from '../TrafficChart';

@Component
export struct GraphTab {
  @State useLog: boolean = false;
  @State statusLine: string = '';
  @State chartRevision: number = 0;
  private seconds: RatePoint[] = [];
  private minutes: RatePoint[] = [];
  private hours: RatePoint[] = [];
  private timerId: number = -1;

  aboutToAppear(): void {
    this.useLog = GP.getBool('useLogGraph', false);
    this.refresh();
    this.timerId = setInterval(() => {
      VpnStatus.restoreFromSnapshot();
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
    let th = VpnStatus.trafficHistory;
    let interval = 1000;
    this.seconds = TrafficHistory.toRateSeries(th.getSeconds(), interval);
    this.minutes = TrafficHistory.toRateSeries(th.getMinutes(), TrafficHistory.TIME_PERIOD_MINUTE);
    this.hours = TrafficHistory.toRateSeries(th.getHours(), TrafficHistory.TIME_PERIOD_HOUR);
    let last = th.lastSecond();
    if (last !== undefined && last !== null) {
      this.statusLine = `↓ ${Format.humanReadableByteCount(last.inBytes, false)}` +
        ` - ↑ ${Format.humanReadableByteCount(last.outBytes, false)}`;
    } else {
      this.statusLine = '';
    }
    this.chartRevision++;
  }

  build() {
    Scroll() {
      Column() {
        Text(this.statusLine)
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ top: 8, bottom: 4 })

        Row() {
          Checkbox()
            .select(this.useLog)
            .selectedColor(Theme.PRIMARY)
            .onChange((v: boolean) => {
              this.useLog = v;
              GP.setBool('useLogGraph', v);
              this.chartRevision++;
            })
          Text(R.s('use_logarithmic_scale'))
            .fontSize(14)
            .fontColor(Theme.TEXT_PRIMARY)
        }
        .width('100%')
        .padding({ bottom: 4 })

        TrafficChart({ chartTitle: R.s('graph_last_5_minutes'), useLog: this.useLog, points: this.seconds })
        TrafficChart({ chartTitle: R.s('graph_avg_per_minute'), useLog: this.useLog, points: this.minutes })
        TrafficChart({ chartTitle: R.s('graph_avg_per_hour'), useLog: this.useLog, points: this.hours })
      }
      .padding(8)
    }
    .width('100%')
    .height('100%')
  }
}
