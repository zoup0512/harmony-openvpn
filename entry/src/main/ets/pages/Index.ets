/**
 * Main page — replicates MainActivity: toolbar + ViewPager with the tabs
 * Profiles / Graph / Settings / FAQ / About.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { GP } from '../common/GP';
import { VpnProfile } from '../core/VpnProfile';
import { ProfileManager } from '../core/ProfileManager';
import { FileUtil } from '../common/FileUtil';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { ImportASDialog } from '../components/dialogs/ImportASDialog';
import { ProfilesTab } from '../components/tabs/ProfilesTab';
import { GraphTab } from '../components/tabs/GraphTab';
import { SettingsTab } from '../components/tabs/SettingsTab';
import { FaqTab } from '../components/tabs/FaqTab';
import { AboutTab } from '../components/tabs/AboutTab';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State sortTick: number = 0;
  private addModel: InputDialogModel = new InputDialogModel();
  private addDialogController: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.addModel }),
    autoCancel: true,
    customStyle: true
  });
  private asDialogController: CustomDialogController = new CustomDialogController({
    builder: ImportASDialog({}),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      R.init(ctx);
    }
  }

  private changeSorting(): void {
    let byLru = !GP.getBool('sortProfilesByLRU', false);
    GP.setBool('sortProfilesByLRU', byLru);
    promptAction.showToast({
      message: byLru ? R.s('sorted_lru') : R.s('sorted_az')
    });
    this.sortTick++;
  }

  private openAddProfileDialog(): void {
    this.addModel.title = R.s('menu_add_profile');
    this.addModel.message = R.s('add_profile_name_prompt');
    this.addModel.placeholder = R.s('name_of_the_vpn_profile');
    this.addModel.initial = '';
    this.addModel.okText = R.s('ok');
    this.addModel.cancelText = R.s('cancel');
    this.addModel.neutralText = R.s('menu_import_short');
    this.addModel.onOk = (text: string) => {
      this.addProfileNamed(text);
    };
    this.addModel.onNeutral = () => {
      this.importConfigFile();
    };
    this.addDialogController.open();
  }

  private addProfileNamed(name: string): void {
    if (name === undefined || name === '') {
      promptAction.showToast({ message: R.s('duplicate_profile_name') });
      return;
    }
    if (ProfileManager.getProfileByName(name) !== undefined && ProfileManager.getProfileByName(name) !== null) {
      promptAction.showToast({ message: R.s('duplicate_profile_name') });
      return;
    }
    let profile = new VpnProfile(name);
    ProfileManager.addProfile(profile);
    profile.addChangeLogEntry('empty profile added via main profile list');
    ProfileManager.saveProfile(profile);
    this.editVPN(profile.getUUID());
  }

  private importConfigFile(): void {
    FileUtil.pickAndRead(['.ovpn', '.conf']).then((f) => {
      let params: Record<string, Object> = {
        'text': f.content,
        'fileName': f.name
      };
      let opt: router.RouterOptions = {
        url: 'pages/ConfigConverter',
        params: params
      };
      router.pushUrl(opt);
    }).catch(() => {
    });
  }

  private editVPN(uuid: string): void {
    let params: Record<string, Object> = { 'uuid': uuid };
    let opt: router.RouterOptions = {
      url: 'pages/VPNPreferences',
      params: params
    };
    router.pushUrl(opt);
  }

  private tabTitle(i: number): string {
    switch (i) {
      case 0:
        return R.s('vpn_list_title');
      case 1:
        return R.s('graph');
      case 2:
        return R.s('generalsettings');
      case 3:
        return R.s('faq');
      case 4:
        return R.s('about');
      default:
        return '';
    }
  }

  build() {
    Column() {
      // ---- Toolbar (replicates ActionBar + fragment menus) ----
      Row() {
        Text(R.s('app_name'))
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .layoutWeight(1)
          .padding({ left: 16 })

        if (this.currentIndex === 0) {
          Image($r('app.media.ic_add'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 12 })
            .onClick(() => {
              this.openAddProfileDialog();
            })
          Image($r('app.media.ic_import'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.importConfigFile();
            })
          Image($r('app.media.ic_sort'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.changeSorting();
            })
          Image($r('app.media.ic_download'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.asDialogController.open();
            })
        }

        Image($r('app.media.ic_receipt'))
          .width(24).height(24).fillColor(Color.White)
          .margin({ left: 16, right: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/LogWindow' });
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Tab bar ----
      Row() {
        ForEach([0, 1, 2, 3, 4], (i: number) => {
          Column() {
            Text(this.tabTitle(i))
              .fontSize(14)
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
      .width('100%')
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Bottom)

      // ---- Content ----
      Tabs({ index: this.currentIndex, barPosition: BarPosition.Start }) {
        TabContent() {
          ProfilesTab({ sortTick: this.sortTick })
        }
        .tabBar('')

        TabContent() {
          GraphTab()
        }
        .tabBar('')

        TabContent() {
          SettingsTab()
        }
        .tabBar('')

        TabContent() {
          FaqTab()
        }
        .tabBar('')

        TabContent() {
          AboutTab()
        }
        .tabBar('')
      }
      .scrollable(true)
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
