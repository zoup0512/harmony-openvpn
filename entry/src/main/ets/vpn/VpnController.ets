/**
 * UI-side VPN control: starts/stops the VpnExtensionAbility.
 */

import vpnExtension from '@ohos.net.vpnExtension';
import Want from '@ohos.app.ability.Want';
import fs from '@ohos.file.fs';
import { App } from '../common/App';
import { FileUtil } from '../common/FileUtil';

export class PendingStart {
  uuid: string = '';
  reason: string = 'unknown';
  response: string = '';
  dynamicChallengeCookie: string = '';
  authKind: string = '';
}

export class PendingAuthChallenge {
  uuid: string = '';
  kind: string = '';
  challenge: string = '';
  echo: boolean = false;
  responseRequired: boolean = true;
  cookie: string = '';
  expiresAt: number = 0;
}

export class VpnController {
  static readonly BUNDLE_NAME: string = 'com.razor.tools.openvpn';
  static readonly ABILITY_NAME: string = 'VpnServiceAbility';
  private static readonly PENDING_START_FILENAME: string = 'pending-start.json';
  private static readonly PENDING_AUTH_FILENAME: string = 'pending-auth.challenge';

  static startVpn(uuid: string, reason: string, response: string = '',
    dynamicChallengeCookie: string = '', authKind: string = ''): Promise<void> {
    // The system VPN authorization dialog starts the extension with a
    // system-generated want, so custom parameters may not reach onCreate.
    // Persist the request synchronously as the out-of-band channel.
    VpnController.writePendingStart(uuid, reason, response, dynamicChallengeCookie, authKind);
    let want: Want = {
      bundleName: VpnController.BUNDLE_NAME,
      abilityName: VpnController.ABILITY_NAME,
      parameters: {
        'de.blinkt.openvpn.profileUUID': uuid,
        'startReason': reason,
        'authResponse': response,
        'dynamicChallengeCookie': dynamicChallengeCookie,
        'authKind': authKind
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

  static stopVpn(): Promise<void> {
    VpnController.clearPendingStart();
    VpnController.clearPendingAuthChallenge();
    let want: Want = {
      bundleName: VpnController.BUNDLE_NAME,
      abilityName: VpnController.ABILITY_NAME
    };
    return vpnExtension.stopVpnExtensionAbility(want);
  }

  /** Request persisted by startVpn(); read by VpnServiceAbility when the want carries no uuid. */
  static readPendingStart(): PendingStart | undefined {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      return undefined;
    }
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
      let rec = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      let u = rec['uuid'];
      let r = rec['reason'];
      let response = rec['authResponse'];
      let cookie = rec['dynamicChallengeCookie'];
      let authKind = rec['authKind'];
      if (typeof u !== 'string' || u === '') {
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
      VpnController.clearPendingStart();
      return info;
    } catch (e) {
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
    dynamicChallengeCookie: string, authKind: string): void {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      return;
    }
    let info = new PendingStart();
    info.uuid = uuid;
    info.reason = reason;
    info.response = response;
    info.dynamicChallengeCookie = dynamicChallengeCookie;
    info.authKind = authKind;
    try {
      FileUtil.writeText(path, JSON.stringify(info));
    } catch (e) {
      // best effort: the want parameter may still be delivered on some builds
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
