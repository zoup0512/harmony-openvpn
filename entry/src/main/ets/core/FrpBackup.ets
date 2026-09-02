import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FileUtil } from '../common/FileUtil';
import { FrpConfig } from './FrpConfig';
import { FrpType } from './FrpType';
import { FrpValidator } from './FrpValidator';

export class FrpBackupInfo {
  type: FrpType;
  configFileName: string;
  backupFileName: string;
  createdAt: number;
  size: number;

  constructor(type: FrpType, configFileName: string, backupFileName: string,
    createdAt: number = Date.now(), size: number = 0) {
    this.type = type;
    this.configFileName = configFileName;
    this.backupFileName = backupFileName;
    this.createdAt = createdAt;
    this.size = size;
  }
}

/** Explicit, local backups for FRP TOML files. */
export class FrpBackup {
  static readonly MAX_BACKUPS_PER_CONFIG: number = 10;
  private static context?: Context = undefined;

  static init(context: Context): void {
    FrpBackup.context = context;
  }

  static create(config: FrpConfig, content?: string): FrpBackupInfo {
    FrpBackup.requireContext();
    let source = content;
    if (source === undefined) {
      let configPath = FrpBackup.configPath(config);
      if (!fs.accessSync(configPath)) {
        throw new Error(`Configuration does not exist: ${config.fileName}`);
      }
      source = fs.readTextSync(configPath);
    }
    let validation = FrpValidator.validateConfig(config, source);
    if (!validation.valid) {
      throw new Error(validation.message);
    }
    let directory = FrpBackup.directory(config.type);
    FrpBackup.ensureDirectory(directory);
    let now = Date.now();
    let fileName = `${FrpConfig.removeExtension(config.fileName)}.${now}.toml.bak`;
    FileUtil.writeText(`${directory}/${fileName}`, source);
    FrpBackup.prune(config);
    return new FrpBackupInfo(config.type, config.fileName, fileName, now, source.length);
  }

  static list(config: FrpConfig): FrpBackupInfo[] {
    let result: FrpBackupInfo[] = [];
    if (FrpBackup.context === undefined) {
      return result;
    }
    try {
      let directory = FrpBackup.directory(config.type);
      if (!fs.accessSync(directory)) {
        return result;
      }
      let prefix = `${FrpConfig.removeExtension(config.fileName)}.`;
      for (let name of fs.listFileSync(directory)) {
        if (!name.startsWith(prefix) || !name.endsWith('.toml.bak')) {
          continue;
        }
        let timestampText = name.substring(prefix.length, name.length - '.toml.bak'.length);
        let timestamp = Number(timestampText);
        if (!isFinite(timestamp)) {
          timestamp = 0;
        }
        let size = 0;
        try {
          size = fs.statSync(`${directory}/${name}`).size;
        } catch (e) {
          size = 0;
        }
        result.push(new FrpBackupInfo(config.type, config.fileName, name, timestamp, size));
      }
    } catch (e) {
      return [];
    }
    result.sort((a: FrpBackupInfo, b: FrpBackupInfo) => b.createdAt - a.createdAt);
    return result;
  }

  static read(info: FrpBackupInfo): string {
    FrpBackup.requireContext();
    let path = `${FrpBackup.directory(info.type)}/${info.backupFileName}`;
    return fs.accessSync(path) ? fs.readTextSync(path) : '';
  }

  static restore(config: FrpConfig, info: FrpBackupInfo): boolean {
    FrpBackup.requireContext();
    if (config.type !== info.type || config.fileName !== info.configFileName) {
      return false;
    }
    let content = FrpBackup.read(info);
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      return false;
    }
    FileUtil.writeText(FrpBackup.configPath(config), content);
    config.updatedAt = Date.now();
    return true;
  }

  static remove(info: FrpBackupInfo): boolean {
    if (FrpBackup.context === undefined) {
      return false;
    }
    try {
      let path = `${FrpBackup.directory(info.type)}/${info.backupFileName}`;
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static clear(config: FrpConfig): number {
    let removed = 0;
    for (let info of FrpBackup.list(config)) {
      if (FrpBackup.remove(info)) {
        removed++;
      }
    }
    return removed;
  }

  private static prune(config: FrpConfig): void {
    let backups = FrpBackup.list(config);
    for (let i = FrpBackup.MAX_BACKUPS_PER_CONFIG; i < backups.length; i++) {
      FrpBackup.remove(backups[i]);
    }
  }

  private static configPath(config: FrpConfig): string {
    FrpBackup.requireContext();
    return `${(FrpBackup.context as Context).filesDir}/frp/${config.type}/${config.fileName}`;
  }

  private static directory(type: FrpType): string {
    FrpBackup.requireContext();
    return `${(FrpBackup.context as Context).filesDir}/frp/backups/${type}`;
  }

  private static ensureDirectory(path: string): void {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }

  private static requireContext(): void {
    if (FrpBackup.context === undefined) {
      throw new Error('FrpBackup has not been initialized.');
    }
  }
}
