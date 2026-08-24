/**
 * Settings tab — replicates GeneralSettings (app behaviour + VPN behaviour).
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { GP } from '../../common/GP';
import { PrefCategory, CheckRow, SwitchRow, TapRow } from '../PrefRows';
import { ProfileManager } from '../../core/ProfileManager';
import { VpnProfile } from '../../core/VpnProfile';
import { promptAction } from '@kit.ArkUI';

@Component
export struct SettingsTab {
  @State showlogwindow: boolean = true;
  @State allowTranslation: boolean = true;
  @State ovpn3: boolean = false;
  @State alwaysOnVpnName: string = '';
  @State restartvpnonboot: boolean = false;
  @State preferencryption: boolean = true;
  @State usesystemproxy: boolean = true;
  @State netchangereconnect: boolean = true;
  @State screenoff: boolean = false;
  @State disableconfirmation: boolean = false;

  aboutToAppear(): void {
    this.showlogwindow = GP.getBool('showlogwindow', true);
    this.allowTranslation = GP.getBool('allow_translation', true);
    this.ovpn3 = false;
    this.restartvpnonboot = GP.getBool('restartvpnonboot', false);
    this.preferencryption = GP.getBool('preferencryption', true);
    this.usesystemproxy = GP.getBool('usesystemproxy', true);
    this.netchangereconnect = GP.getBool('netchangereconnect', true);
    this.screenoff = GP.getBool('screenoff', false);
    this.disableconfirmation = GP.getBool('disableconfirmation', false);
    this.updateAlwaysOnName();
  }

  private updateAlwaysOnName(): void {
    let vpn = ProfileManager.getAlwaysOnVPN();
    if (vpn !== undefined && vpn !== null) {
      this.alwaysOnVpnName = `${R.s('defaultvpnsummary')}\n${R.s('currently_selected_vpn', vpn.getName())}`;
    } else {
      this.alwaysOnVpnName = `${R.s('defaultvpnsummary')}\n${R.s('no_vpn_selected')}`;
    }
  }

  private pickAlwaysOnVpn(): void {
    let profiles = ProfileManager.getProfiles();
    if (profiles.length === 0) {
      promptAction.showToast({ message: R.s('no_vpn_selected') });
      return;
    }
    let buttons: Array<SheetInfo> = [];
    for (let p of profiles) {
      let name = p.getName();
      buttons.push({
        title: name,
        action: () => {
          ProfileManager.setAlwaysOnVPN(p.getUUID());
          this.updateAlwaysOnName();
        }
      });
    }
    let confirmBtn: ActionSheetButtonOptions = {
      value: R.s('cancel'),
      action: () => {
      }
    };
    let sheetOptions: ActionSheetOptions = {
      title: R.s('alwaysOnVpn'),
      message: '',
      sheets: buttons,
      confirm: confirmBtn,
      cancel: () => {
      }
    };
    ActionSheet.show(sheetOptions);
  }

  build() {
    Scroll() {
      Column() {
        PrefCategory({ title: R.s('app_behaviour') })
        CheckRow({
          title: R.s('showlogwindow'), summary: R.s('showlogwindow_summary'),
          checked: this.showlogwindow,
          onChange: (v: boolean) => {
            this.showlogwindow = v;
            GP.setBool('showlogwindow', v);
          }
        })
        CheckRow({
          title: R.s('allow_translation'), summary: R.s('allow_translation_summary'),
          checked: this.allowTranslation,
          onChange: (v: boolean) => {
            this.allowTranslation = v;
            GP.setBool('allow_translation', v);
          }
        })
        CheckRow({
          title: R.s('ovpn3'), summary: `${R.s('ovpn3_summary_off')} (${R.s('not_available_this_build')})`,
          checked: false, rowEnabled: false
        })
        TapRow({
          title: R.s('alwaysOnVpn'), summary: this.alwaysOnVpnName,
          onRowClick: () => {
            this.pickAlwaysOnVpn();
          }
        })
        CheckRow({
          title: R.s('restartvpnonboot'), summary: '',
          checked: this.restartvpnonboot,
          onChange: (v: boolean) => {
            let alwaysOn = ProfileManager.getAlwaysOnVPN();
            if (v && (alwaysOn === undefined || alwaysOn === null)) {
              promptAction.showToast({ message: R.s('no_default_vpn_set') });
              return;
            }
            this.restartvpnonboot = v;
            GP.setBool('restartvpnonboot', v);
          }
        })
        CheckRow({
          title: R.s('preferencryption'), summary: '',
          checked: this.preferencryption,
          onChange: (v: boolean) => {
            this.preferencryption = v;
            GP.setBool('preferencryption', v);
          }
        })

        PrefCategory({ title: R.s('vpnbehaviour') })
        CheckRow({
          title: R.s('usesystemproxy'), summary: R.s('usesystemproxy_summary'),
          checked: this.usesystemproxy,
          onChange: (v: boolean) => {
            this.usesystemproxy = v;
            GP.setBool('usesystemproxy', v);
          }
        })
        CheckRow({
          title: R.s('netchangereconnect'), summary: R.s('netchangereconnect_summary'),
          checked: this.netchangereconnect,
          onChange: (v: boolean) => {
            this.netchangereconnect = v;
            GP.setBool('netchangereconnect', v);
          }
        })
        CheckRow({
          title: R.s('screenoff'), summary: R.s('screenoff_summary'),
          checked: this.screenoff,
          onChange: (v: boolean) => {
            this.screenoff = v;
            GP.setBool('screenoff', v);
          }
        })
        CheckRow({
          title: R.s('disableconfirmation'), summary: '',
          checked: this.disableconfirmation,
          onChange: (v: boolean) => {
            this.disableconfirmation = v;
            GP.setBool('disableconfirmation', v);
          }
        })
        TapRow({
          title: R.s('osslspeed'),
          summary: `${R.s('osslspeed_summary')} (${R.s('not_available_this_build')})`,
          rowEnabled: false,
          onRowClick: () => {
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
