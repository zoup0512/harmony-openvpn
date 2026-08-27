import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { App } from '../common/App';
import { R } from '../common/Res';
import { ProfileManager } from '../core/ProfileManager';
import { VpnController } from '../vpn/VpnController';

const SHORTCUT_PROFILE_UUID = 'de.blinkt.openvpn.profileUUID';
const SHORTCUT_START_REASON = 'startReason';
const SHORTCUT_REASON = 'shortcut';
const SHORTCUT_RETRY_COUNT = 4;
const SHORTCUT_RETRY_DELAY_MS = 150;
const SHORTCUT_DUPLICATE_WINDOW_MS = 2000;

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private lastShortcutUuid: string = '';
  private lastShortcutAt: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    App.init(this.context);
    R.init(this.context);
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onCreate');
    this.handleShortcutWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    App.init(this.context);
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onNewWant');
    this.handleShortcutWant(want);
  }

  private handleShortcutWant(want: Want): void {
    let uuid = EntryAbility.readStringParameter(want, SHORTCUT_PROFILE_UUID);
    let reason = EntryAbility.readStringParameter(want, SHORTCUT_START_REASON);
    if (uuid === undefined || uuid === '' || reason !== SHORTCUT_REASON) {
      return;
    }

    let now = Date.now();
    if (uuid === this.lastShortcutUuid && now - this.lastShortcutAt < SHORTCUT_DUPLICATE_WINDOW_MS) {
      hilog.info(DOMAIN, 'OpenVPN', 'Ignoring duplicate shortcut launch for %{public}s', uuid);
      return;
    }
    this.lastShortcutUuid = uuid;
    this.lastShortcutAt = now;
    this.startShortcutVpn(uuid, 0);
  }

  private startShortcutVpn(uuid: string, attempt: number): void {
    let profile = ProfileManager.get(uuid);
    if (profile !== undefined && profile !== null) {
      VpnController.startVpn(uuid, SHORTCUT_REASON).then(() => {
        hilog.info(DOMAIN, 'OpenVPN', 'Shortcut VPN start requested for %{public}s', uuid);
      }).catch((error: Error) => {
        hilog.error(DOMAIN, 'OpenVPN', 'Shortcut VPN start failed for %{public}s: %{public}s', uuid,
          error.message);
      });
      return;
    }

    if (attempt >= SHORTCUT_RETRY_COUNT) {
      hilog.error(DOMAIN, 'OpenVPN', 'Shortcut profile not found after retries: %{public}s', uuid);
      return;
    }

    setTimeout(() => {
      ProfileManager.ensureLoaded();
      this.startShortcutVpn(uuid, attempt + 1);
    }, SHORTCUT_RETRY_DELAY_MS);
  }

  private static readStringParameter(want: Want, key: string): string | undefined {
    let parameters = want.parameters;
    if (parameters === undefined || parameters === null) {
      return undefined;
    }
    let value = parameters[key];
    return typeof value === 'string' ? value : undefined;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'OpenVPN', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'OpenVPN', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'OpenVPN', '%{public}s', 'Ability onBackground');
  }
}
