import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FileUtil } from '../common/FileUtil';
import { FrpConfig } from './FrpConfig';

export enum FrpLogLevel {
  ERROR = 'ERROR',
  WARN = 'WARN',
  INFO = 'INFO',
  DEBUG = 'DEBUG'
}

export class FrpLogEntry {
  timestamp: number;
  level: FrpLogLevel;
  message: string;

  constructor(message: string, level: FrpLogLevel = FrpLogLevel.INFO, timestamp: number = Date.now()) {
    this.timestamp = timestamp;
    this.level = level;
    this.message = message;
  }

  toJson(): Record<string, Object> {
    return { 'timestamp': this.timestamp, 'level': this.level, 'message': this.message };
  }

  static fromJson(raw: Record<string, Object>): FrpLogEntry {
    let level = FrpLogStore.parseLevel(typeof raw['level'] === 'string' ? raw['level'] as string : 'INFO');
    return new FrpLogEntry(typeof raw['message'] === 'string' ? raw['message'] as string : '', level,
      typeof raw['timestamp'] === 'number' ? raw['timestamp'] as number : Date.now());
  }
}

/** Per-configuration append-only logs with a bounded file size. */
export class FrpLogStore {
  static readonly DEFAULT_MAX_BYTES: number = 512 * 1024;
  static readonly DEFAULT_MAX_ENTRIES: number = 2000;

  private static context?: Context = undefined;
  private static maxBytes: number = FrpLogStore.DEFAULT_MAX_BYTES;
  private static maxEntries: number = FrpLogStore.DEFAULT_MAX_ENTRIES;

  static setContext(context: Context, maxBytes: number = FrpLogStore.DEFAULT_MAX_BYTES,
    maxEntries: number = FrpLogStore.DEFAULT_MAX_ENTRIES): void {
    FrpLogStore.context = context;
    FrpLogStore.maxBytes = Math.max(1024, maxBytes);
    FrpLogStore.maxEntries = Math.max(1, maxEntries);
  }

  static append(config: FrpConfig, message: string, level: FrpLogLevel = FrpLogLevel.INFO): boolean {
    if (FrpLogStore.context === undefined || message === '') {
      return false;
    }
    try {
      FrpLogStore.ensureDirectory(config);
      let path = config.getLogPath(`${FrpLogStore.context.filesDir}/frp`);
      let line = FrpLogStore.formatLine(new FrpLogEntry(message, level));
      let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      try {
        fs.writeSync(file.fd, line);
      } finally {
        fs.closeSync(file);
      }
      FrpLogStore.truncate(config);
      return true;
    } catch (e) {
      return false;
    }
  }

  static appendEntry(config: FrpConfig, entry: FrpLogEntry): boolean {
    return FrpLogStore.append(config, entry.message, entry.level);
  }

  static read(config: FrpConfig, maxEntries: number = FrpLogStore.maxEntries): FrpLogEntry[] {
    let result: FrpLogEntry[] = [];
    if (FrpLogStore.context === undefined) {
      return result;
    }
    try {
      let path = config.getLogPath(`${FrpLogStore.context.filesDir}/frp`);
      if (!fs.accessSync(path)) {
        return result;
      }
      let lines = fs.readTextSync(path).replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
      let start = Math.max(0, lines.length - 1 - Math.max(1, maxEntries));
      for (let i = start; i < lines.length; i++) {
        let line = lines[i].trim();
        if (line !== '') {
          result.push(FrpLogStore.parseLine(line));
        }
      }
    } catch (e) {
      return [];
    }
    return result;
  }

  static readText(config: FrpConfig): string {
    if (FrpLogStore.context === undefined) {
      return '';
    }
    try {
      let path = config.getLogPath(`${FrpLogStore.context.filesDir}/frp`);
      return fs.accessSync(path) ? fs.readTextSync(path) : '';
    } catch (e) {
      return '';
    }
  }

  static clear(config: FrpConfig): boolean {
    if (FrpLogStore.context === undefined) {
      return false;
    }
    try {
      let path = config.getLogPath(`${FrpLogStore.context.filesDir}/frp`);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static path(config: FrpConfig): string {
    if (FrpLogStore.context === undefined) {
      return '';
    }
    return config.getLogPath(`${FrpLogStore.context.filesDir}/frp`);
  }

  private static ensureDirectory(config: FrpConfig): void {
    let directory = FrpTypeLogDirectory(config, FrpLogStore.context as Context);
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory, true);
    }
  }

  private static truncate(config: FrpConfig): void {
    if (FrpLogStore.context === undefined) {
      return;
    }
    let path = FrpLogStore.path(config);
    let text = fs.readTextSync(path);
    if (text.length <= FrpLogStore.maxBytes) {
      let lines = text.split(/\r?\n/).filter((line: string) => line.trim() !== '');
      if (lines.length <= FrpLogStore.maxEntries) {
        return;
      }
      text = lines.slice(lines.length - FrpLogStore.maxEntries).join('\n') + '\n';
    } else {
      text = text.substring(Math.max(0, text.length - FrpLogStore.maxBytes));
      let firstNewline = text.indexOf('\n');
      if (firstNewline !== -1) {
        text = text.substring(firstNewline + 1);
      }
    }
    FileUtil.writeText(path, text);
  }

  private static formatLine(entry: FrpLogEntry): string {
    return `${entry.timestamp}\t${entry.level}\t${entry.message.replace(/\r/g, '\\r').replace(/\n/g, '\\n')}\n`;
  }

  private static parseLine(line: string): FrpLogEntry {
    let parts = line.split('\t');
    if (parts.length < 3) {
      return new FrpLogEntry(line);
    }
    let timestamp = Number(parts[0]);
    if (!isFinite(timestamp)) {
      timestamp = Date.now();
    }
    let message = parts.slice(2).join('\t').replace(/\\r/g, '\r').replace(/\\n/g, '\n');
    return new FrpLogEntry(message, FrpLogStore.parseLevel(parts[1]), timestamp);
  }

  static parseLevel(level: string): FrpLogLevel {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return FrpLogLevel.ERROR;
      case 'WARN':
      case 'WARNING':
        return FrpLogLevel.WARN;
      case 'DEBUG':
        return FrpLogLevel.DEBUG;
      default:
        return FrpLogLevel.INFO;
    }
  }
}

function FrpTypeLogDirectory(config: FrpConfig, context: Context): string {
  return `${context.filesDir}/frp/logs/${config.type}`;
}
