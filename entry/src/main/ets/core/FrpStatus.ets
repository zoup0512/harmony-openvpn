import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FileUtil } from '../common/FileUtil';
import { FrpConfig } from './FrpConfig';
import { FrpType, parseFrpType } from './FrpType';

export enum FrpRunState {
  STARTING = 'STARTING',
  RUNNING = 'RUNNING',
  STOPPING = 'STOPPING',
  STOPPED = 'STOPPED',
  FAILED = 'FAILED',
  CRASHED = 'CRASHED',
  UNAVAILABLE = 'UNAVAILABLE'
}

export class FrpStatusSnapshot {
  configId: string = '';
  type: FrpType = FrpType.FRPC;
  fileName: string = '';
  state: FrpRunState = FrpRunState.STOPPED;
  message: string = '';
  exitCode: number = 0;
  hasExitCode: boolean = false;
  updatedAt: number = 0;
  startedAt: number = 0;
  stoppedAt: number = 0;
  revision: number = 0;

  static forConfig(config: FrpConfig): FrpStatusSnapshot {
    let snapshot = new FrpStatusSnapshot();
    snapshot.configId = config.key;
    snapshot.type = config.type;
    snapshot.fileName = config.fileName;
    snapshot.updatedAt = Date.now();
    return snapshot;
  }

  toJson(): Record<string, Object> {
    return {
      'configId': this.configId,
      'type': this.type,
      'fileName': this.fileName,
      'state': this.state,
      'message': this.message,
      'exitCode': this.exitCode,
      'hasExitCode': this.hasExitCode,
      'updatedAt': this.updatedAt,
      'startedAt': this.startedAt,
      'stoppedAt': this.stoppedAt,
      'revision': this.revision
    };
  }

  static fromJson(raw: Record<string, Object>): FrpStatusSnapshot | undefined {
    let typeValue = raw['type'];
    let fileNameValue = raw['fileName'];
    let stateValue = raw['state'];
    if (typeof typeValue !== 'string' || typeof fileNameValue !== 'string' || typeof stateValue !== 'string') {
      return undefined;
    }
    let type = parseFrpType(typeValue);
    let state = FrpStatus.parseState(stateValue);
    if (type === undefined || state === undefined) {
      return undefined;
    }
    let result = new FrpStatusSnapshot();
    result.type = type;
    result.fileName = fileNameValue;
    result.configId = typeof raw['configId'] === 'string' ? raw['configId'] as string :
      FrpConfig.makeId(type, fileNameValue);
    result.state = state;
    result.message = typeof raw['message'] === 'string' ? raw['message'] as string : '';
    result.exitCode = typeof raw['exitCode'] === 'number' ? raw['exitCode'] as number : 0;
    result.hasExitCode = typeof raw['hasExitCode'] === 'boolean' ? raw['hasExitCode'] as boolean : false;
    result.updatedAt = typeof raw['updatedAt'] === 'number' ? raw['updatedAt'] as number : 0;
    result.startedAt = typeof raw['startedAt'] === 'number' ? raw['startedAt'] as number : 0;
    result.stoppedAt = typeof raw['stoppedAt'] === 'number' ? raw['stoppedAt'] as number : 0;
    result.revision = typeof raw['revision'] === 'number' ? raw['revision'] as number : 0;
    return result;
  }
}

export type FrpStatusListener = (snapshot: FrpStatusSnapshot) => void;

/**
 * Status snapshot store. A future FRP service is expected to be the writer;
 * this class never starts a process and never converts a request into RUNNING.
 */
export class FrpStatus {
  private static readonly SNAPSHOT_VERSION: number = 1;
  private static context?: Context = undefined;
  private static writer: boolean = false;
  private static statuses: Map<string, FrpStatusSnapshot> = new Map<string, FrpStatusSnapshot>();
  private static listeners: FrpStatusListener[] = [];
  private static revision: number = 0;

  static setPersistenceContext(context: Context, writer: boolean = false): void {
    FrpStatus.context = context;
    FrpStatus.writer = writer;
    FrpStatus.restoreFromDisk();
  }

  static get(config: FrpConfig): FrpStatusSnapshot {
    let found = FrpStatus.statuses.get(config.key);
    if (found !== undefined) {
      return found;
    }
    return FrpStatusSnapshot.forConfig(config);
  }

  static getByKey(configId: string): FrpStatusSnapshot | undefined {
    return FrpStatus.statuses.get(configId);
  }

  static getAll(): FrpStatusSnapshot[] {
    let result: FrpStatusSnapshot[] = [];
    FrpStatus.statuses.forEach((snapshot: FrpStatusSnapshot) => {
      result.push(snapshot);
    });
    result.sort((a: FrpStatusSnapshot, b: FrpStatusSnapshot) => b.updatedAt - a.updatedAt);
    return result;
  }

  static update(config: FrpConfig, state: FrpRunState, message: string = '', exitCode?: number): FrpStatusSnapshot {
    let snapshot = FrpStatus.get(config);
    let now = Date.now();
    snapshot.configId = config.key;
    snapshot.type = config.type;
    snapshot.fileName = config.fileName;
    snapshot.state = state;
    snapshot.message = message;
    snapshot.updatedAt = now;
    snapshot.revision = ++FrpStatus.revision;
    if (state === FrpRunState.STARTING) {
      snapshot.startedAt = now;
      snapshot.stoppedAt = 0;
      snapshot.hasExitCode = false;
      snapshot.exitCode = 0;
    } else if (FrpStatus.isTerminal(state)) {
      snapshot.stoppedAt = now;
      if (exitCode !== undefined && isFinite(exitCode)) {
        snapshot.exitCode = exitCode;
        snapshot.hasExitCode = true;
      }
    }
    FrpStatus.statuses.set(config.key, snapshot);
    FrpStatus.notify(snapshot);
    FrpStatus.persistNow();
    return snapshot;
  }

