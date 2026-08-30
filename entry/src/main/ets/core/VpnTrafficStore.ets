/**
 * Persistent per-profile VPN traffic totals.
 *
 * The VPN extension is the sole writer. The UI process reloads the same
 * snapshot file so statistics survive extension restarts and app relaunches.
 */

import fs from '@ohos.file.fs';
import { Context } from '@kit.AbilityKit';
import { FileUtil } from '../common/FileUtil';

export class TrafficAmount {
  inBytes: number = 0;
  outBytes: number = 0;

  constructor(inBytes: number = 0, outBytes: number = 0) {
    this.inBytes = inBytes;
    this.outBytes = outBytes;
  }

  total(): number {
    return this.inBytes + this.outBytes;
  }
}

export class TrafficDay {
  day: string = '';
  inBytes: number = 0;
  outBytes: number = 0;

  constructor(day: string = '', inBytes: number = 0, outBytes: number = 0) {
    this.day = day;
    this.inBytes = inBytes;
    this.outBytes = outBytes;
  }

  total(): number {
    return this.inBytes + this.outBytes;
  }
}

export class VpnTrafficStats {
  uuid: string = '';
  totalInBytes: number = 0;
  totalOutBytes: number = 0;
  today: TrafficAmount = new TrafficAmount();
  month: TrafficAmount = new TrafficAmount();
  days: TrafficDay[] = [];
}

class StoredTrafficProfile {
  totalInBytes: number = 0;
  totalOutBytes: number = 0;
  days: Record<string, TrafficAmount> = {};
  months: Record<string, TrafficAmount> = {};
}

class SampleCounter {
  inBytes: number = 0;
  outBytes: number = 0;

  constructor(inBytes: number, outBytes: number) {
    this.inBytes = inBytes;
    this.outBytes = outBytes;
  }
}

class TrafficSnapshot {
  version: number = 1;
  updatedAt: number = 0;
  profiles: Record<string, StoredTrafficProfile> = {};
}

export class VpnTrafficStore {
  private static readonly FILENAME: string = 'vpn_traffic_stats.json';
  private static readonly SNAPSHOT_VERSION: number = 1;
  private static readonly DAYS_TO_KEEP: number = 365;
  private static readonly MONTHS_TO_KEEP: number = 24;

  private static ctx?: Context = undefined;
  private static writer: boolean = false;
  private static profiles: Map<string, StoredTrafficProfile> = new Map<string, StoredTrafficProfile>();
  private static sessionCounters: Map<string, SampleCounter> = new Map<string, SampleCounter>();
  private static loaded: boolean = false;
  private static lastDiskTimestamp: number = 0;
  private static lastPersist: number = 0;
  private static persistTimer: number = -1;

  static setPersistenceContext(ctx: Context, writer: boolean = false): void {
    VpnTrafficStore.ctx = ctx;
    VpnTrafficStore.writer = writer;
    if (!VpnTrafficStore.loaded) {
      VpnTrafficStore.restoreFromDisk();
    }
  }

  static beginSession(uuid: string): void {
    if (uuid === '') {
      return;
    }
    VpnTrafficStore.sessionCounters.set(uuid, new SampleCounter(0, 0));
  }

  static recordSample(uuid: string, inBytes: number, outBytes: number): void {
    if (!VpnTrafficStore.writer || uuid === '') {
      return;
    }
    let currentIn = VpnTrafficStore.nonNegative(inBytes);
    let currentOut = VpnTrafficStore.nonNegative(outBytes);
    let previous = VpnTrafficStore.sessionCounters.get(uuid);
    VpnTrafficStore.sessionCounters.set(uuid, new SampleCounter(currentIn, currentOut));
    if (previous === undefined) {
      return;
    }

    // A reconnect or native client restart may reset one or both counters. In
    // that case the current value is the traffic accumulated since the reset.
    let diffIn = currentIn >= previous.inBytes ? currentIn - previous.inBytes : currentIn;
    let diffOut = currentOut >= previous.outBytes ? currentOut - previous.outBytes : currentOut;
    if (diffIn === 0 && diffOut === 0) {
      return;
    }

    let now = Date.now();
    let dayKey = VpnTrafficStore.dayKey(new Date(now));
    let monthKey = VpnTrafficStore.monthKey(new Date(now));
    let profile = VpnTrafficStore.profileFor(uuid);
    profile.totalInBytes += diffIn;
    profile.totalOutBytes += diffOut;
    VpnTrafficStore.addAmount(profile.days, dayKey, diffIn, diffOut);
    VpnTrafficStore.addAmount(profile.months, monthKey, diffIn, diffOut);
    VpnTrafficStore.prune(profile, now);
    VpnTrafficStore.persistSoon();
  }

