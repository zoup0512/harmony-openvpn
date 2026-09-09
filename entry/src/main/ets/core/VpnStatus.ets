/**
 * Port of de.blinkt.openvpn.core.VpnStatus
 * Central status/event hub shared between UI and the VPN extension ability.
 */

import { ConnectionStatus, LogItem, LogLevel, logLevelName } from './LogItem';
import { TrafficHistory } from './TrafficHistory';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import { FileUtil } from '../common/FileUtil';
import { Context } from '@kit.AbilityKit';
import { VpnTrafficStore } from './VpnTrafficStore';
import { VpnLogStore } from './VpnLogStore';
import { VpnLogIdentity, redactVpnLog } from './VpnLogArchive';
import { util } from '@kit.ArkTS';

export type StateListener = (level: ConnectionStatus, cleanMessage: string, logItem: LogItem) => void;
export type LogListener = (logItem: LogItem) => void;
export type ByteCountListener = (inBytes: number, outBytes: number, diffIn: number, diffOut: number) => void;

export class VpnStatus {
  static readonly MAXLOGENTRIES: number = 1000;

  private static activeSessionId: string = '';
  private static sessionClock: number = 0;
  private static logListeners: LogListener[] = [];
  private static stateListeners: StateListener[] = [];
  private static byteCountListeners: ByteCountListener[] = [];

  static lastLevel: ConnectionStatus = ConnectionStatus.LEVEL_NOTCONNECTED;
  static lastState: string = 'NOPROCESS';
  static lastCleanMessage: string = '';
  static connectedVPNProfile?: string = undefined;

  static trafficHistory: TrafficHistory = new TrafficHistory();

  /** Bumped on every change; UI uses it to trigger re-renders. */
  static revision: number = 0;

  private static persistCtx?: Context = undefined;
  private static snapshotWriter: boolean = false;
  private static lastPersist: number = 0;
  private static persistTimer: number = -1;
  private static lastSnapshotTimestamp: number = 0;
  private static lastStateTimestamp: number = 0;
  private static readonly processStartTimestamp: number = Date.now();

  static setPersistenceContext(ctx: Context, snapshotWriter: boolean = false): void {
    VpnStatus.persistCtx = ctx;
    VpnStatus.snapshotWriter = snapshotWriter;
    VpnLogStore.setContext(ctx);
  }

  static beginLogSession(uuid: string): VpnSessionLogger {
    VpnStatus.sessionClock = Math.max(Date.now(), VpnStatus.sessionClock + 1);
    let identity = new VpnLogIdentity(uuid, util.generateRandomUUID(true), VpnStatus.sessionClock);
    VpnStatus.activeSessionId = identity.sessionId;
    VpnLogStore.begin(identity);
    return new VpnSessionLogger(identity);
  }

  static isCurrentSession(identity: VpnLogIdentity): boolean {
    return VpnStatus.activeSessionId === identity.sessionId;
  }

  static getlogbuffer(uuid: string = '', sessionId: string = ''): LogItem[] {
    return VpnLogStore.read(uuid, sessionId);
  }

  static getLogSessions(uuid: string): VpnLogIdentity[] {
    return VpnLogStore.history(uuid);
  }

  static clearLog(uuid: string = ''): boolean {
    let cleared = VpnLogStore.clear(uuid);
    VpnStatus.revision++;
    return cleared;
  }

  static isVPNActive(): boolean {
    return VpnStatus.lastLevel !== ConnectionStatus.LEVEL_AUTH_FAILED &&
      VpnStatus.lastLevel !== ConnectionStatus.LEVEL_NOTCONNECTED;
  }

  static getLastConnectedVPNProfile(): string {
    return VpnStatus.connectedVPNProfile as string;
  }

  static setConnectedVPNProfile(uuid?: string): void {
    VpnStatus.connectedVPNProfile = uuid;
  }

  // ------------------------------------------------------------------
  // Listener management
  // ------------------------------------------------------------------

  static addLogListener(l: LogListener): void {
    VpnStatus.logListeners.push(l);
  }

