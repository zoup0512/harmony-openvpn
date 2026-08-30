/**
 * VPN profile editor — port of VPNPreferences: "Editing %s" title, tab bar
 * with the eight settings tabs, remove/duplicate menu, save on exit.
 */

import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { App } from '../common/App';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { VpnProfile } from '../core/VpnProfile';
import { ProfileManager } from '../core/ProfileManager';
import { BasicTab } from '../components/settings/BasicTab';
import { ConnectionsTab } from '../components/settings/ConnectionsTab';
import { IPTab } from '../components/settings/IPTab';
import { RoutingTab } from '../components/settings/RoutingTab';
import { AuthTab } from '../components/settings/AuthTab';
import { ObscureTab } from '../components/settings/ObscureTab';
import { AllowedAppsTab } from '../components/settings/AllowedAppsTab';
import { ShowConfigTab } from '../components/settings/ShowConfigTab';
import { ProfileShortcut } from '../common/ProfileShortcut';

interface RouteParams {
  uuid: string;
  tab?: number;
}

@Entry
@Component
struct VPNPreferences {
  @State currentIndex: number = 0;
  profile: VpnProfile = new VpnProfile('unset');
  private loaded: boolean = false;
  private skipSave: boolean = false;
  private barScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    let params = router.getParams() as RouteParams;
    if (params !== undefined && params !== null && params.uuid !== undefined) {
      let p = ProfileManager.get(params.uuid);
      if (p !== undefined && p !== null) {
        this.profile = p;
        this.loaded = true;
        if (params.tab !== undefined && params.tab >= 0 && params.tab < 8) {
          this.currentIndex = params.tab;
        }
      }
    }
  }

  aboutToDisappear(): void {
    this.save();
  }

  onBackPress(): boolean {
    router.back();
    return true;
  }

  private save(): void {
    if (!this.loaded || this.skipSave) {
      return;
    }
    ProfileManager.saveProfile(this.profile);
  }

  private tabTitle(i: number): string {
    switch (i) {
      case 0:
        return R.s('basic');
      case 1:
        return R.s('server_list');
      case 2:
        return R.s('ipdns');
      case 3:
        return R.s('routing');
      case 4:
        return R.s('settings_auth');
      case 5:
        return R.s('advanced');
      case 6:
        return R.s('vpn_allowed_apps');
      case 7:
        return R.s('generated_config');
      default:
        return '';
    }
  }

  private askProfileRemoval(): void {
    let dialogParams: AlertDialogParamWithButtons = {
      title: R.s('remove_vpn_confirm_title'),
      message: R.s('remove_vpn_query', this.profile.getName()),
      primaryButton: {
        value: R.s('no'),
        fontColor: Theme.PRIMARY,
        action: () => {
        }
      },
        secondaryButton: {
        value: R.s('yes'),
        fontColor: Theme.WARNING_RED,
        action: () => {
          this.skipSave = true;
          let alwaysOn = ProfileManager.getAlwaysOnVPN();
          if (alwaysOn !== undefined && alwaysOn.getUUID() === this.profile.getUUID()) {
            ProfileManager.setAlwaysOnVPN(undefined);
          }
          let context = App.context as common.UIAbilityContext;
          ProfileShortcut.remove(context, this.profile).catch(() => {
          });
          ProfileManager.removeProfile(context, this.profile);
          router.back();
        }
      }
    };
    AlertDialog.show(dialogParams);
  }

  private duplicateVpn(): void {
    let copy = this.profile.copy(`${R.s('copy_of_profile', this.profile.getName())}`);
    ProfileManager.addProfile(copy);
    copy.addChangeLogEntry('Profile duplicated by user');
    promptAction.showToast({ message: R.s('duplicate_vpn', copy.getName()) });
    router.back();
  }

  build() {
    Column() {
      // ---- Toolbar ----
      Row() {
        Image($r('app.media.ic_back'))
          .width(24).height(24).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            this.onBackPress();
          })
        Text(R.s('edit_profile_title', this.profile.getName()))
          .fontSize(18)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .padding({ left: 12 })
        Image($r('app.media.ic_copy'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            this.duplicateVpn();
          })
        Image($r('app.media.ic_delete'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 16, right: 12 })
          .onClick(() => {
            this.askProfileRemoval();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Scrollable tab bar ----
      Scroll(this.barScroller) {
        Row() {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
            Column() {
              Text(this.tabTitle(i))
                .fontSize(13)
                .fontColor(Color.White)
                .maxLines(1)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              Divider()
                .color(this.currentIndex === i ? Theme.ACCENT : '#00000000')
                .strokeWidth(4)
            }
            .onClick(() => {
              this.currentIndex = i;
            })
          }, (i: number) => `${i}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .backgroundColor(Theme.PRIMARY)

      // ---- Content ----
      Tabs({ index: this.currentIndex, barPosition: BarPosition.Start }) {
        TabContent() {
          BasicTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          ConnectionsTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          IPTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          RoutingTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          AuthTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          ObscureTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          AllowedAppsTab({ profile: this.profile })
        }
        .tabBar('')
        TabContent() {
          ShowConfigTab({ profile: this.profile })
        }
        .tabBar('')
      }
      .scrollable(false)
      .barHeight(0)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}

