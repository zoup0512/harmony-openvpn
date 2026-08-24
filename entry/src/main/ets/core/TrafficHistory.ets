/**
 * Port of de.blinkt.openvpn.core.TrafficHistory
 */

export class TrafficDatapoint {
  timestamp: number;
  inBytes: number;
  outBytes: number;

  constructor(timestamp: number, inBytes: number, outBytes: number) {
    this.timestamp = timestamp;
    this.inBytes = inBytes;
    this.outBytes = outBytes;
  }
}

export class LastDiff {
  inBytes: number = 0;
  outBytes: number = 0;
  diffIn: number = 0;
  diffOut: number = 0;
}

export class TrafficHistory {
  static readonly PERIODS_TO_KEEP: number = 5;
  static readonly TIME_PERIOD_MINUTE: number = 60 * 1000;
  static readonly TIME_PERIOD_HOUR: number = 60 * 60 * 1000;
  static readonly TIME_PERIOD_DAY: number = 24 * 60 * 60 * 1000;

  seconds: TrafficDatapoint[] = [];
  minutes: TrafficDatapoint[] = [];
  hours: TrafficDatapoint[] = [];

  add(inBytes: number, outBytes: number): LastDiff {
    let diff = new LastDiff();
    let last = this.lastSecond();
    if (last !== undefined) {
      diff.diffIn = Math.max(0, inBytes - last.inBytes);
      diff.diffOut = Math.max(0, outBytes - last.outBytes);
    }
    diff.inBytes = inBytes;
    diff.outBytes = outBytes;

    let nd = new TrafficDatapoint(Date.now(), inBytes, outBytes);
    this.seconds.push(nd);

    if (this.seconds.length > 1) {
      let peviousSecond = this.seconds[this.seconds.length - 2];
      // Check if a minute was passed between both samples
      if (nd.timestamp - peviousSecond.timestamp > TrafficHistory.TIME_PERIOD_MINUTE) {
        this.minutes.push(new TrafficDatapoint(nd.timestamp, inBytes, outBytes));
      }
    } else {
      this.minutes.push(new TrafficDatapoint(nd.timestamp, inBytes, outBytes));
    }

    let lastMinute = this.minutes.length > 0 ? this.minutes[this.minutes.length - 1] : undefined;
    if (lastMinute !== undefined && nd.timestamp - lastMinute.timestamp > TrafficHistory.TIME_PERIOD_HOUR) {
      this.hours.push(new TrafficDatapoint(nd.timestamp, inBytes, outBytes));
    }

    this.removeOld();

    return diff;
  }

  private removeOld(): void {
    let lengthSeconds = this.seconds.length;
    if (lengthSeconds > TrafficHistory.PERIODS_TO_KEEP * 60) {
      this.seconds = this.seconds.slice(lengthSeconds - TrafficHistory.PERIODS_TO_KEEP * 60);
    }

    let lengthMinutes = this.minutes.length;
    if (lengthMinutes > TrafficHistory.PERIODS_TO_KEEP * 60) {
      this.minutes = this.minutes.slice(lengthMinutes - TrafficHistory.PERIODS_TO_KEEP * 60);
    }

    let lengthHours = this.hours.length;
    if (lengthHours > TrafficHistory.PERIODS_TO_KEEP * 24) {
      this.hours = this.hours.slice(lengthHours - TrafficHistory.PERIODS_TO_KEEP * 24);
    }
  }

  lastSecond(): TrafficDatapoint | undefined {
    if (this.seconds.length === 0) {
      return undefined;
    }
    return this.seconds[this.seconds.length - 1];
  }

  getSeconds(): TrafficDatapoint[] {
    return this.seconds;
  }

  getMinutes(): TrafficDatapoint[] {
    return this.minutes;
  }

  getHours(): TrafficDatapoint[] {
    return this.hours;
  }

  /** Bytes per second series derived from a list of total byte counters. */
  static toRateSeries(points: TrafficDatapoint[], intervalMs: number): RatePoint[] {
    let out: RatePoint[] = [];
    for (let i = 1; i < points.length; i++) {
      let p0 = points[i - 1];
      let p1 = points[i];
      let gap = p1.timestamp - p0.timestamp;
      let rateIn = 0;
      let rateOut = 0;
      if (gap > 0) {
        rateIn = Math.max(0, (p1.inBytes - p0.inBytes) * 1000 / gap);
        rateOut = Math.max(0, (p1.outBytes - p0.outBytes) * 1000 / gap);
      }
      out.push(new RatePoint(p1.timestamp, rateIn, rateOut));
      if (gap > intervalMs * 2) {
        out.push(new RatePoint(p1.timestamp - 1, 0, 0));
      }
    }
    out.sort((a: RatePoint, b: RatePoint) => a.timestamp - b.timestamp);
    return out;
  }
}

export class RatePoint {
  timestamp: number;
  rateIn: number;
  rateOut: number;

  constructor(timestamp: number, rateIn: number, rateOut: number) {
    this.timestamp = timestamp;
    this.rateIn = rateIn;
    this.rateOut = rateOut;
  }
}