  static removeLogListener(l: LogListener): void {
    let idx = VpnStatus.logListeners.indexOf(l);
    if (idx !== -1) {
      VpnStatus.logListeners.splice(idx, 1);
    }
  }

  static addStateListener(l: StateListener): void {
    VpnStatus.stateListeners.push(l);
    // replay last state like the Android version
    let replay = new LogItem(LogLevel.INFO, VpnStatus.lastCleanMessage);
    l(VpnStatus.lastLevel, VpnStatus.lastCleanMessage, replay);
  }

  static removeStateListener(l: StateListener): void {
    let idx = VpnStatus.stateListeners.indexOf(l);
    if (idx !== -1) {
      VpnStatus.stateListeners.splice(idx, 1);
    }
  }

  static addByteCountListener(l: ByteCountListener): void {
    VpnStatus.byteCountListeners.push(l);
    let last = VpnStatus.trafficHistory.lastSecond();
    if (last !== undefined && last !== null) {
      l(last.inBytes, last.outBytes, 0, 0);
    }
  }

  static removeByteCountListener(l: ByteCountListener): void {
    let idx = VpnStatus.byteCountListeners.indexOf(l);
    if (idx !== -1) {
      VpnStatus.byteCountListeners.splice(idx, 1);
    }
  }

  // ------------------------------------------------------------------
  // Logging / state updates
  // ------------------------------------------------------------------

  static logMessage(level: LogLevel, message: string, identity?: VpnLogIdentity): void {
    let li = new LogItem(level, redactVpnLog(message));
    if (identity !== undefined) {
      li.profileUuid = identity.profileUuid;
      li.sessionId = identity.sessionId;
      li.sessionStartedAt = identity.startedAt;
    }
    VpnStatus.insertLogItem(li);
  }

  static logException(e: Error): void {
    VpnStatus.logMessage(LogLevel.ERROR, `Exception: ${e.name}: ${e.message}`);
  }

  static insertLogItem(li: LogItem): void {
    li.message = redactVpnLog(li.message);
    VpnStatus.toHilog(li);
    VpnLogStore.append(li);
    VpnStatus.revision++;
    for (let l of VpnStatus.logListeners) {
      l(li);
    }
    VpnStatus.persistSoon();
  }

  /**
   * Mirror every log/state line to hilog (tag OVPN) so the full VPN state
   * machine can be captured with `hdc hilog` — the in-app log window only
   * shows the UI process buffer and is easy to miss during repro.
   */
  private static toHilog(li: LogItem): void {
    try {
      let msg = `[${logLevelName(li.level)}] ${li.message}`;
      switch (li.level) {
        case LogLevel.ERROR:
          hilog.error(0, 'OVPN', '%{public}s', msg);
          break;
        case LogLevel.WARNING:
          hilog.warn(0, 'OVPN', '%{public}s', msg);
          break;
        case LogLevel.INFO:
        case LogLevel.VERBOSE:
          hilog.info(0, 'OVPN', '%{public}s', msg);
          break;
        default:
          hilog.debug(0, 'OVPN', '%{public}s', msg);
          break;
      }
    } catch (e) {
      // hilog must never break the VPN state machine
    }
  }

  static updateStateString(state: string, cleanMessage: string, level?: ConnectionStatus, identity?: VpnLogIdentity): void {
    cleanMessage = redactVpnLog(cleanMessage);
    if (identity !== undefined && !VpnStatus.isCurrentSession(identity)) {
      VpnStatus.logMessage(LogLevel.INFO, `[state] ${state}: ${cleanMessage}`, identity);
      return;
    }
    let lvl: ConnectionStatus;
    if (level !== undefined) {
      lvl = level;
    } else {
      lvl = VpnStatus.getLevel(state);
    }

    // Ignore WAIT/AUTH states when already connected (ported behaviour)
    if (VpnStatus.lastLevel === ConnectionStatus.LEVEL_CONNECTED &&
      (state === 'WAIT' || state === 'AUTH')) {
      return;
    }
    if (VpnStatus.lastLevel === ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT && state === 'GET_CONFIG') {
      return;
    }

    VpnStatus.lastState = state;
    VpnStatus.lastStateTimestamp = Date.now();
    VpnStatus.lastLevel = lvl;
    VpnStatus.lastCleanMessage = cleanMessage;

    let li = new LogItem(VpnStatus.levelToLogLevel(lvl), `[state] ${state}: ${cleanMessage}`);
    if (identity !== undefined) {
      li.profileUuid = identity.profileUuid;
      li.sessionId = identity.sessionId;
      li.sessionStartedAt = identity.startedAt;
    }
    VpnStatus.insertLogItem(li);

    for (let l of VpnStatus.stateListeners) {
      l(lvl, cleanMessage, li);
    }
    VpnStatus.persistSoon();
  }