  static restoreFromDisk(): boolean {
    VpnTrafficStore.loaded = true;
    let path = VpnTrafficStore.snapshotPath();
    if (path === '') {
      return false;
    }
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
      let text = fs.readTextSync(path);
      let raw = JSON.parse(text) as Record<string, Object>;
      let version = VpnTrafficStore.numberValue(raw['version']);
      let updatedAt = VpnTrafficStore.numberValue(raw['updatedAt']);
      if (version !== 0 && version !== VpnTrafficStore.SNAPSHOT_VERSION) {
        return false;
      }
      if (!VpnTrafficStore.writer && updatedAt <= VpnTrafficStore.lastDiskTimestamp) {
        return false;
      }
      let rawProfiles = raw['profiles'] as Record<string, Object>;
      if (rawProfiles === undefined || rawProfiles === null) {
        return false;
      }
      let next = new Map<string, StoredTrafficProfile>();
      for (let uuid of Object.keys(rawProfiles)) {
        let rawProfile = rawProfiles[uuid] as Record<string, Object>;
        let profile = VpnTrafficStore.profileFromJson(rawProfile);
        if (profile !== undefined) {
          next.set(uuid, profile);
        }
      }
      VpnTrafficStore.profiles = next;
      VpnTrafficStore.lastDiskTimestamp = updatedAt;
      return true;
    } catch (e) {
      return false;
    }
  }

  static getProfileStats(uuid: string): VpnTrafficStats {
    let result = new VpnTrafficStats();
    result.uuid = uuid;
    let profile = VpnTrafficStore.profiles.get(uuid);
    if (profile === undefined) {
      return result;
    }
    let now = new Date();
    result.totalInBytes = profile.totalInBytes;
    result.totalOutBytes = profile.totalOutBytes;
    result.today = VpnTrafficStore.copyAmount(profile.days[VpnTrafficStore.dayKey(now)]);
    result.month = VpnTrafficStore.copyAmount(profile.months[VpnTrafficStore.monthKey(now)]);
    result.days = VpnTrafficStore.getDailyBreakdown(uuid, 7);
    return result;
  }

  static getDailyBreakdown(uuid: string, days: number = 7): TrafficDay[] {
    let result: TrafficDay[] = [];
    let count = Math.max(1, Math.min(days, VpnTrafficStore.DAYS_TO_KEEP));
    let profile = VpnTrafficStore.profiles.get(uuid);
    for (let offset = count - 1; offset >= 0; offset--) {
      let date = new Date();
      date.setDate(date.getDate() - offset);
      let key = VpnTrafficStore.dayKey(date);
      let amount = profile === undefined ? undefined : profile.days[key];
      result.push(new TrafficDay(key,
        amount === undefined ? 0 : amount.inBytes,
        amount === undefined ? 0 : amount.outBytes));
    }
    return result;
  }

  static removeProfile(uuid: string): void {
    if (uuid === '') {
      return;
    }
    VpnTrafficStore.profiles.delete(uuid);
    VpnTrafficStore.sessionCounters.delete(uuid);
    VpnTrafficStore.persistSoon();
  }

  private static profileFor(uuid: string): StoredTrafficProfile {
    let existing = VpnTrafficStore.profiles.get(uuid);
    if (existing !== undefined) {
      return existing;
    }
    let created = new StoredTrafficProfile();
    VpnTrafficStore.profiles.set(uuid, created);
    return created;
  }

  private static addAmount(buckets: Record<string, TrafficAmount>, key: string,
    inBytes: number, outBytes: number): void {
    let amount = buckets[key];
    if (amount === undefined || amount === null) {
      amount = new TrafficAmount();
      buckets[key] = amount;
    }
    amount.inBytes += inBytes;
    amount.outBytes += outBytes;
  }

  private static prune(profile: StoredTrafficProfile, now: number): void {
    let oldestDay = new Date(now);
    oldestDay.setDate(oldestDay.getDate() - VpnTrafficStore.DAYS_TO_KEEP + 1);
    let oldestDayKey = VpnTrafficStore.dayKey(oldestDay);
    profile.days = VpnTrafficStore.bucketsFrom(profile.days, oldestDayKey);

    let current = new Date(now);
    let oldestMonth = new Date(current.getFullYear(), current.getMonth() - VpnTrafficStore.MONTHS_TO_KEEP + 1, 1);
    let oldestMonthKey = VpnTrafficStore.monthKey(oldestMonth);
    profile.months = VpnTrafficStore.bucketsFrom(profile.months, oldestMonthKey);
  }

  private static bucketsFrom(source: Record<string, TrafficAmount>, minimumKey: string): Record<string, TrafficAmount> {
    let result: Record<string, TrafficAmount> = {};
    for (let key of Object.keys(source)) {
      if (key >= minimumKey) {
        result[key] = source[key];
      }
    }
    return result;
  }

  private static persistSoon(): void {
    if (!VpnTrafficStore.writer || VpnTrafficStore.ctx === undefined) {
      return;
    }
    let now = Date.now();
    if (now - VpnTrafficStore.lastPersist < 500) {
      if (VpnTrafficStore.persistTimer === -1) {
        VpnTrafficStore.persistTimer = setTimeout(() => {
          VpnTrafficStore.persistTimer = -1;
          VpnTrafficStore.persistSnapshot();
        }, 520) as number;
      }
      return;
    }
    VpnTrafficStore.persistSnapshot();
  }

  private static persistSnapshot(): void {
    if (!VpnTrafficStore.writer || VpnTrafficStore.ctx === undefined) {
      return;
    }
    VpnTrafficStore.lastPersist = Date.now();
    try {
      let snapshot = new TrafficSnapshot();
      snapshot.version = VpnTrafficStore.SNAPSHOT_VERSION;
      snapshot.updatedAt = VpnTrafficStore.lastPersist;
      VpnTrafficStore.profiles.forEach((profile: StoredTrafficProfile, uuid: string) => {
        snapshot.profiles[uuid] = profile;
      });
      FileUtil.writeText(VpnTrafficStore.snapshotPath(), JSON.stringify(snapshot));
      VpnTrafficStore.lastDiskTimestamp = snapshot.updatedAt;
    } catch (e) {
      // Statistics must never interrupt the VPN engine.
    }
  }

  private static snapshotPath(): string {
    if (VpnTrafficStore.ctx === undefined) {
      return '';
    }
    return `${VpnTrafficStore.ctx.filesDir}/${VpnTrafficStore.FILENAME}`;
  }

  private static profileFromJson(raw: Record<string, Object>): StoredTrafficProfile | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }
    let profile = new StoredTrafficProfile();
    profile.totalInBytes = VpnTrafficStore.numberValue(raw['totalInBytes']);
    profile.totalOutBytes = VpnTrafficStore.numberValue(raw['totalOutBytes']);
    VpnTrafficStore.readBuckets(raw['days'] as Record<string, Object>, profile.days);
    VpnTrafficStore.readBuckets(raw['months'] as Record<string, Object>, profile.months);
    return profile;
  }

  private static readBuckets(raw: Record<string, Object> | undefined,
    target: Record<string, TrafficAmount>): void {
    if (raw === undefined || raw === null) {
      return;
    }
    for (let key of Object.keys(raw)) {
      let rawAmount = raw[key] as Record<string, Object>;
      if (rawAmount === undefined || rawAmount === null) {
        continue;
      }
      target[key] = new TrafficAmount(
        VpnTrafficStore.numberValue(rawAmount['inBytes']),
        VpnTrafficStore.numberValue(rawAmount['outBytes']));
    }
  }

  private static copyAmount(amount: TrafficAmount | undefined): TrafficAmount {
    if (amount === undefined || amount === null) {
      return new TrafficAmount();
    }
    return new TrafficAmount(amount.inBytes, amount.outBytes);
  }

  private static numberValue(value: Object | undefined): number {
    if (typeof value !== 'number' || !isFinite(value) || value < 0) {
      return 0;
    }
    return value;
  }

  private static nonNegative(value: number): number {
    if (!isFinite(value) || value < 0) {
      return 0;
    }
    return value;
  }

  private static dayKey(date: Date): string {
    return `${date.getFullYear()}-${VpnTrafficStore.two(date.getMonth() + 1)}-${VpnTrafficStore.two(date.getDate())}`;
  }

  private static monthKey(date: Date): string {
    return `${date.getFullYear()}-${VpnTrafficStore.two(date.getMonth() + 1)}`;
  }

  private static two(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
