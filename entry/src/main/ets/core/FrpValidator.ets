import { FrpConfig } from './FrpConfig';
import { FrpType } from './FrpType';

export class FrpValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];

  constructor(valid: boolean = true, errors: string[] = [], warnings: string[] = []) {
    this.valid = valid;
    this.errors = errors;
    this.warnings = warnings;
  }

  get message(): string {
    return this.errors.join('; ');
  }
}

/**
 * Conservative validation for configuration names and the small TOML subset
 * needed to catch common FRP mistakes before a future runner is invoked.
 */
export class FrpValidator {
  static readonly MAX_FILE_NAME_LENGTH: number = 128;
  static readonly MAX_CONFIG_LENGTH: number = 1024 * 1024;
  private static readonly FILE_NAME_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9._-]*\.toml$/;

  static validateFileName(fileName: string): FrpValidationResult {
    let errors: string[] = [];
    let normalized = fileName.trim();
    if (normalized === '') {
      errors.push('Configuration file name is empty.');
    } else if (normalized.length > FrpValidator.MAX_FILE_NAME_LENGTH) {
      errors.push('Configuration file name is too long.');
    } else if (normalized !== fileName) {
      errors.push('Configuration file name must not contain leading or trailing spaces.');
    }
    if (normalized.indexOf('/') !== -1 || normalized.indexOf('\\') !== -1 ||
      normalized.indexOf('..') !== -1 || normalized.indexOf('\u0000') !== -1) {
      errors.push('Configuration file name must be a single safe path component.');
    }
    if (normalized !== '' && !FrpValidator.FILE_NAME_PATTERN.test(normalized)) {
      errors.push('Configuration file name must match [A-Za-z0-9][A-Za-z0-9._-]*.toml.');
    }
    return new FrpValidationResult(errors.length === 0, errors);
  }

  static normalizeFileName(fileName: string): string {
    let value = fileName.trim();
    if (!value.toLowerCase().endsWith(FrpConfig.FILE_EXTENSION)) {
      value += FrpConfig.FILE_EXTENSION;
    }
    return value;
  }

  static validateConfig(config: FrpConfig, content: string): FrpValidationResult {
    let nameResult = FrpValidator.validateFileName(config.fileName);
    let syntaxResult = FrpValidator.validateToml(config.type, content);
    return new FrpValidationResult(nameResult.valid && syntaxResult.valid,
      nameResult.errors.concat(syntaxResult.errors), nameResult.warnings.concat(syntaxResult.warnings));
  }

  /**
   * Validates comments, tables, arrays of tables and key/value assignments.
   * It intentionally does not claim to be a complete TOML parser.
   */
  static validateToml(type: FrpType, content: string): FrpValidationResult {
    let errors: string[] = [];
    let warnings: string[] = [];
    if (content === undefined || content === null || content.trim() === '') {
      errors.push('Configuration content is empty.');
      return new FrpValidationResult(false, errors, warnings);
    }
    if (content.length > FrpValidator.MAX_CONFIG_LENGTH) {
      errors.push('Configuration content exceeds the 1 MiB limit.');
      return new FrpValidationResult(false, errors, warnings);
    }

    let table: string = '';
    let lineNumber = 0;
    let lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    let keys: Set<string> = new Set<string>();
    let hasClientAddress = false;
    let hasClientPort = false;
    let hasServerBindPort = false;
    let proxyCount = 0;
    let visitorCount = 0;

    for (let rawLine of lines) {
      lineNumber++;
      let line = FrpValidator.stripComment(rawLine).trim();
      if (line === '') {
        continue;
      }
      if (line.startsWith('[')) {
        let isArrayTable = line.startsWith('[[');
        let end = isArrayTable ? ']]' : ']';
        if (!line.endsWith(end) || line.length <= (isArrayTable ? 4 : 2)) {
          errors.push(`Line ${lineNumber}: malformed TOML table.`);
          continue;
        }
        let start = isArrayTable ? 2 : 1;
        table = line.substring(start, line.length - end.length).trim();
        if (table.indexOf('[') !== -1 || table.indexOf(']') !== -1 || table === '') {
          errors.push(`Line ${lineNumber}: malformed TOML table name.`);
        }
        if (isArrayTable && (table === 'proxies' || table === 'visitors')) {
          if (table === 'proxies') {
            proxyCount++;
          } else {
            visitorCount++;
          }
        }
        continue;
      }

      let equals = FrpValidator.findAssignmentSeparator(line);
      if (equals === -1) {
        errors.push(`Line ${lineNumber}: expected a key/value assignment.`);
        continue;
      }
      let key = line.substring(0, equals).trim();
      let value = line.substring(equals + 1).trim();
      if (!FrpValidator.isKey(key)) {
        errors.push(`Line ${lineNumber}: invalid TOML key.`);
      }
      if (value === '') {
        errors.push(`Line ${lineNumber}: value is empty.`);
      }
      if (key !== '') {
        let fullKey = table === '' ? key : `${table}.${key}`;
        if (keys.has(fullKey)) {
          warnings.push(`Line ${lineNumber}: duplicate key ${fullKey}.`);
        }
        keys.add(fullKey);
        if (fullKey === 'serverAddr') {
          hasClientAddress = FrpValidator.isMeaningfulString(value);
        }
        if (fullKey === 'serverPort') {
          hasClientPort = FrpValidator.isValidPort(value);
        }
        if (fullKey === 'bindPort') {
          hasServerBindPort = FrpValidator.isValidPort(value);
        }
      }
      if (FrpValidator.hasUnbalancedQuotes(value) || FrpValidator.hasUnbalancedBrackets(value)) {
        errors.push(`Line ${lineNumber}: malformed TOML value.`);
      }
    }

    if (type === FrpType.FRPC) {
      if (!hasClientAddress) {
        errors.push('frpc requires a non-empty serverAddr.');
      }
      if (!hasClientPort) {
        errors.push('frpc requires a valid serverPort (1-65535).');
      }
      if (proxyCount === 0 && visitorCount === 0) {
        warnings.push('frpc has no proxies or visitors.');
      }
    } else if (!hasServerBindPort) {
      errors.push('frps requires a valid bindPort (1-65535).');
    }
    return new FrpValidationResult(errors.length === 0, errors, warnings);
  }

  private static stripComment(line: string): string {
    let quoted = false;
    let quote = '';
    for (let i = 0; i < line.length; i++) {
      let ch = line.charAt(i);
      if ((ch === '"' || ch === "'") && (i === 0 || line.charAt(i - 1) !== '\\')) {
        if (!quoted) {
          quoted = true;
          quote = ch;
        } else if (quote === ch) {
          quoted = false;
        }
      }
      if (!quoted && ch === '#') {
        return line.substring(0, i);
      }
    }
    return line;
  }

  private static findAssignmentSeparator(line: string): number {
    let quoted = false;
    let quote = '';
    for (let i = 0; i < line.length; i++) {
      let ch = line.charAt(i);
      if ((ch === '"' || ch === "'") && (i === 0 || line.charAt(i - 1) !== '\\')) {
        if (!quoted) {
          quoted = true;
          quote = ch;
        } else if (quote === ch) {
          quoted = false;
        }
      }
      if (!quoted && ch === '=') {
        return i;
      }
    }
    return -1;
  }

  private static isKey(key: string): boolean {
    return /^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/.test(key);
  }

  private static isMeaningfulString(value: string): boolean {
    if (value.length < 2) {
      return false;
    }
    let first = value.charAt(0);
    let last = value.charAt(value.length - 1);
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return value.substring(1, value.length - 1).trim() !== '';
    }
    return false;
  }

  private static isValidPort(value: string): boolean {
    let parsed = Number(value);
    return isFinite(parsed) && Math.floor(parsed) === parsed && parsed >= 1 && parsed <= 65535;
  }

  private static hasUnbalancedQuotes(value: string): boolean {
    let doubleQuoted = false;
    let singleQuoted = false;
    for (let i = 0; i < value.length; i++) {
      let ch = value.charAt(i);
      if (ch === '"' && (i === 0 || value.charAt(i - 1) !== '\\') && !singleQuoted) {
        doubleQuoted = !doubleQuoted;
      } else if (ch === "'" && !doubleQuoted) {
        singleQuoted = !singleQuoted;
      }
    }
    return doubleQuoted || singleQuoted;
  }

  private static hasUnbalancedBrackets(value: string): boolean {
    let depth = 0;
    for (let ch of value) {
      if (ch === '[') {
        depth++;
      } else if (ch === ']') {
        depth--;
        if (depth < 0) {
          return true;
        }
      }
    }
    return depth !== 0;
  }
}
