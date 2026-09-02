import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FileUtil, PickedFile } from '../common/FileUtil';
import { FrpConfig } from './FrpConfig';
import { FrpType, allFrpTypes } from './FrpType';
import { FrpValidationResult, FrpValidator } from './FrpValidator';
import { FrpLogStore } from './FrpLogStore';
import { FrpStatus } from './FrpStatus';

export class FrpConfigManager {
  static readonly ROOT_DIRECTORY_NAME: string = 'frp';
  static readonly METADATA_FILE_NAME: string = 'metadata.json';

  private static context?: Context = undefined;
  private static configs: Map<string, FrpConfig> = new Map<string, FrpConfig>();
  private static loaded: boolean = false;

  static init(context: Context): void {
    if (FrpConfigManager.context === undefined) {
      FrpConfigManager.context = context;
    }
    FrpLogStore.setContext(context);
    // The app process owns the frpc runtime, so it is also the status writer.
    FrpStatus.setPersistenceContext(context, true);
  }

  static ensureLoaded(): void {
    if (FrpConfigManager.loaded || FrpConfigManager.context === undefined) {
      return;
    }
    FrpConfigManager.loaded = true;
    FrpConfigManager.ensureDirectories();
    FrpConfigManager.loadMetadata();
  }

  static rootPath(): string {
    if (FrpConfigManager.context === undefined) {
      return '';
    }
    return `${FrpConfigManager.context.filesDir}/${FrpConfigManager.ROOT_DIRECTORY_NAME}`;
  }

  static configDirectory(type: FrpType): string {
    return `${FrpConfigManager.rootPath()}/${type}`;
  }

  static get(type: FrpType, fileName: string): FrpConfig | undefined {
    FrpConfigManager.ensureLoaded();
    let result = FrpConfigManager.configs.get(FrpConfig.makeId(type, fileName));
    if (result !== undefined && FrpConfigManager.fileExists(result)) {
      return result;
    }
    return result;
  }

  static getById(id: string): FrpConfig | undefined {
    FrpConfigManager.ensureLoaded();
    return FrpConfigManager.configs.get(id);
  }

  static list(type?: FrpType): FrpConfig[] {
    FrpConfigManager.ensureLoaded();
    let result: FrpConfig[] = [];
    FrpConfigManager.configs.forEach((config: FrpConfig) => {
      if (type === undefined || type === config.type) {
        result.push(config);
      }
    });
    result.sort((a: FrpConfig, b: FrpConfig) => a.fileName.localeCompare(b.fileName));
    return result;
  }

  static refresh(): FrpConfig[] {
    FrpConfigManager.loaded = false;
    FrpConfigManager.configs = new Map<string, FrpConfig>();
    FrpConfigManager.ensureLoaded();
    return FrpConfigManager.list();
  }

