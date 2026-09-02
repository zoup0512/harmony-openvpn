import childProcessManager from '@ohos.app.ability.childProcessManager';
import type { ChildProcessArgs } from '@ohos.app.ability.ChildProcessArgs';
import type { ChildProcessOptions } from '@ohos.app.ability.ChildProcessOptions';
import * as frpglue from 'libfrpglue.so';
import { FrpConfig } from '../core/FrpConfig';
import { FrpControlFiles, FrpExitReport } from '../core/FrpControlFiles';
import { FrpType } from '../core/FrpType';

export class FrpRuntimeCapability {
  available: boolean = false;
  entryPoint: string = '';
  message: string = '';
  constructor(available: boolean, entryPoint: string, message: string) {
    this.available = available;
    this.entryPoint = entryPoint;
    this.message = message;
  }
}

export class FrpRuntimeHandle {
  configId: string = '';
  type: FrpType = FrpType.FRPC;
  pid: number = 0;
  mode: string = '';
  ctlDir: string = '';
  logPath: string = '';
  startedAt: number = 0;
  constructor(configId: string, type: FrpType, pid: number, mode: string, ctlDir: string, logPath: string) {
    this.configId = configId;
    this.type = type;
    this.pid = pid;
    this.mode = mode;
    this.ctlDir = ctlDir;
    this.logPath = logPath;
    this.startedAt = Date.now();
  }
}

/**
 * Boundary to the bundled Go frpc core (libfrp_host.so, built from
 * native/frpc-host). Preferred mode is a native child process via
 * childProcessManager; devices that cannot spawn native child processes
 * fall back to loading the same core in-process through the frpglue NAPI
 * bridge. Only frpc is bundled — frps is rejected before any launch.
 */
export class FrpRuntimeAdapter {
  static readonly NATIVE_ENTRY_POINT: string = 'libfrp_host.so:Main';
  static readonly MODE_CHILD: string = 'child';
  static readonly MODE_INLINE: string = 'inline';

  static probeCapability(): FrpRuntimeCapability {
    let childSupported = canIUse('SystemCapability.Ability.AbilityRuntime.Core');
    if (!childSupported) {
      return new FrpRuntimeCapability(true, FrpRuntimeAdapter.NATIVE_ENTRY_POINT,
        'frp 核心已就绪（进程内模式）');
    }
    return new FrpRuntimeCapability(true, FrpRuntimeAdapter.NATIVE_ENTRY_POINT, '');
  }

  static async start(config: FrpConfig, configPath: string, logPath: string,
    ctlDir: string): Promise<FrpRuntimeHandle> {
    if (config.type !== FrpType.FRPC) {
      throw new Error('当前核心仅内置 frpc 客户端，暂不支持运行 frps 服务端');
    }
    FrpControlFiles.prepareStart(ctlDir, config.key);

    let childError = '';
    if (canIUse('SystemCapability.Ability.AbilityRuntime.Core')) {
      try {
        let args: ChildProcessArgs = {
          entryParams: FrpRuntimeAdapter.entryParams(config, configPath, logPath, ctlDir,
            FrpRuntimeAdapter.MODE_CHILD)
        };
        let options: ChildProcessOptions = {
          // An isolated child process has no network access; frpc must share
          // the app sandbox and its network context.
          isolationMode: false
        };
        let pid = await childProcessManager.startNativeChildProcess(
          FrpRuntimeAdapter.NATIVE_ENTRY_POINT, args, options);
        return new FrpRuntimeHandle(config.key, config.type, pid, FrpRuntimeAdapter.MODE_CHILD,
          ctlDir, logPath);
      } catch (e) {
        childError = (e as Error).message;
      }
    }

    try {
      let rc: number = frpglue.runFrpHost(
        FrpRuntimeAdapter.entryParams(config, configPath, logPath, ctlDir, FrpRuntimeAdapter.MODE_INLINE));
      if (rc === 0) {
        return new FrpRuntimeHandle(config.key, config.type, 0, FrpRuntimeAdapter.MODE_INLINE,
          ctlDir, logPath);
      }
      throw new Error(`frp 核心进程内启动失败 (code ${rc})`);
    } catch (e) {
      let reason = (e as Error).message;
      let detail = childError !== '' ? `（子进程通道不可用：${childError}）` : '';
      throw new Error(`frp 核心进程内启动失败：${reason}${detail}`);
    }
  }

  /** Signals a graceful stop and waits for the host exit report. */
  static async stop(handle: FrpRuntimeHandle): Promise<FrpExitReport | undefined> {
    FrpControlFiles.writeStop(handle.ctlDir, handle.configId);
    return FrpControlFiles.waitExit(handle.ctlDir, handle.configId, 8000);
  }

  static readExitReport(handle: FrpRuntimeHandle): FrpExitReport | undefined {
    return FrpControlFiles.readExit(handle.ctlDir, handle.configId);
  }

  static describeMode(handle: FrpRuntimeHandle): string {
    return handle.mode === FrpRuntimeAdapter.MODE_CHILD ? `pid ${handle.pid}` : '进程内';
  }

  /**
   * Loads the Go core in-process and runs a minimal entry (invalid params,
   * host returns 3). Diagnostics only: proves dlopen + Go runtime + cgo entry
   * all work before any real launch.
   */
  static selfTest(): number {
    return frpglue.runFrpHost('{}');
  }

  private static entryParams(config: FrpConfig, configPath: string, logPath: string,
    ctlDir: string, mode: string): string {
    return JSON.stringify({
      'type': config.type,
      'configId': config.key,
      'configPath': configPath,
      'logPath': logPath,
      'ctlDir': ctlDir,
      'mode': mode,
      'version': 1
    });
  }
}
