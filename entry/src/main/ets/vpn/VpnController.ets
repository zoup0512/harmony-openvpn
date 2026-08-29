/**
 * UI-side VPN control: starts/stops the VpnExtensionAbility.
 */

import vpnExtension from '@ohos.net.vpnExtension';
import Want from '@ohos.app.ability.Want';
import fs from '@ohos.file.fs';
import notificationManager from '@ohos.notificationManager';
import { App } from '../common/App';
import { FileUtil } from '../common/FileUtil';
import { VpnStatus } from '../core/VpnStatus';
import { LogLevel } from '../core/LogItem';

export class PendingStart {
  uuid: string = '';
  reason: string = 'unknown';
  response: string = '';
  dynamicChallengeCookie: string = '';
  authKind: string = '';
  username: string = '';
  password: string = '';
}

export class PendingAuthChallenge {
  uuid: string = '';
  kind: string = '';
  challenge: string = '';
  echo: boolean = false;
  responseRequired: boolean = true;
  cookie: string = '';
  // When an OTP arrived but no password was available, the response rides
  // here so the credentials resubmission completes the same challenge round
  // (also survives a VPN extension process restart, unlike memory state).
  response: string = '';
  username: string = '';
  expiresAt: number = 0;
}

export class SessionCredentialsRecord {
  uuid: string = '';
  username: string = '';
  password: string = '';
  expiresAt: number = 0;
}

export class VpnController {
  static readonly BUNDLE_NAME: string = 'com.razor.tools.openvpn';
  static readonly ABILITY_NAME: string = 'VpnServiceAbility';
  /** Same id as the extension's ongoing VPN notification. */
  static readonly VPN_NOTIFICATION_ID: number = 1;
  private static readonly PENDING_START_FILENAME: string = 'pending-start.json';
  private static readonly PENDING_AUTH_FILENAME: string = 'pending-auth.challenge';
  private static readonly SESSION_CREDS_FILENAME: string = 'session-creds.json';

  static startVpn(uuid: string, reason: string, response: string = '',
    dynamicChallengeCookie: string = '', authKind: string = '', username: string = '',
    password: string = ''): Promise<void> {
    // The system VPN authorization dialog starts the extension with a
    // system-generated want, so custom parameters may not reach onCreate.
    // Persist the request synchronously as the out-of-band channel.
    VpnController.writePendingStart(uuid, reason, response, dynamicChallengeCookie, authKind, username, password);
    let want: Want = {
      bundleName: VpnController.BUNDLE_NAME,
      abilityName: VpnController.ABILITY_NAME,
      parameters: {
        'de.blinkt.openvpn.profileUUID': uuid,
        'startReason': reason,
        'authResponse': response,
        'dynamicChallengeCookie': dynamicChallengeCookie,
        'authKind': authKind,
        'username': username,
        'password': password
      } as Record<string, Object>
    };
    return vpnExtension.startVpnExtensionAbility(want);
  }

  static writePendingAuthChallenge(challenge: PendingAuthChallenge): void {
    let path = VpnController.pendingAuthPath();
    if (path === undefined) {
      return;
    }
    try {
      FileUtil.writeText(path, JSON.stringify(challenge));
    } catch (e) {
    }
  }

