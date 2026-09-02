import fs from '@ohos.file.fs';

/**
 * File-based control channel between the ArkTS runtime owner and the Go
 * frpc host. The host (child process or in-process goroutine) watches the
 * stop file and writes an exit report exactly once; both sides derive file
 * names from the config id with the identical sanitizing rule as the Go
 * side (see ctlBaseName in native/frpc-host/main.go).
 */
export class FrpExitReport {
  code: number = 0;
  message: string = '';
  pid: number = 0;
  startedAt: number = 0;
  stoppedAt: number = 0;

  static fromJson(raw: Record<string, Object>): FrpExitReport | undefined {
    let code = raw['code'];
    if (typeof code !== 'number') {
      return undefined;
    }
    let report = new FrpExitReport();
    report.code = code;
    report.message = typeof raw['message'] === 'string' ? raw['message'] as string : '';
    report.pid = typeof raw['pid'] === 'number' ? raw['pid'] as number : 0;
    report.startedAt = typeof raw['startedAt'] === 'number' ? raw['startedAt'] as number : 0;
    report.stoppedAt = typeof raw['stoppedAt'] === 'number' ? raw['stoppedAt'] as number : 0;
    return report;
  }
}

export class FrpControlFiles {
  static readonly DIRECTORY_NAME: string = 'ctl';
  private static readonly STOP_SUFFIX: string = '.stop';
  private static readonly EXIT_SUFFIX: string = '.exit';
  private static readonly PID_SUFFIX: string = '.pid';

  static ctlDir(rootDirectory: string): string {
    return `${rootDirectory}/${FrpControlFiles.DIRECTORY_NAME}`;
  }

  /** Mirrors ctlBaseName in native/frpc-host/main.go. */
  static baseName(configId: string): string {
    let builder = '';
    for (let i = 0; i < configId.length; i++) {
      let ch = configId.charAt(i);
      let code = configId.charCodeAt(i);
      let safe = (code >= 97 && code <= 122) || (code >= 65 && code <= 90) ||
        (code >= 48 && code <= 57) || ch === '.' || ch === '_' || ch === '-';
      builder += safe ? ch : '_';
    }
    return builder === '' ? 'config' : builder;
  }

  static stopPath(ctlDir: string, configId: string): string {
    return `${ctlDir}/${FrpControlFiles.baseName(configId)}${FrpControlFiles.STOP_SUFFIX}`;
  }

  static exitPath(ctlDir: string, configId: string): string {
    return `${ctlDir}/${FrpControlFiles.baseName(configId)}${FrpControlFiles.EXIT_SUFFIX}`;
  }

  static pidPath(ctlDir: string, configId: string): string {
    return `${ctlDir}/${FrpControlFiles.baseName(configId)}${FrpControlFiles.PID_SUFFIX}`;
  }

  static ensureDir(ctlDir: string): void {
    try {
      if (!fs.accessSync(ctlDir)) {
        fs.mkdirSync(ctlDir, true);
      }
    } catch (e) {
    }
  }

  /** Clears stale control files before a fresh start. */
  static prepareStart(ctlDir: string, configId: string): void {
    FrpControlFiles.ensureDir(ctlDir);
    FrpControlFiles.removeFile(FrpControlFiles.stopPath(ctlDir, configId));
    FrpControlFiles.removeFile(FrpControlFiles.exitPath(ctlDir, configId));
    FrpControlFiles.removeFile(`${FrpControlFiles.exitPath(ctlDir, configId)}.tmp`);
  }

  static writeStop(ctlDir: string, configId: string): boolean {
    try {
      FrpControlFiles.ensureDir(ctlDir);
      let path = FrpControlFiles.stopPath(ctlDir, configId);
      let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.closeSync(file);
      return true;
    } catch (e) {
      return false;
    }
  }

  static removeStop(ctlDir: string, configId: string): void {
    FrpControlFiles.removeFile(FrpControlFiles.stopPath(ctlDir, configId));
  }

  static readExit(ctlDir: string, configId: string): FrpExitReport | undefined {
    try {
      let path = FrpControlFiles.exitPath(ctlDir, configId);
      if (!fs.accessSync(path)) {
        return undefined;
      }
      let raw = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      return FrpExitReport.fromJson(raw);
    } catch (e) {
      return undefined;
    }
  }

  static waitExit(ctlDir: string, configId: string, timeoutMs: number): Promise<FrpExitReport | undefined> {
    return new Promise<FrpExitReport | undefined>((resolve) => {
      let deadline = Date.now() + timeoutMs;
      let timerId = setInterval(() => {
        let report = FrpControlFiles.readExit(ctlDir, configId);
        if (report !== undefined) {
          clearInterval(timerId);
          resolve(report);
          return;
        }
        if (Date.now() >= deadline) {
          clearInterval(timerId);
          resolve(undefined);
        }
      }, 200);
    });
  }

  private static removeFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
    }
  }
}
