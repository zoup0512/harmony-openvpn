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
}

export class VpnController {
  static readonly BUNDLE_NAME: string = 'com.razor.tools.openvpn';
  static readonly ABILITY_NAME: string = 'VpnServiceAbility';
  private static readonly PENDING_START_FILENAME: string = 'pending-start.json';

  static startVpn(uuid: string, reason: string): Promise<void> {
    // The system VPN authorization dialog starts the extension with a
    // system-generated want, so custom parameters may not reach onCreate.
    // Persist the request synchronously as the out-of-band channel.
    VpnController.writePendingStart(uuid, reason);
    let want: Want = {
      bundleName: VpnController.BUNDLE_NAME,
      abilityName: VpnController.ABILITY_NAME,
      parameters: {
        'de.blinkt.openvpn.profileUUID': uuid,
        'startReason': reason
      } as Record<string, Object>
    };
    return vpnExtension.startVpnExtensionAbility(want);
  }

  static stopVpn(): Promise<void> {
    VpnController.clearPendingStart();
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
      if (typeof u !== 'string' || u === '') {
        return undefined;
      }
      let info = new PendingStart();
      info.uuid = u;
      if (typeof r === 'string' && r !== '') {
        info.reason = r;
      }
      return info;
    } catch (e) {
      return undefined;
    }
  }

  private static pendingStartPath(): string | undefined {
    let ctx = App.context;
    if (ctx === undefined || ctx === null) {
      return undefined;
    }
    return `${ctx.filesDir}/${VpnController.PENDING_START_FILENAME}`;
  }

  private static writePendingStart(uuid: string, reason: string): void {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      return;
    }
    let info = new PendingStart();
    info.uuid = uuid;
    info.reason = reason;
    try {
      FileUtil.writeText(path, JSON.stringify(info));
    } catch (e) {
      // best effort: the want parameter may still be delivered on some builds
    }
  }

  private static clearPendingStart(): void {
    let path = VpnController.pendingStartPath();
    if (path === undefined) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // ignore
    }
  }
}