  /** Create a draft. An empty draft may be saved after editing. */
  static create(type: FrpType, fileName: string, content: string = '', displayName: string = ''): FrpConfig {
    FrpConfigManager.ensureReady();
    let safeName = FrpValidator.normalizeFileName(fileName);
    FrpConfigManager.requireValidName(safeName);
    let key = FrpConfig.makeId(type, safeName);
    if (FrpConfigManager.configs.has(key) || FrpConfigManager.fileAt(type, safeName) !== '') {
      throw new Error(`Configuration already exists: ${safeName}`);
    }
    let config = new FrpConfig(type, safeName, displayName);
    if (content === '') {
      throw new Error('Configuration content is empty.');
    }
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      throw new Error(validation.message);
    }
    FileUtil.writeTextAtomic(config.getConfigPath(FrpConfigManager.rootPath()), content);
    FrpConfigManager.configs.set(config.key, config);
    FrpConfigManager.persistMetadata();
    return config;
  }

  static importContent(type: FrpType, fileName: string, content: string, displayName: string = ''): FrpConfig {
    FrpConfigManager.ensureReady();
    let safeName = FrpValidator.normalizeFileName(fileName);
    FrpConfigManager.requireValidName(safeName);
    let config = new FrpConfig(type, safeName, displayName);
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      throw new Error(validation.message);
    }
    if (FrpConfigManager.configs.has(config.key) || FrpConfigManager.fileAt(type, safeName) !== '') {
      throw new Error(`Configuration already exists: ${safeName}`);
    }
    FileUtil.writeTextAtomic(config.getConfigPath(FrpConfigManager.rootPath()), content);
    FrpConfigManager.configs.set(config.key, config);
    FrpConfigManager.persistMetadata();
    return config;
  }

  static importPickedFile(type: FrpType, picked: PickedFile, displayName: string = ''): FrpConfig {
    return FrpConfigManager.importContent(type, picked.name, picked.content, displayName);
  }

  static importFromUri(type: FrpType, uri: string, fileName: string = ''): FrpConfig {
    let picked = FileUtil.readUri(uri);
    return FrpConfigManager.importContent(type, fileName === '' ? picked.name : fileName, picked.content);
  }

  /** Saves only after strict file-name and lightweight TOML validation. */
  static save(config: FrpConfig, content: string): FrpValidationResult {
    FrpConfigManager.ensureReady();
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      return validation;
    }
    let known = FrpConfigManager.configs.get(config.key);
    if (known === undefined) {
      return new FrpValidationResult(false, ['Configuration is not managed by FrpConfigManager.']);
    }
    FileUtil.writeTextAtomic(config.getConfigPath(FrpConfigManager.rootPath()), content);
    config.updatedAt = Date.now();
    known.updatedAt = config.updatedAt;
    FrpConfigManager.persistMetadata();
    return validation;
  }

  static read(config: FrpConfig): string {
    FrpConfigManager.ensureReady();
    try {
      let path = config.getConfigPath(FrpConfigManager.rootPath());
      return fs.accessSync(path) ? fs.readTextSync(path) : '';
    } catch (e) {
      return '';
    }
  }

  static rename(config: FrpConfig, newFileName: string): FrpConfig {
    FrpConfigManager.ensureReady();
    let safeName = FrpValidator.normalizeFileName(newFileName);
    FrpConfigManager.requireValidName(safeName);
    if (safeName === config.fileName) {
      return config;
    }
    let targetKey = FrpConfig.makeId(config.type, safeName);
    if (FrpConfigManager.configs.has(targetKey) || FrpConfigManager.fileAt(config.type, safeName) !== '') {
      throw new Error(`Configuration already exists: ${safeName}`);
    }
    let oldPath = config.getConfigPath(FrpConfigManager.rootPath());
    let newPath = `${FrpConfigManager.configDirectory(config.type)}/${safeName}`;
    if (!fs.accessSync(oldPath)) {
      throw new Error(`Configuration does not exist: ${config.fileName}`);
    }
    let oldLogPath = config.getLogPath(FrpConfigManager.rootPath());
    let newLogPath = `${FrpConfigManager.rootPath()}/logs/${config.type}/${FrpConfig.removeExtension(safeName)}.log`;
    fs.renameSync(oldPath, newPath);
    if (oldLogPath !== newLogPath && fs.accessSync(oldLogPath)) {
      if (!fs.accessSync(newLogPath)) {
        fs.renameSync(oldLogPath, newLogPath);
      } else {
        fs.unlinkSync(oldLogPath);
      }
    }
    let wasAutoStart = config.autoStart;
    let oldKey = config.key;
    FrpConfigManager.configs.delete(oldKey);
    config.fileName = safeName;
    config.id = FrpConfig.makeId(config.type, safeName);
    config.updatedAt = Date.now();
    config.autoStart = wasAutoStart;
    FrpStatus.rename(oldKey, config);
    FrpConfigManager.configs.set(config.key, config);
    FrpConfigManager.persistMetadata();
    return config;
  }

  static copy(config: FrpConfig, newFileName: string, newDisplayName: string = ''): FrpConfig {
    FrpConfigManager.ensureReady();
    let safeName = FrpValidator.normalizeFileName(newFileName);
    FrpConfigManager.requireValidName(safeName);
    let targetKey = FrpConfig.makeId(config.type, safeName);
    if (FrpConfigManager.configs.has(targetKey) || FrpConfigManager.fileAt(config.type, safeName) !== '') {
      throw new Error(`Configuration already exists: ${safeName}`);
    }
    let content = FrpConfigManager.read(config);
    if (content === '') {
      throw new Error(`Configuration is empty or does not exist: ${config.fileName}`);
    }
    let copy = config.copy(safeName, newDisplayName);
    FileUtil.writeTextAtomic(copy.getConfigPath(FrpConfigManager.rootPath()), content);
    FrpConfigManager.configs.set(copy.key, copy);
    FrpConfigManager.persistMetadata();
    return copy;
  }

  static remove(config: FrpConfig): boolean {
    FrpConfigManager.ensureReady();
    try {
      let path = config.getConfigPath(FrpConfigManager.rootPath());
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      FrpLogStore.clear(config);
      FrpStatus.remove(config);
      FrpConfigManager.configs.delete(config.key);
      FrpConfigManager.persistMetadata();
      return true;
    } catch (e) {
      return false;
    }
  }

  static setAutoStart(config: FrpConfig, enabled: boolean): boolean {
    FrpConfigManager.ensureReady();
    let known = FrpConfigManager.configs.get(config.key);
    if (known === undefined || !FrpConfigManager.fileExists(known)) {
      return false;
    }
    known.autoStart = enabled;
    known.updatedAt = Date.now();
    config.autoStart = enabled;
    config.updatedAt = known.updatedAt;
    FrpConfigManager.persistMetadata();
    return true;
  }

  static isAutoStart(config: FrpConfig): boolean {
    let known = FrpConfigManager.get(config.type, config.fileName);
    return known !== undefined && known.autoStart;
  }

  static getAutoStartConfigs(type?: FrpType): FrpConfig[] {
    return FrpConfigManager.list(type).filter((config: FrpConfig) => config.autoStart &&
      FrpConfigManager.fileExists(config));
  }

  static saveAsync(config: FrpConfig, content: string): Promise<FrpValidationResult> {
    return Promise.resolve(FrpConfigManager.save(config, content));
  }

  static listAsync(type?: FrpType): Promise<FrpConfig[]> {
    return Promise.resolve(FrpConfigManager.list(type));
  }

  private static ensureReady(): void {
    if (FrpConfigManager.context === undefined) {
      throw new Error('FrpConfigManager has not been initialized.');
    }
    FrpConfigManager.ensureLoaded();
  }

  private static requireValidName(fileName: string): void {
    let validation = FrpValidator.validateFileName(fileName);
    if (!validation.valid) {
      throw new Error(validation.message);
    }
  }

  private static fileExists(config: FrpConfig): boolean {
    let path = config.getConfigPath(FrpConfigManager.rootPath());
    try {
      return fs.accessSync(path) && !fs.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  private static fileAt(type: FrpType, fileName: string): string {
    let path = `${FrpConfigManager.configDirectory(type)}/${fileName}`;
    try {
      return fs.accessSync(path) && !fs.statSync(path).isDirectory() ? path : '';
    } catch (e) {
      return '';
    }
  }

  private static ensureDirectories(): void {
    let root = FrpConfigManager.rootPath();
    FrpConfigManager.ensureDirectory(root);
    for (let type of allFrpTypes()) {
      FrpConfigManager.ensureDirectory(FrpConfigManager.configDirectory(type));
      FrpConfigManager.ensureDirectory(`${root}/logs/${type}`);
      FrpConfigManager.ensureDirectory(`${root}/backups/${type}`);
    }
  }

  private static ensureDirectory(path: string): void {
    if (path === '') {
      return;
    }
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      } else if (!fs.statSync(path).isDirectory()) {
        fs.unlinkSync(path);
        fs.mkdirSync(path, true);
      }
    } catch (e) {
      fs.mkdirSync(path, true);
    }
  }

  private static metadataPath(): string {
    return `${FrpConfigManager.rootPath()}/${FrpConfigManager.METADATA_FILE_NAME}`;
  }

  private static loadMetadata(): void {
    try {
      let path = FrpConfigManager.metadataPath();
      if (fs.accessSync(path)) {
        let raw = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
        let entries = raw['configs'] as Object[];
        if (Array.isArray(entries)) {
          for (let entry of entries) {
            let config = FrpConfig.fromJson(entry as Record<string, Object>);
            if (config !== undefined && FrpValidator.validateFileName(config.fileName).valid &&
              FrpConfigManager.fileExists(config)) {
              FrpConfigManager.configs.set(config.key, config);
            }
          }
        }
      }
    } catch (e) {
      // A corrupt index is rebuilt from the configuration directories.
    }
    FrpConfigManager.reconcileFiles();
    FrpConfigManager.persistMetadata();
  }

  private static reconcileFiles(): void {
    for (let type of allFrpTypes()) {
      try {
        let names = fs.listFileSync(FrpConfigManager.configDirectory(type));
        for (let name of names) {
          if (!name.toLowerCase().endsWith(FrpConfig.FILE_EXTENSION) ||
            !FrpValidator.validateFileName(name).valid) {
            continue;
          }
          let key = FrpConfig.makeId(type, name);
          let path = `${FrpConfigManager.configDirectory(type)}/${name}`;
          if (!fs.accessSync(path) || fs.statSync(path).isDirectory()) {
            continue;
          }
          if (!FrpConfigManager.configs.has(key)) {
            let config = new FrpConfig(type, name);
            let modifiedAt = fs.statSync(path).mtime * 1000;
            if (isFinite(modifiedAt) && modifiedAt > 0) {
              config.createdAt = modifiedAt;
              config.updatedAt = modifiedAt;
            }
            FrpConfigManager.configs.set(key, config);
          }
        }
      } catch (e) {
        // Keep all valid metadata entries when a directory cannot be read.
      }
    }
  }

  private static persistMetadata(): void {
    if (FrpConfigManager.context === undefined) {
      return;
    }
    try {
        FrpConfigManager.ensureDirectory(FrpConfigManager.rootPath());
      let entries: Object[] = [];
      FrpConfigManager.configs.forEach((config: FrpConfig) => {
        if (FrpConfigManager.fileExists(config)) {
          entries.push(config.toJson());
        }
      });
      let raw: Record<string, Object> = {
        'version': 1,
        'updatedAt': Date.now(),
        'configs': entries
      };
      FileUtil.writeTextAtomic(FrpConfigManager.metadataPath(), JSON.stringify(raw));
    } catch (e) {
      // Configuration files remain usable if index persistence fails.
    }
  }
}
