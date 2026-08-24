/**
 * Traffic graph replicating the MPAndroidChart based graph items of the
 * Android client: red line for incoming, blue line for outgoing traffic,
 * light fill under the lines, "n s/m/h ago" x axis labels and human readable
 * byte/s y labels (optionally logarithmic).
 */

import { Theme } from '../common/Theme';
import { RatePoint } from '../core/TrafficHistory';
import { Format } from '../common/Format';
import { R } from '../common/Res';

@Component
export struct TrafficChart {
  @Prop chartTitle: string = '';
  @Prop useLog: boolean = false;
  points: RatePoint[] = [];
  @State private minData: boolean = true;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context2D: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private log(v: number): number {
    return Math.log10(Math.max(v * 8, 1));
  }

  private fmtY(v: number): string {
    if (this.useLog) {
      if (v < 2.1) {
        return '< 100 bit/s';
      }
      let rate = Math.pow(10, v) / 8;
      return Format.humanReadableByteCount(rate, true);
    }
    return Format.humanReadableByteCount(v, true);
  }

  private fmtX(secondsAgo: number): string {
    if (secondsAgo >= 3600) {
      return `${Math.round(secondsAgo / 3600)}\u2009h`;
    } else if (secondsAgo >= 60) {
      return `${Math.round(secondsAgo / 60)}\u2009m`;
    } else {
      return `${Math.round(secondsAgo)}\u2009s`;
    }
  }

  build() {
    Column() {
      Text(this.chartTitle)
        .fontSize(16)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
        .padding({ bottom: 4 })
      if (this.minData) {
        Text(R.s('notenoughdata'))
          .fontSize(14)
          .fontColor(Theme.TEXT_SECONDARY)
          .height(200)
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Canvas(this.context2D)
          .width('100%')
          .height(200)
          .onReady(() => {
            this.draw();
          })
      }
    }
    .padding(8)
    .width('100%')
    .backgroundColor(Theme.CARD_BG)
    .onAppear(() => {
      this.minData = this.points.length < 3;
      if (!this.minData) {
        this.context2D.clearRect(0, 0, this.context2D.width, this.context2D.height);
      }
    })
  }

  private draw(): void {
    let ctx = this.context2D;
    let w = ctx.width;
    let h = ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    let left = 64;
    let right = w - 8;
    let top = 8;
    let bottom = h - 24;

    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, w, h);

    let now = Date.now();
    let windowMs = this.points.length > 0 ? Math.max(1000, now - this.points[0].timestamp) : 1000;

    let maxY = 0;
    let drawIn: number[] = [];
    let drawOut: number[] = [];
    for (let p of this.points) {
      let vi = this.useLog ? this.log(p.rateIn) : p.rateIn;
      let vo = this.useLog ? this.log(p.rateOut) : p.rateOut;
      drawIn.push(vi);
      drawOut.push(vo);
      if (vi > maxY) {
        maxY = vi;
      }
      if (vo > maxY) {
        maxY = vo;
      }
    }
    if (this.useLog) {
      maxY = Math.max(Math.ceil(maxY), 2);
    } else if (maxY <= 0) {
      maxY = 1024;
    }

    // axes
    ctx.strokeStyle = '#99000000';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(left, top);
    ctx.lineTo(left, bottom);
    ctx.lineTo(right, bottom);
    ctx.stroke();

    // y labels
    ctx.fillStyle = Theme.TEXT_SECONDARY;
    ctx.font = '11px sans-serif';
    let ySteps = this.useLog ? Math.max(1, Math.ceil(maxY - 2)) : 6;
    if (ySteps > 10) {
      ySteps = 10;
    }
    let minY = this.useLog ? 2 : 0;
    for (let i = 0; i <= ySteps; i++) {
      let val = minY + (maxY - minY) * i / ySteps;
      let y = bottom - (bottom - top) * i / ySteps;
      ctx.fillText(this.fmtY(val), 2, y + 4);
    }

    // x labels
    for (let i = 0; i <= 4; i++) {
      let x = left + (right - left) * i / 4;
      let msAgo = windowMs * (1 - i / 4);
      ctx.fillText(this.fmtX(msAgo / 1000), Math.min(x, right - 30), bottom + 18);
    }

    // series
    this.drawSeries(ctx, drawIn, Theme.DATA_IN, left, right, top, bottom, maxY, minY, now, windowMs);
    this.drawSeries(ctx, drawOut, Theme.DATA_OUT, left, right, top, bottom, maxY, minY, now, windowMs);
  }

  private drawSeries(ctx: CanvasRenderingContext2D, values: number[], color: string,
    left: number, right: number, top: number, bottom: number,
    maxY: number, minY: number, now: number, windowMs: number): void {
    let n = this.points.length;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.fillStyle = color;
    ctx.globalAlpha = 0.16;
    ctx.beginPath();
    let started = false;
    for (let i = 0; i < n; i++) {
      let p = this.points[i];
      let x = left + (right - left) * (1 - (now - p.timestamp) / windowMs);
      let y = bottom - (bottom - top) * (values[i] - minY) / (maxY - minY);
      if (!started) {
        ctx.moveTo(x, y);
        started = true;
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
    // fill under the line
    ctx.lineTo(right, bottom);
    ctx.lineTo(left, bottom);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 1;
  }
}
