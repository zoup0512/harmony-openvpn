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
import { ConfirmDialog, ConfirmDialogModel } from '../components/ConfirmDialog';
import { ProfileShortcut } from '../common/ProfileShortcut';

const PREFS_BACKGROUND: string = Theme.DARK_BACKGROUND;
const PREFS_TOOLBAR: string = Theme.DARK_TOOLBAR;
const PREFS_TABBAR: string = Theme.DARK_SURFACE;
const PREFS_TAB_PRESSED: string = Theme.DARK_SURFACE_ALT;
const PREFS_TEXT: string = Theme.DARK_TEXT_PRIMARY;
const PREFS_MUTED: string = Theme.DARK_TEXT_SECONDARY;
const PREFS_ACCENT: string = Theme.DARK_ACCENT;

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
  private skipNextSave: boolean = false;
  private deleteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });
  private barScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    let params = router.getParams() as RouteParams;
    if (params === undefined || params === null || params.uuid === undefined) {
      promptAction.showToast({ message: R.s('profile_not_found') });
      return;
    }
    let p = ProfileManager.get(params.uuid);
    if (p === undefined || p === null) {
      promptAction.showToast({ message: R.s('profile_not_found') });
      return;
    }
    this.profile = p;
    this.loaded = true;
    if (params.tab !== undefined && params.tab >= 0 && params.tab < 8) {
      this.currentIndex = params.tab;
    }
  }

  aboutToDisappear(): void {
    if (!this.skipNextSave) {
      this.save();
    }
  }

  onBackPress(): boolean {
    router.back();
    return true;
  }

  private save(): boolean {
    if (!this.loaded || this.skipSave) {
      return false;
    }
    try {
      ProfileManager.saveProfile(this.profile);
      return true;
    } catch (e) {
      promptAction.showToast({ message: R.s('profile_save_failed') });
      return false;
    }
  }

  private saveAndBack(): void {
    if (this.save()) {
      this.skipNextSave = true;
      promptAction.showToast({ message: R.s('profile_saved') });
      router.back();
    }
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
    this.deleteDialogModel.title = R.s('remove_vpn_confirm_title');
    this.deleteDialogModel.message = R.s('remove_vpn_query', this.profile.getName());
    this.deleteDialogModel.cancelText = R.s('no');
    this.deleteDialogModel.confirmText = R.s('yes');
    this.deleteDialogModel.showCancel = true;
    this.deleteDialogModel.dangerous = true;
    this.deleteDialogModel.onConfirm = () => {
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
    };
    this.deleteDialogController.open();
  }

  private duplicateVpn(): void {
    let copy = this.profile.copy(`${R.s('copy_of_profile', this.profile.getName())}`);
    copy.addChangeLogEntry('Profile duplicated by user');
    ProfileManager.addProfile(copy);
    promptAction.showToast({ message: R.s('duplicate_vpn', copy.getName()) });
    router.back();
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(44)
          .height(44)
          .padding(10)
          .fillColor(PREFS_TEXT)
          .margin({ left: 4 })
          .onClick(() => {
            this.onBackPress();
          })
        Text(R.s('edit_profile_title', this.profile.getName()))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(PREFS_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .padding({ left: 4, right: 4 })
        Image($r('app.media.ic_copy'))
          .width(44)
          .height(44)
          .padding(11)
          .fillColor(PREFS_TEXT)
          .opacity(this.loaded ? 1 : 0.4)
          .enabled(this.loaded)
          .onClick(() => {
            this.duplicateVpn();
          })
        Image($r('app.media.ic_delete'))
          .width(44)
          .height(44)
          .padding(11)
          .fillColor(PREFS_TEXT)
          .opacity(this.loaded ? 1 : 0.4)
          .enabled(this.loaded)
          .onClick(() => {
            this.askProfileRemoval();
          })
        Text(R.s('save'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.loaded ? PREFS_ACCENT : PREFS_MUTED)
          .textAlign(TextAlign.Center)
          .width(64)
          .padding({ top: 14, bottom: 14 })
          .enabled(this.loaded)
          .onClick(() => {
            this.saveAndBack();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(PREFS_TOOLBAR)
      .alignItems(VerticalAlign.Center)

      Scroll(this.barScroller) {
        Row() {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
            Column() {
              Text(this.tabTitle(i))
                .fontSize(13)
                .fontWeight(this.currentIndex === i ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.currentIndex === i ? PREFS_TEXT : PREFS_MUTED)
                .maxLines(1)
                .padding({ left: 16, right: 16, top: 14, bottom: 11 })
              Divider()
                .color(this.currentIndex === i ? PREFS_ACCENT : Theme.TRANSPARENT)
                .strokeWidth(3)
            }
            .height(48)
            .backgroundColor(this.currentIndex === i ? PREFS_TAB_PRESSED : Theme.TRANSPARENT)
            .onClick(() => {
              this.currentIndex = i;
            })
          }, (i: number) => `${i}`)
        }
        .height(48)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(48)
      .backgroundColor(PREFS_TABBAR)

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
      .backgroundColor(PREFS_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PREFS_BACKGROUND)
  }
}

