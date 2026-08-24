/**
 * Allowed Apps tab — port of Settings_Allowed_Apps. Third party apps cannot
 * enumerate the installed applications on HarmonyOS, so the package list is
 * edited manually (stored exactly like the Android per-app VPN lists).
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { InputDialog, InputDialogModel } from '../InputDialog';

@Component
export struct AllowedAppsTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State disallowedMode: boolean = true;
  @State allowBypass: boolean = false;
  @State apps: string[] = [];
  private addModel: InputDialogModel = new InputDialogModel();
  private addDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.addModel }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    this.disallowedMode = this.profile.mAllowedAppsVpnAreDisallowed;
    this.allowBypass = this.profile.mAllowAppVpnBypass;
    this.reload();
  }

  private reload(): void {
    let list: string[] = [];
    this.profile.mAllowedAppsVpn.forEach((a: string) => {
      list.push(a);
    });
    list.sort();
    this.apps = list;
  }

  private toggleApp(pkg: string): void {
    if (this.profile.mAllowedAppsVpn.has(pkg)) {
      this.profile.mAllowedAppsVpn.delete(pkg);
    } else {
      this.profile.mAllowedAppsVpn.add(pkg);
    }
    this.reload();
  }

  build() {
    Column() {
      // default allow switch bar
      Row() {
        Text(this.disallowedMode ? R.s('vpn_disallow_radio') : R.s('vpn_allow_radio'))
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.disallowedMode })
          .selectedColor(Theme.ACCENT)
          .onChange((v: boolean) => {
            this.disallowedMode = v;
            this.profile.mAllowedAppsVpnAreDisallowed = v;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#E6E6E6')

      // bypass bar
      Row() {
        Text(R.s('vpn_allow_bypass'))
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.allowBypass })
          .selectedColor(Theme.ACCENT)
          .onChange((v: boolean) => {
            this.allowBypass = v;
            this.profile.mAllowAppVpnBypass = v;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F2F2F2')

      Text(R.s('allowed_apps_manual_hint'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

      List() {
        ForEach(this.apps, (pkg: string) => {
          ListItem() {
            Row() {
              Text(pkg)
                .fontSize(14)
                .fontColor(Theme.TEXT_PRIMARY)
                .layoutWeight(1)
              Checkbox()
                .select(true)
                .selectedColor(Theme.PRIMARY)
                .onChange((v: boolean) => {
                  this.toggleApp(pkg);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(Theme.CARD_BG)
          }
        }, (pkg: string) => pkg)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