  static markUnavailable(config: FrpConfig, message: string): FrpStatusSnapshot {
    return FrpStatus.update(config, FrpRunState.UNAVAILABLE, message);
  }

  static reconcileStaleActiveStates(message: string): void {
    let changed = false;
    FrpStatus.statuses.forEach((snapshot: FrpStatusSnapshot) => {
      if (FrpStatus.isActive(snapshot.state)) {
        snapshot.state = FrpRunState.CRASHED;
        snapshot.message = message;
        snapshot.stoppedAt = Date.now();
        snapshot.updatedAt = snapshot.stoppedAt;
        snapshot.revision = ++FrpStatus.revision;
        changed = true;
      }
    });
    if (changed) {
      FrpStatus.persistNow();
    }
  }

  static rename(oldKey: string, config: FrpConfig): void {
    if (oldKey === config.key) {
      return;
    }
    let previous = FrpStatus.statuses.get(oldKey);
    FrpStatus.statuses.delete(oldKey);
    if (previous !== undefined) {
      previous.configId = config.key;
      previous.type = config.type;
      previous.fileName = config.fileName;
      previous.updatedAt = Date.now();
      previous.revision = ++FrpStatus.revision;
      FrpStatus.statuses.set(config.key, previous);
      FrpStatus.notify(previous);
    }
    FrpStatus.persistNow();
  }

  static remove(config: FrpConfig): void {
    FrpStatus.statuses.delete(config.key);
    FrpStatus.persistNow();
  }

  static addListener(listener: FrpStatusListener): void {
    FrpStatus.listeners.push(listener);
  }

  static removeListener(listener: FrpStatusListener): void {
    let index = FrpStatus.listeners.indexOf(listener);
    if (index !== -1) {
      FrpStatus.listeners.splice(index, 1);
    }
  }

  static persistNow(): boolean {
    if (!FrpStatus.writer || FrpStatus.context === undefined) {
      return false;
    }
    try {
      FrpStatus.ensureDirectory();
      let items: Object[] = [];
      FrpStatus.statuses.forEach((snapshot: FrpStatusSnapshot) => {
        items.push(snapshot.toJson());
      });
      let raw: Record<string, Object> = {
        'version': FrpStatus.SNAPSHOT_VERSION,
        'updatedAt': Date.now(),
        'revision': FrpStatus.revision,
        'statuses': items
      };
      FileUtil.writeText(FrpStatus.snapshotPath(), JSON.stringify(raw));
      return true;
    } catch (e) {
      return false;
    }
  }

  static restoreFromDisk(): boolean {
    if (FrpStatus.context === undefined) {
      return false;
    }
    try {
      let path = FrpStatus.snapshotPath();
      if (!fs.accessSync(path)) {
        return false;
      }
      let raw = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      let items = raw['statuses'] as Object[];
      if (!Array.isArray(items)) {
        return false;
      }
      let restored = new Map<string, FrpStatusSnapshot>();
      for (let item of items) {
        let snapshot = FrpStatusSnapshot.fromJson(item as Record<string, Object>);
        if (snapshot !== undefined && snapshot.configId !== '') {
          restored.set(snapshot.configId, snapshot);
          FrpStatus.revision = Math.max(FrpStatus.revision, snapshot.revision);
        }
      }
      FrpStatus.statuses = restored;
      return true;
    } catch (e) {
      return false;
    }
  }

  static isActive(state: FrpRunState): boolean {
    return state === FrpRunState.STARTING || state === FrpRunState.RUNNING || state === FrpRunState.STOPPING;
  }

  static isTerminal(state: FrpRunState): boolean {
    return state === FrpRunState.STOPPED || state === FrpRunState.FAILED ||
      state === FrpRunState.CRASHED || state === FrpRunState.UNAVAILABLE;
  }

  static parseState(value: string): FrpRunState | undefined {
    switch (value) {
      case FrpRunState.STARTING:
        return FrpRunState.STARTING;
      case FrpRunState.RUNNING:
        return FrpRunState.RUNNING;
      case FrpRunState.STOPPING:
        return FrpRunState.STOPPING;
      case FrpRunState.STOPPED:
        return FrpRunState.STOPPED;
      case FrpRunState.FAILED:
        return FrpRunState.FAILED;
      case FrpRunState.CRASHED:
        return FrpRunState.CRASHED;
      case FrpRunState.UNAVAILABLE:
        return FrpRunState.UNAVAILABLE;
      default:
        return undefined;
    }
  }

  private static notify(snapshot: FrpStatusSnapshot): void {
    for (let listener of FrpStatus.listeners) {
      listener(snapshot);
    }
  }

  private static snapshotPath(): string {
    if (FrpStatus.context === undefined) {
      return '';
    }
    return `${FrpStatus.context.filesDir}/frp/status.json`;
  }

  private static ensureDirectory(): void {
    if (FrpStatus.context === undefined) {
      return;
    }
    let path = `${FrpStatus.context.filesDir}/frp`;
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }
}
