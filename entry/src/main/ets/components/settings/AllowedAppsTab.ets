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
    builder: InputDialog({ model: this.addModel, darkMode: true }),
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
      Column() {
        // default allow switch bar
        Row() {
          Text(this.disallowedMode ? R.s('vpn_disallow_radio') : R.s('vpn_allow_radio'))
            .fontSize(15)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.disallowedMode })
            .selectedColor(Theme.DARK_ACCENT)
            .onChange((v: boolean) => {
              this.disallowedMode = v;
              this.profile.mAllowedAppsVpnAreDisallowed = v;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })

        Divider()
          .color(Theme.DARK_BORDER)
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        // bypass bar
        Row() {
          Text(R.s('vpn_allow_bypass'))
            .fontSize(15)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.allowBypass })
            .selectedColor(Theme.DARK_ACCENT)
            .onChange((v: boolean) => {
              this.allowBypass = v;
              this.profile.mAllowAppVpnBypass = v;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      }
      .width('100%')
      .backgroundColor(Theme.DARK_SURFACE)
      .border({ width: 1, color: Theme.DARK_BORDER })
      .borderRadius(Theme.DARK_CARD_RADIUS)
      .margin({ top: 12 })

      Text(R.s('allowed_apps_manual_hint'))
        .fontSize(12)
        .fontColor(Theme.DARK_TEXT_SECONDARY)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      List() {
        ForEach(this.apps, (pkg: string) => {
          ListItem() {
            Row() {
              Text(pkg)
                .fontSize(14)
                .fontColor(Theme.DARK_TEXT_PRIMARY)
                .fontFamily('monospace')
                .layoutWeight(1)
              Checkbox()
                .select(true)
                .selectedColor(Theme.DARK_ACCENT)
                .onChange((v: boolean) => {
                  this.toggleApp(pkg);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor(Theme.DARK_SURFACE_ALT)
            .border({ width: 1, color: Theme.DARK_BORDER })
            .borderRadius(Theme.DARK_ROW_RADIUS)
            .margin({ bottom: 8 })
          }
        }, (pkg: string) => pkg)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: 4 })
      .backgroundColor(Theme.DARK_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor(Theme.DARK_BACKGROUND)
  }
}
