import fs from '@ohos.file.fs';
import { Context } from '@kit.AbilityKit';
import { FileUtil } from '../common/FileUtil';
import { LogItem } from './LogItem';
import { VpnLogArchive, VpnLogIdentity } from './VpnLogArchive';

/** Shared sandbox file, protected by a stable advisory lock across Ability processes.
 * Each mutation reloads under lock; no stale in-memory buffer can resurrect cleared logs.
 * Contention/permissions fail closed for diagnostics only; never block the VPN worker.
 */
export class VpnLogStore {
  private static directory: string = '';
  private static archive: VpnLogArchive = new VpnLogArchive();

  static setContext(ctx: Context): void {
    VpnLogStore.directory = ctx.filesDir;
    VpnLogStore.refresh();
  }

  private static load(): VpnLogArchive {
    let path = VpnLogStore.directory + '/vpn_logs.json';
    if (fs.accessSync(path)) {
      if (fs.statSync(path).size > 32 * 1024 * 1024) {
        throw new Error('Log archive exceeds safety limit');
      }
      return VpnLogArchive.parse(fs.readTextSync(path));
    }
    let result = new VpnLogArchive();
    // One-time migration, independent of status freshness. Legacy records remain unowned.
    let legacy = VpnLogStore.directory + '/vpn_status_snapshot.json';
    if (fs.accessSync(legacy)) {
      let raw = JSON.parse(fs.readTextSync(legacy)) as Record<string, Object>;
      let logs = raw['logs'] as Record<string, Object>[];
      if (Array.isArray(logs)) {
        for (let item of logs.slice(-200)) {
          let li = LogItem.fromJson(item);
          li.profileUuid = '';
          li.sessionId = '';
          result.append(li);
        }
      }
    }
    return result;
  }

  private static transact(change?: (archive: VpnLogArchive) => void): boolean {
    if (VpnLogStore.directory === '') {
      if (change !== undefined) {
        change(VpnLogStore.archive);
      }
      return true;
    }
    try {
      let lock = fs.openSync(VpnLogStore.directory + '/vpn_logs.lock',
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      try {
        lock.tryLock(true);
        let archive = VpnLogStore.load();
        if (change !== undefined) {
          change(archive);
          FileUtil.writeTextAtomic(VpnLogStore.directory + '/vpn_logs.json', archive.serialize());
        }
        VpnLogStore.archive = archive;
      } finally {
        fs.closeSync(lock);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static refresh(): void {
    VpnLogStore.transact();
  }

  static begin(identity: VpnLogIdentity): void {
    VpnLogStore.transact((archive: VpnLogArchive) => archive.begin(identity));
  }

  static append(item: LogItem): void {
    VpnLogStore.transact((archive: VpnLogArchive) => archive.append(item));
  }

  static read(uuid: string = '', sessionId: string = ''): LogItem[] {
    return VpnLogStore.archive.select(uuid, sessionId);
  }

  static history(uuid: string): VpnLogIdentity[] {
    return VpnLogStore.archive.history(uuid);
  }

  static clear(uuid: string = ''): boolean {
    return VpnLogStore.transact((archive: VpnLogArchive) => archive.clear(uuid));
  }
}
