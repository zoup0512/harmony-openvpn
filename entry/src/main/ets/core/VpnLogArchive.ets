import { LogItem } from './LogItem';

/** Immutable identity captured by one connection attempt, never derived from current VPN state. */
export class VpnLogIdentity {
  readonly profileUuid: string;
  readonly sessionId: string;
  readonly startedAt: number;

  constructor(profileUuid: string, sessionId: string, startedAt: number) {
    this.profileUuid = profileUuid;
    this.sessionId = sessionId;
    this.startedAt = startedAt;
  }
}

/** Platform-independent archive used by the actual file store and host regression tests. */
export class VpnLogArchive {
  static readonly MAX_ENTRIES: number = 2000;
  static readonly MAX_SESSIONS: number = 64;
  entries: LogItem[] = [];
  sessions: VpnLogIdentity[] = [];

  begin(identity: VpnLogIdentity): void {
    if (!this.sessions.some((s: VpnLogIdentity) => s.sessionId === identity.sessionId)) {
      this.sessions.push(identity);
      this.sessions.sort((a: VpnLogIdentity, b: VpnLogIdentity) => b.startedAt - a.startedAt ||
        b.sessionId.localeCompare(a.sessionId));
      this.sessions = this.sessions.slice(0, VpnLogArchive.MAX_SESSIONS);
    }
  }

  append(item: LogItem): void {
    if (item.profileUuid !== '' && item.sessionId !== '') {
      this.begin(new VpnLogIdentity(item.profileUuid, item.sessionId, item.sessionStartedAt));
      if (!this.sessions.some((s: VpnLogIdentity) => s.sessionId === item.sessionId)) {
        return;
      }
    }
    item.message = redactVpnLog(item.message);
    this.entries.push(item);
    this.entries = this.entries.filter((e: LogItem) => e.sessionId === '' ||
      this.sessions.some((s: VpnLogIdentity) => s.sessionId === e.sessionId))
      .slice(-VpnLogArchive.MAX_ENTRIES);
  }

  history(uuid: string): VpnLogIdentity[] {
    return this.sessions.filter((s: VpnLogIdentity) => s.profileUuid === uuid);
  }

  select(uuid: string = '', sessionId: string = ''): LogItem[] {
    if (uuid === '') {
      return this.entries.slice();
    }
    let history = this.history(uuid);
    let selected = sessionId || (history.length > 0 ? history[0].sessionId : '');
    return this.entries.filter((e: LogItem) => e.profileUuid === uuid && e.sessionId !== '' &&
      e.sessionId === selected);
  }

  clear(uuid: string = ''): void {
    // Keep session identities: clearing while running must not promote an older late callback.
    this.entries = uuid === '' ? [] : this.entries.filter((e: LogItem) => e.profileUuid !== uuid);
  }

  serialize(): string {
    return JSON.stringify({ version: 1, entries: this.entries.map((e: LogItem) => e.toJson()),
      sessions: this.sessions });
  }

  static parse(text: string): VpnLogArchive {
    let result = new VpnLogArchive();
    let raw = JSON.parse(text) as Record<string, Object>;
    let sessions = raw['sessions'] as Record<string, Object>[];
    if (Array.isArray(sessions)) {
      for (let s of sessions.slice(0, VpnLogArchive.MAX_SESSIONS)) {
        if (typeof s['profileUuid'] === 'string' && typeof s['sessionId'] === 'string' &&
          typeof s['startedAt'] === 'number') {
          result.begin(new VpnLogIdentity(s['profileUuid'] as string, s['sessionId'] as string,
            s['startedAt'] as number));
        }
      }
    }
    let entries = raw['entries'] as Record<string, Object>[];
    if (Array.isArray(entries)) {
      for (let e of entries.slice(-VpnLogArchive.MAX_ENTRIES)) {
        result.append(LogItem.fromJson(e));
      }
    }
    return result;
  }
}

export function redactVpnLog(message: string): string {
  // Never persist credential-bearing protocol messages, challenge cookies or key material.
  if (/CRV1:|SCRV1:|CR_TEXT:|auth[-_]token|session[-_]token|password\s*[:=]|passwd\s*[:=]|cookie\s*[:=]|private.key|BEGIN .*KEY/i.test(message)) {
    return '[credential-bearing diagnostic redacted]';
  }
  return message.substring(0, 4096);
}
