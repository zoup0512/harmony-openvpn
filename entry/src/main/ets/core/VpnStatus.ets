/**
 * Port of de.blinkt.openvpn.core.VpnStatus
 * Central status/event hub shared between UI and the VPN extension ability.
 */

import { ConnectionStatus, LogItem, LogLevel } from './LogItem';
import { TrafficHistory } from './TrafficHistory';
import fs from '@ohos.file.fs';
import { FileUtil } from '../common/FileUtil';
import { Context } from '@kit.AbilityKit';

export type StateListener = (level: ConnectionStatus, cleanMessage: string, logItem: LogItem) => void;
export type LogListener = (logItem: LogItem) => void;
export type ByteCountListener = (inBytes: number, outBytes: number, diffIn: number, diffOut: number) => void;

export class VpnStatus {
  static readonly MAXLOGENTRIES: number = 1000;

  private static logbuffer: LogItem[] = [];
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
  }

  static getlogbuffer(): LogItem[] {
    return VpnStatus.logbuffer;
  }

  static clearLog(): void {
    VpnStatus.logbuffer = [];
    VpnStatus.revision++;
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

  static logMessage(level: LogLevel, message: string): void {
    let li = new LogItem(level, message);
    VpnStatus.insertLogItem(li);
  }

  static logException(e: Error): void {
    VpnStatus.logMessage(LogLevel.ERROR, `Exception: ${e.name}: ${e.message}`);
  }

  static insertLogItem(li: LogItem): void {
    VpnStatus.logbuffer.push(li);
    if (VpnStatus.logbuffer.length > VpnStatus.MAXLOGENTRIES + 500) {
      VpnStatus.logbuffer = VpnStatus.logbuffer.slice(500);
    }
    VpnStatus.revision++;
    for (let l of VpnStatus.logListeners) {
      l(li);
    }
    VpnStatus.persistSoon();
  }

  static updateStateString(state: string, cleanMessage: string, level?: ConnectionStatus): void {
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
    VpnStatus.insertLogItem(li);

    for (let l of VpnStatus.stateListeners) {
      l(lvl, cleanMessage, li);
    }
    VpnStatus.persistSoon();
  }

  static updateByteCount(inBytes: number, outBytes: number): void {
    let diff = VpnStatus.trafficHistory.add(inBytes, outBytes);
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
      case 'DISCONNECTED':
      case 'EXITING':
        return ConnectionStatus.LEVEL_NOTCONNECTED;
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
      let logs: Object[] = [];
      let start = Math.max(0, VpnStatus.logbuffer.length - 200);
      for (let i = start; i < VpnStatus.logbuffer.length; i++) {
        logs.push(VpnStatus.logbuffer[i].toJson());
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
        'logs': logs,
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
      let logs = o['logs'] as Object[];
      if (logs !== undefined && logs !== null && logs.length > 0) {
        VpnStatus.logbuffer = [];
        for (let lo of logs) {
          VpnStatus.logbuffer.push(LogItem.fromJson(lo as Record<string, Object>));
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
