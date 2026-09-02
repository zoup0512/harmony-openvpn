import { FrpConfig } from '../core/FrpConfig';
import { FrpConfigManager } from '../core/FrpConfigManager';
import { FrpControlFiles, FrpExitReport } from '../core/FrpControlFiles';
import { FrpLogLevel, FrpLogStore } from '../core/FrpLogStore';
import { FrpRunState, FrpStatus } from '../core/FrpStatus';
import { FrpType } from '../core/FrpType';
import { FrpValidator } from '../core/FrpValidator';
import { FrpRuntimeAdapter, FrpRuntimeCapability, FrpRuntimeHandle } from './FrpRuntimeAdapter';

/**
 * UI-side runtime owner for the bundled frpc core. Runs in the app process:
 * the child-process mode keeps frpc isolated, the inline fallback keeps it in
 * a goroutine. All lifecycle state lands in FrpStatus/FrpLogStore through
 * file reports produced by the Go host.
 */
export class FrpController {
  private static handles: Map<string, FrpRuntimeHandle> = new Map<string, FrpRuntimeHandle>();
  private static monitorId: number = -1;
  private static reconciled: boolean = false;

  static probeCapability(): FrpRuntimeCapability {
    FrpController.reconcileOnce();
    return FrpRuntimeAdapter.probeCapability();
  }

  static start(config: FrpConfig): Promise<void> {
    FrpController.reconcileOnce();
    if (config.type !== FrpType.FRPC) {
      let message = '当前核心仅内置 frpc 客户端，暂不支持运行 frps 服务端';
      FrpStatus.markUnavailable(config, message);
      FrpLogStore.append(config, message, FrpLogLevel.ERROR);
      return Promise.reject(new Error(message));
    }
    if (FrpController.handles.has(config.key)) {
      return Promise.resolve();
    }
    let content = FrpConfigManager.read(config);
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      let message = validation.message === '' ? 'frpc 配置验证失败' : validation.message;
      FrpStatus.update(config, FrpRunState.FAILED, message);
      return Promise.reject(new Error(message));
    }
    let root = FrpConfigManager.rootPath();
    let ctlDir = FrpControlFiles.ctlDir(root);
    FrpStatus.update(config, FrpRunState.STARTING, '正在启动 frpc');
    return FrpRuntimeAdapter.start(config, config.getConfigPath(root), config.getLogPath(root), ctlDir)
      .then((handle: FrpRuntimeHandle) => {
        FrpController.handles.set(config.key, handle);
        let where = FrpRuntimeAdapter.describeMode(handle);
        FrpStatus.update(config, FrpRunState.RUNNING, `frpc 运行中（${where}）`);
        FrpLogStore.append(config, `frpc started (${where})`, FrpLogLevel.INFO);
        FrpController.ensureMonitor();
      }).catch((error: Error) => {
        let message = error.message === '' ? 'frp 核心启动失败' : error.message;
        FrpStatus.update(config, FrpRunState.FAILED, message);
        FrpLogStore.append(config, message, FrpLogLevel.ERROR);
        throw new Error(message);
      });
  }

  static stop(config: FrpConfig): Promise<void> {
    let handle = FrpController.handles.get(config.key);
    if (handle === undefined) {
      FrpStatus.update(config, FrpRunState.STOPPED, 'frpc 未运行');
      return Promise.resolve();
    }
    FrpStatus.update(config, FrpRunState.STOPPING, '正在停止 frpc');
    return FrpRuntimeAdapter.stop(handle).then((report: FrpExitReport | undefined) => {
      FrpController.handles.delete(config.key);
      if (report === undefined) {
        FrpStatus.update(config, FrpRunState.FAILED, '停止超时：frpc 未在期限内退出，下次启动将自动清理残留实例');
        FrpLogStore.append(config, 'frpc stop timed out', FrpLogLevel.ERROR);
      } else {
        FrpController.applyExitReport(config, report, true);
      }
    });
  }

  static stopAll(): Promise<void> {
    let ids: string[] = [];
    FrpController.handles.forEach((handle: FrpRuntimeHandle, id: string) => {
      ids.push(id);
    });
    let pending: Promise<void>[] = [];
    for (let id of ids) {
      let config = FrpConfigManager.getById(id);
      if (config !== undefined) {
        pending.push(FrpController.stop(config));
      }
    }
    return Promise.all(pending).then(() => {
    });
  }

  static restart(config: FrpConfig): Promise<void> {
    return FrpController.stop(config).then(() => {
      return new Promise<void>((resolve) => {
        setTimeout(() => {
          FrpController.start(config).then(() => resolve()).catch(() => resolve());
        }, 150);
      });
    });
  }

  static getStatus(config: FrpConfig) {
    FrpConfigManager.ensureLoaded();
    FrpStatus.restoreFromDisk();
    return FrpStatus.get(config);
  }

  static getLog(config: FrpConfig): string {
    return FrpLogStore.readText(config);
  }

  static clearLog(config: FrpConfig): boolean {
    return FrpLogStore.clear(config);
  }

  /** Marks states left behind by a previous process lifetime as crashed. */
  private static reconcileOnce(): void {
    if (FrpController.reconciled) {
      return;
    }
    FrpController.reconciled = true;
    FrpConfigManager.ensureLoaded();
    FrpStatus.reconcileStaleActiveStates('应用已重启，原 frpc 实例已失效');
  }

  private static ensureMonitor(): void {
    if (FrpController.monitorId !== -1) {
      return;
    }
    FrpController.monitorId = setInterval(() => {
      FrpController.sweepExitReports();
      if (FrpController.handles.size === 0 && FrpController.monitorId !== -1) {
        clearInterval(FrpController.monitorId);
        FrpController.monitorId = -1;
      }
    }, 1200) as number;
  }

  private static sweepExitReports(): void {
    let ids: string[] = [];
    FrpController.handles.forEach((handle: FrpRuntimeHandle, id: string) => {
      ids.push(id);
    });
    for (let id of ids) {
      let handle = FrpController.handles.get(id);
      if (handle === undefined) {
        continue;
      }
      let report = FrpRuntimeAdapter.readExitReport(handle);
      if (report === undefined) {
        continue;
      }
      FrpController.handles.delete(id);
      let config = FrpConfigManager.getById(id);
      if (config !== undefined) {
        let stopping = FrpStatus.get(config).state === FrpRunState.STOPPING;
        FrpController.applyExitReport(config, report, stopping);
      }
    }
  }

  private static applyExitReport(config: FrpConfig, report: FrpExitReport, stoppedByUser: boolean): void {
    switch (report.code) {
      case 0:
        FrpStatus.update(config, FrpRunState.STOPPED, stoppedByUser ? 'frpc 已停止' : 'frpc 已退出');
        FrpLogStore.append(config, 'frpc stopped', FrpLogLevel.INFO);
        break;
      case 2:
        FrpStatus.update(config, FrpRunState.FAILED, `配置错误：${report.message}`);
        FrpLogStore.append(config, report.message, FrpLogLevel.ERROR);
        break;
      case 3:
        FrpStatus.update(config, FrpRunState.UNAVAILABLE, report.message);
        FrpLogStore.append(config, report.message, FrpLogLevel.ERROR);
        break;
      default:
        FrpStatus.update(config, FrpRunState.CRASHED, `frpc 异常退出：${report.message}`);
        FrpLogStore.append(config, report.message, FrpLogLevel.ERROR);
        break;
    }
  }
}