  static readPendingAuthChallenge(): PendingAuthChallenge | undefined {
    let path = VpnController.pendingAuthPath();
    if (path === undefined) {
      return undefined;
    }
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
      let rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      let expiresAt = rec['expiresAt'];
      if (typeof expiresAt !== 'number' || expiresAt <= Date.now()) {
        VpnController.clearPendingAuthChallenge();
        return undefined;
      }
      let info = new PendingAuthChallenge();
      let uuid = rec['uuid'];
      let kind = rec['kind'];
      let challenge = rec['challenge'];
      let echo = rec['echo'];
      let responseRequired = rec['responseRequired'];
      let cookie = rec['cookie'];
      let response = rec['response'];
      let username = rec['username'];
      if (typeof uuid === 'string') {
        info.uuid = uuid;
      }
      if (typeof kind === 'string') {
        info.kind = kind;
      }
      if (typeof challenge === 'string') {
        info.challenge = challenge;
      }
      if (typeof echo === 'boolean') {
        info.echo = echo;
      }
      if (typeof responseRequired === 'boolean') {
        info.responseRequired = responseRequired;
      }
      if (typeof cookie === 'string') {
        info.cookie = cookie;
      }
      if (typeof response === 'string') {
        info.response = response;
      }
      if (typeof username === 'string') {
        info.username = username;
      }
      info.expiresAt = expiresAt;
      return info;
    } catch (e) {
      VpnController.clearPendingAuthChallenge();
      return undefined;
    }
  }

  static clearPendingAuthChallenge(): void {
    VpnController.deleteFile(VpnController.pendingAuthPath());
  }

  static clearPendingStartRequest(): void {
    VpnController.clearPendingStart();
  }

  // ---- Session credentials bridge -------------------------------------
  // The VPN extension ability instance can be destroyed and recreated while
  // the user fetches an OTP (in-memory session credentials die with it).
  // Bridge them through the same app-private, short-TTL, auto-wiped file
  // mechanism used for the CRV1 challenge cookie.

  static writeSessionCredentials(uuid: string, username: string, password: string,
    expiresAt: number): void {
    let path = VpnController.sessionCredsPath();
    if (path === undefined) {
      return;
    }
    let rec = new SessionCredentialsRecord();
    rec.uuid = uuid;
    rec.username = username;
    rec.password = password;
    rec.expiresAt = expiresAt;
    try {
      FileUtil.writeText(path, JSON.stringify(rec));
      VpnStatus.logMessage(LogLevel.DEBUG,
        `Session credentials bridged for ${uuid} (expires in ${Math.max(0, expiresAt - Date.now())}ms).`);
    } catch (e) {
      let message = e instanceof Error ? e.message : `${e}`;
      VpnStatus.logMessage(LogLevel.WARNING, `Failed to bridge session credentials: ${message}`);
    }
  }

  static readSessionCredentials(): SessionCredentialsRecord | undefined {
    let path = VpnController.sessionCredsPath();
    if (path === undefined) {
      return undefined;
    }
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
      let rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      let uuid = rec['uuid'];
      let expiresAt = rec['expiresAt'];
      if (typeof uuid !== 'string' || uuid === '' || typeof expiresAt !== 'number') {
        VpnController.clearSessionCredentialsFile();
        return undefined;
      }
      if (expiresAt <= Date.now()) {
        VpnController.clearSessionCredentialsFile();
        return undefined;
      }
      let out = new SessionCredentialsRecord();
      out.uuid = uuid;
      out.expiresAt = expiresAt;
      let u = rec['username'];
      if (typeof u === 'string') {
        out.username = u;
      }
      let p = rec['password'];
      if (typeof p === 'string') {
        out.password = p;
      }
      return out;
    } catch (e) {
      VpnController.clearSessionCredentialsFile();
      return undefined;
    }
  }

  static clearSessionCredentialsFile(): void {
    VpnController.deleteFile(VpnController.sessionCredsPath());
  }

  private static sessionCredsPath(): string | undefined {
    return VpnController.filePath(VpnController.SESSION_CREDS_FILENAME);
  }

  /**
   * Cancel the ongoing VPN notification from any process of this bundle.
   * Notifications do not die with the publishing process: when the VPN
   * extension was killed without onDestroy, its "Connected" notice would
   * otherwise linger forever.
   */
  static cancelVpnNotification(): void {
    try {
      notificationManager.cancel(VpnController.VPN_NOTIFICATION_ID);
    } catch (e) {
      // nothing published — fine
    }
  }

  static stopVpn(): Promise<void> {
    VpnController.clearPendingStart();
    VpnController.clearPendingAuthChallenge();
    // The extension cancels its own notification on onDestroy, but if it was
    // already dead there is nobody left to cancel — do it here as well.
    VpnController.cancelVpnNotification();
    let want: Want = {
      bundleName: VpnController.BUNDLE_NAME,
      abilityName: VpnController.ABILITY_NAME
    };
    return vpnExtension.stopVpnExtensionAbility(want);
  }

  /** Read for logs/diagnostics: where the pending start file is and whether it exists. */
  static pendingStartDebugInfo(): string {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      return 'path unknown (App context not initialized)';
    }
    try {
      return fs.accessSync(path) ? `present at ${path}` : `missing at ${path}`;
    } catch (e) {
      return `unreadable at ${path}`;
    }
  }

  /** Request persisted by startVpn(); read by VpnServiceAbility when the want carries no uuid. */
  static readPendingStart(): PendingStart | undefined {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      VpnStatus.logMessage(LogLevel.ERROR,
        'readPendingStart: App context not initialized, cannot locate the pending start file.');
      return undefined;
    }
    try {
      if (!fs.accessSync(path)) {
        VpnStatus.logMessage(LogLevel.DEBUG, `readPendingStart: no pending start file at ${path}.`);
        return undefined;
      }
      let rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      let u = rec['uuid'];
      let r = rec['reason'];
      let response = rec['response'];
      if (typeof response !== 'string') {
        response = rec['authResponse'];
      }
      let cookie = rec['dynamicChallengeCookie'];
      let authKind = rec['authKind'];
      let username = rec['username'];
      let password = rec['password'];
      if (typeof u !== 'string' || u === '') {
        VpnStatus.logMessage(LogLevel.WARNING,
          `readPendingStart: file at ${path} has no valid uuid entry.`);
        return undefined;
      }
      let info = new PendingStart();
      info.uuid = u;
      if (typeof r === 'string' && r !== '') {
        info.reason = r;
      }
      if (typeof response === 'string') {
        info.response = response;
      }
      if (typeof cookie === 'string') {
        info.dynamicChallengeCookie = cookie;
      }
      if (typeof authKind === 'string') {
        info.authKind = authKind;
      }
      if (typeof username === 'string') {
        info.username = username;
      }
      if (typeof password === 'string') {
        info.password = password;
      }
      VpnStatus.logMessage(LogLevel.DEBUG,
        `readPendingStart: using pending request for ${u} (reason=${info.reason}, ` +
        `hasResponse=${info.response !== ''}, hasCookie=${info.dynamicChallengeCookie !== ''}, ` +
        `hasUser=${info.username !== ''}, hasPass=${info.password !== ''}).`);
      VpnController.clearPendingStart();
      return info;
    } catch (e) {
      let message = e instanceof Error ? e.message : `${e}`;
      VpnStatus.logMessage(LogLevel.WARNING,
        `readPendingStart: failed to read ${path}: ${message}`);
      return undefined;
    }
  }

  private static pendingStartPath(): string | undefined {
    return VpnController.filePath(VpnController.PENDING_START_FILENAME);
  }

  private static pendingAuthPath(): string | undefined {
    return VpnController.filePath(VpnController.PENDING_AUTH_FILENAME);
  }

  private static filePath(name: string): string | undefined {
    let ctx = App.context;
    if (ctx === undefined || ctx === null) {
      return undefined;
    }
    return `${ctx.filesDir}/${name}`;
  }

  private static writePendingStart(uuid: string, reason: string, response: string,
    dynamicChallengeCookie: string, authKind: string, username: string, password: string): void {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      VpnStatus.logMessage(LogLevel.ERROR,
        'writePendingStart: App context not initialized, cannot persist the start request.');
      return;
    }
    let info = new PendingStart();
    info.uuid = uuid;
    info.reason = reason;
    info.response = response;
    info.dynamicChallengeCookie = dynamicChallengeCookie;
    info.authKind = authKind;
    info.username = username;
    info.password = password;
    try {
      FileUtil.writeText(path, JSON.stringify(info));
      VpnStatus.logMessage(LogLevel.DEBUG,
        `Pending start request persisted for ${uuid} (reason=${reason}, hasResponse=${response !== ''}, ` +
        `hasCookie=${dynamicChallengeCookie !== ''}, hasUser=${username !== ''}, hasPass=${password !== ''}).`);
    } catch (e) {
      let message = e instanceof Error ? e.message : `${e}`;
      VpnStatus.logMessage(LogLevel.ERROR,
        `writePendingStart: failed to write ${path}: ${message}`);
    }
  }

  private static clearPendingStart(): void {
    VpnController.deleteFile(VpnController.pendingStartPath());
  }

  private static deleteFile(path?: string): void {
    if (path === undefined) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
    }
  }
}
