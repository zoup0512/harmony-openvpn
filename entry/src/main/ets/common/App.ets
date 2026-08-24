/**
 * Global application context holder.
 */

import { common } from '@kit.AbilityKit';
import { ProfileManager } from '../core/ProfileManager';
import { VpnStatus } from '../core/VpnStatus';
import { GP } from './GP';

export class App {
  private static inited: boolean = false;
  static context?: common.Context = undefined;

  static init(context: common.Context): void {
    App.context = context;
    if (App.inited) {
      return;
    }
    App.inited = true;
    ProfileManager.init(context);
    // The UI process reads the VPN snapshot; the VPN extension is the sole writer.
    VpnStatus.setPersistenceContext(context, false);
    GP.init(context).catch(() => {
    });
    ProfileManager.warmupPrefs().then(() => {
      ProfileManager.ensureLoaded();
    }).catch(() => {
    });
  }
}
