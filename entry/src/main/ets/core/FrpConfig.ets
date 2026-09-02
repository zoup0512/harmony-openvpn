import { FrpType, frpConfigDirectory, frpLogDirectory, parseFrpType } from './FrpType';

/** A persisted FRP configuration descriptor. */
export class FrpConfig {
  static readonly FILE_EXTENSION: string = '.toml';
  static readonly CURRENT_VERSION: number = 1;

  id: string;
  type: FrpType;
  fileName: string;
  displayName: string;
  createdAt: number;
  updatedAt: number;
  autoStart: boolean;
  version: number;

  constructor(type: FrpType, fileName: string, displayName: string = '') {
    this.id = FrpConfig.makeId(type, fileName);
    this.type = type;
    this.fileName = fileName;
    this.displayName = displayName === '' ? FrpConfig.removeExtension(fileName) : displayName;
    this.createdAt = Date.now();
    this.updatedAt = this.createdAt;
    this.autoStart = false;
    this.version = FrpConfig.CURRENT_VERSION;
  }

  get key(): string {
    return FrpConfig.makeId(this.type, this.fileName);
  }

  get name(): string {
    return this.displayName === '' ? FrpConfig.removeExtension(this.fileName) : this.displayName;
  }

  getConfigPath(rootDirectory: string): string {
    return `${frpConfigDirectory(rootDirectory, this.type)}/${this.fileName}`;
  }

  getLogPath(rootDirectory: string): string {
    let logName = FrpConfig.removeExtension(this.fileName) + '.log';
    return `${frpLogDirectory(rootDirectory, this.type)}/${logName}`;
  }

  copy(newFileName: string, newDisplayName: string = ''): FrpConfig {
    let copy = new FrpConfig(this.type, newFileName,
      newDisplayName === '' ? FrpConfig.removeExtension(newFileName) : newDisplayName);
    copy.autoStart = false;
    return copy;
  }

  toJson(): Record<string, Object> {
    return {
      'id': this.id,
      'type': this.type,
      'fileName': this.fileName,
      'displayName': this.displayName,
      'createdAt': this.createdAt,
      'updatedAt': this.updatedAt,
      'autoStart': this.autoStart,
      'version': this.version
    };
  }

  static fromJson(raw: Record<string, Object>): FrpConfig | undefined {
    let typeValue = raw['type'];
    let nameValue = raw['fileName'];
    if (typeof typeValue !== 'string' || typeof nameValue !== 'string') {
      return undefined;
    }
    let type = parseFrpType(typeValue);
    if (type === undefined) {
      return undefined;
    }
    let config = new FrpConfig(type, nameValue,
      typeof raw['displayName'] === 'string' ? raw['displayName'] as string : '');
    if (typeof raw['id'] === 'string' && (raw['id'] as string) !== '') {
      config.id = raw['id'] as string;
    }
    if (typeof raw['createdAt'] === 'number' && isFinite(raw['createdAt'] as number)) {
      config.createdAt = raw['createdAt'] as number;
    }
    if (typeof raw['updatedAt'] === 'number' && isFinite(raw['updatedAt'] as number)) {
      config.updatedAt = raw['updatedAt'] as number;
    }
    if (typeof raw['autoStart'] === 'boolean') {
      config.autoStart = raw['autoStart'] as boolean;
    }
    if (typeof raw['version'] === 'number') {
      config.version = raw['version'] as number;
    }
    return config;
  }

  static makeId(type: FrpType, fileName: string): string {
    return `${type}:${fileName}`;
  }

  static removeExtension(fileName: string): string {
    return fileName.endsWith(FrpConfig.FILE_EXTENSION) ?
      fileName.substring(0, fileName.length - FrpConfig.FILE_EXTENSION.length) : fileName;
  }
}
