/**
 * Port of ConnectionStatus / LogLevel / LogItem from de.blinkt.openvpn.core
 */

export enum ConnectionStatus {
  LEVEL_CONNECTED,
  LEVEL_VPNPAUSED,
  LEVEL_CONNECTING_SERVER_REPLIED,
  LEVEL_CONNECTING_NO_SERVER_REPLY_YET,
  LEVEL_NONETWORK,
  LEVEL_NOTCONNECTED,
  LEVEL_START,
  LEVEL_AUTH_FAILED,
  LEVEL_WAITING_FOR_USER_INPUT,
  UNKNOWN_LEVEL
}

export enum LogLevel {
  ERROR = -2,
  WARNING = 1,
  INFO = 2,
  VERBOSE = 3,
  DEBUG = 4
}

export function logLevelByValue(v: number): LogLevel {
  switch (v) {
    case -2:
      return LogLevel.ERROR;
    case 1:
      return LogLevel.WARNING;
    case 2:
      return LogLevel.INFO;
    case 3:
      return LogLevel.VERBOSE;
    case 4:
      return LogLevel.DEBUG;
    default:
      return LogLevel.INFO;
  }
}

export function logLevelName(l: LogLevel): string {
  switch (l) {
    case LogLevel.ERROR:
      return 'E';
    case LogLevel.WARNING:
      return 'W';
    case LogLevel.INFO:
      return 'I';
    case LogLevel.VERBOSE:
      return 'V';
    case LogLevel.DEBUG:
      return 'D';
    default:
      return 'I';
  }
}

export class LogItem {
  level: LogLevel;
  message: string;
  logtime: number;
  verbosityLevel: number;

  constructor(level: LogLevel, message: string, verbosityLevel: number = -1) {
    this.level = level;
    this.message = message;
    this.logtime = Date.now();
    this.verbosityLevel = verbosityLevel;
  }

  getVerbosityLevel(): number {
    if (this.verbosityLevel === -1) {
      return this.level as number;
    }
    return this.verbosityLevel;
  }

  toJson(): Record<string, Object> {
    return {
      'level': this.level as number,
      'message': this.message,
      'logtime': this.logtime,
      'verbosityLevel': this.verbosityLevel
    };
  }

  static fromJson(o: Record<string, Object>): LogItem {
    let li = new LogItem(logLevelByValue((o['level'] as number) ?? 2),
      (o['message'] as string) ?? '', (o['verbosityLevel'] as number) ?? -1);
    li.logtime = (o['logtime'] as number) ?? Date.now();
    return li;
  }
}
