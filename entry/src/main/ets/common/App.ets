/**
 * Global application context holder.
 */

import { common } from '@kit.AbilityKit';
import { ProfileManager } from '../core/ProfileManager';
import { VpnStatus } from '../core/VpnStatus';
import { GP } from './GP';
import { VpnTrafficStore } from '../core/VpnTrafficStore';

export class App {
  private static inited: boolean = false;
  static context?: common.Context = undefined;
  static uiContext?: common.UIAbilityContext = undefined;

  static setUiContext(context: common.UIAbilityContext): void {
    App.uiContext = context;
    App.init(context);
  }

  static init(context: common.Context): void {
    if (App.context === undefined) {
      App.context = context;
    }
    if (App.inited) {
      return;
    }
    App.inited = true;
    ProfileManager.init(context);
    // The UI process reads VPN snapshots; the VPN extension is the sole writer.
    VpnStatus.setPersistenceContext(context, false);
    VpnTrafficStore.setPersistenceContext(context, false);
    GP.init(context).catch(() => {
    });
    ProfileManager.warmupPrefs().then(() => {
      ProfileManager.ensureLoaded();
    }).catch(() => {
    });
  }
}