  static updateByteCount(inBytes: number, outBytes: number): void {
    let diff = VpnStatus.trafficHistory.add(inBytes, outBytes);
    if (VpnStatus.connectedVPNProfile !== undefined) {
      VpnTrafficStore.recordSample(VpnStatus.connectedVPNProfile, inBytes, outBytes);
    }
    VpnStatus.revision++;
    for (let l of VpnStatus.byteCountListeners) {
      l(inBytes, outBytes, diff.diffIn, diff.diffOut);
    }
    VpnStatus.persistSoon();
  }

  static levelToLogLevel(l: ConnectionStatus): LogLevel {
    switch (l) {
      case ConnectionStatus.LEVEL_AUTH_FAILED:
      case ConnectionStatus.LEVEL_NONETWORK:
      case ConnectionStatus.LEVEL_NOTCONNECTED:
        return LogLevel.ERROR;
      case ConnectionStatus.LEVEL_VPNPAUSED:
      case ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT:
        return LogLevel.WARNING;
      case ConnectionStatus.UNKNOWN_LEVEL:
        return LogLevel.DEBUG;
      default:
        return LogLevel.INFO;
    }
  }

  /** Port of VpnStatus.getLevel(state) — OpenVPN management state to level mapping. */
  static getLevel(state: string): ConnectionStatus {
    switch (state) {
      case 'CONNECTING':
      case 'WAIT':
      case 'RECONNECTING':
      case 'RESOLVE':
      case 'TCP_CONNECT':
        return ConnectionStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET;
      case 'AUTH':
      case 'GET_CONFIG':
      case 'ASSIGN_IP':
      case 'ADD_ROUTES':
      case 'AUTH_PENDING':
        return ConnectionStatus.LEVEL_CONNECTING_SERVER_REPLIED;
      case 'CONNECTED':
        return ConnectionStatus.LEVEL_CONNECTED;
      case 'SESSION_EXPIRED':
      case 'AUTH_FAILED':
        return ConnectionStatus.LEVEL_AUTH_FAILED;
      case 'DISCONNECTED':
      case 'EXITING':
      case 'NOPROCESS':
        return ConnectionStatus.LEVEL_NOTCONNECTED;
      case 'USER_INPUT':
        return ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT;
      default:
        return ConnectionStatus.UNKNOWN_LEVEL;
    }
  }

  static lastCleanLogMessage(): string {
    if (VpnStatus.lastCleanMessage === '') {
      return '';
    }
    return VpnStatus.lastCleanMessage;
  }

  // ------------------------------------------------------------------
  // Cross-process snapshot persistence (file based)
  // ------------------------------------------------------------------

  private static snapshotPath(): string {
    if (VpnStatus.persistCtx === undefined) {
      return '';
    }
    return VpnStatus.persistCtx.filesDir + '/vpn_status_snapshot.json';
  }

  private static persistSoon(): void {
    if (VpnStatus.persistCtx === undefined || !VpnStatus.snapshotWriter) {
      return;
    }
    let now = Date.now();
    if (now - VpnStatus.lastPersist < 400) {
      if (VpnStatus.persistTimer === -1) {
        VpnStatus.persistTimer = setTimeout(() => {
          VpnStatus.persistTimer = -1;
          VpnStatus.persistSnapshot();
        }, 420) as number;
      }
      return;
    }
    VpnStatus.persistSnapshot();
  }

  /** Force a snapshot write (e.g. before the VPN extension terminates). */
  static persistNow(): void {
    if (VpnStatus.snapshotWriter) {
      VpnStatus.persistSnapshot();
    }
  }

  private static persistSnapshot(): void {
    VpnStatus.lastPersist = Date.now();
    try {
      let path = VpnStatus.snapshotPath();
      if (path === '') {
        return;
      }
      let last = VpnStatus.trafficHistory.lastSecond();
      let snapshotTimestamp = Date.now();
      let snap: Record<string, Object> = {
        'revision': VpnStatus.revision,
        'timestamp': snapshotTimestamp,
        'lastLevel': VpnStatus.lastLevel as number,
        'lastState': VpnStatus.lastState,
        'lastCleanMessage': VpnStatus.lastCleanMessage,
        'connectedVPNProfile': VpnStatus.connectedVPNProfile === undefined ? '' : VpnStatus.connectedVPNProfile,
        'logArchiveVersion': 1,
        'inBytes': last !== undefined && last !== null ? last.inBytes : 0,
        'outBytes': last !== undefined && last !== null ? last.outBytes : 0
      };
      FileUtil.writeText(path, JSON.stringify(snap));
    } catch (e) {
      // ignore persistence errors
    }
  }

  /** Reads the snapshot written by another process and merges it if newer. */
  static restoreFromSnapshot(): boolean {
    VpnLogStore.refresh();
    try {
      let path = VpnStatus.snapshotPath();
      if (path === '' || !fs.accessSync(path)) {
        return false;
      }
      let text = fs.readTextSync(path);
      let o = JSON.parse(text) as Record<string, Object>;
      let timestamp = (o['timestamp'] as number) ?? 0;
      if (timestamp <= VpnStatus.lastSnapshotTimestamp || timestamp < VpnStatus.lastStateTimestamp ||
        timestamp < VpnStatus.processStartTimestamp) {
        return false;
      }
      VpnStatus.lastSnapshotTimestamp = timestamp;
      VpnStatus.lastStateTimestamp = timestamp;
      let rev = (o['revision'] as number) ?? 0;
      VpnStatus.revision = Math.max(VpnStatus.revision, rev);
      VpnStatus.lastLevel = (o['lastLevel'] as number) as ConnectionStatus;
      VpnStatus.lastState = (o['lastState'] as string) ?? 'NOPROCESS';
      VpnStatus.lastCleanMessage = (o['lastCleanMessage'] as string) ?? '';
      let uuid = (o['connectedVPNProfile'] as string) ?? '';
      VpnStatus.connectedVPNProfile = uuid === '' ? undefined : uuid;
      let inBytes = o['inBytes'] as number;
      let outBytes = o['outBytes'] as number;
      if (typeof inBytes === 'number' && typeof outBytes === 'number' &&
        isFinite(inBytes) && isFinite(outBytes) && inBytes >= 0 && outBytes >= 0) {
        VpnStatus.trafficHistory.add(inBytes, outBytes);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}

/** Per-attempt logger; safe to capture across awaits, native events and timers. */
export class VpnSessionLogger {
  readonly identity: VpnLogIdentity;
  private secrets: string[] = [];
  constructor(identity: VpnLogIdentity) {
    this.identity = identity;
  }
  protectSecrets(values: string[]): void {
    this.secrets = this.secrets.concat(values.filter((value: string) => value !== '')).slice(-16);
  }
  private safeMessage(message: string): string {
    for (let secret of this.secrets) {
      message = message.split(secret).join('[redacted]');
    }
    return message;
  }
  logMessage(level: LogLevel, message: string): void {
    VpnStatus.logMessage(level, this.safeMessage(message), this.identity);
  }
  updateStateString(state: string, message: string, level?: ConnectionStatus): void {
    VpnStatus.updateStateString(state, this.safeMessage(message), level, this.identity);
  }
  isCurrent(): boolean {
    return VpnStatus.isCurrentSession(this.identity);
  }
}
