/**
 * Main page — replicates MainActivity: toolbar + ViewPager with the tabs
 * Profiles / Graph / Settings / FAQ / About.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { GP } from '../common/GP';
import { FileUtil } from '../common/FileUtil';
import { ImportASDialog } from '../components/dialogs/ImportASDialog';
import { ProfilesTab } from '../components/tabs/ProfilesTab';
import { GraphTab } from '../components/tabs/GraphTab';
import { SettingsTab } from '../components/tabs/SettingsTab';
import { FaqTab } from '../components/tabs/FaqTab';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { VpnController, PendingAuthChallenge } from '../vpn/VpnController';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State sortTick: number = 0;
  private authTimerId: number = -1;
  private activeAuthExpiresAt: number = 0;
  private authModel: InputDialogModel = new InputDialogModel();
  private authDialogController: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.authModel }),
    autoCancel: false,
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
    this.authTimerId = setInterval(() => {
      this.checkPendingAuth();
    }, 500) as number;
  }

  aboutToDisappear(): void {
    if (this.authTimerId !== -1) {
      clearInterval(this.authTimerId);
      this.authTimerId = -1;
    }
  }

  private checkPendingAuth(): void {
    let challenge = VpnController.readPendingAuthChallenge();
    if (challenge === undefined || challenge.expiresAt <= Date.now()) {
      return;
    }
    if (this.activeAuthExpiresAt === challenge.expiresAt) {
      return;
    }
    let pending = new PendingAuthChallenge();
    pending.uuid = challenge.uuid;
    pending.kind = challenge.kind;
    pending.challenge = challenge.challenge;
    pending.echo = challenge.echo;
    pending.responseRequired = challenge.responseRequired;
    pending.cookie = challenge.cookie;
    pending.expiresAt = challenge.expiresAt;
    this.activeAuthExpiresAt = pending.expiresAt;
    this.authModel.title = R.s('otp_title');
    this.authModel.message = pending.challenge === '' ? R.s('otp_message') : pending.challenge;
    this.authModel.placeholder = R.s('otp_placeholder');
    this.authModel.initial = '';
    this.authModel.isPassword = !pending.echo;
    this.authModel.okText = R.s('submit');
    this.authModel.cancelText = R.s('cancel');
    this.authModel.neutralText = '';
    this.authModel.onOk = (value: string) => {
      this.submitPendingAuth(pending, value);
    };
    this.authModel.onCancel = () => {
      VpnController.clearPendingAuthChallenge();
      this.activeAuthExpiresAt = 0;
      VpnController.stopVpn().catch(() => {
      });
    };
    this.authDialogController.open();
  }

  private submitPendingAuth(challenge: PendingAuthChallenge, value: string): void {
    let response = value.trim();
    if (response === '') {
      promptAction.showToast({ message: R.s('otp_required') });
      return;
    }
    VpnController.clearPendingAuthChallenge();
    this.activeAuthExpiresAt = 0;
    if (challenge.kind === 'cr_text') {
      promptAction.showToast({ message: R.s('otp_retrying') });
      // CR_TEXT is handled by the live native client when the extension remains active.
      // If the extension has already ended, the normal retry path is used instead.
      VpnController.startVpn(challenge.uuid, 'otp-cr-text', response, '', 'cr_text').catch(() => {
      });
      return;
    }
    promptAction.showToast({ message: R.s('otp_retrying') });
    VpnController.startVpn(challenge.uuid, 'otp', response, challenge.cookie, challenge.kind).catch(() => {
    });
  }

  private changeSorting(): void {
    let byLru = !GP.getBool('sortProfilesByLRU', false);
    GP.setBool('sortProfilesByLRU', byLru);
    promptAction.showToast({
      message: byLru ? R.s('sorted_lru') : R.s('sorted_az')
    });
    this.sortTick++;
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
          .margin({ left: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/LogWindow' });
          })

        Image($r('app.media.ic_info'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: 16, right: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' });
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Tab bar ----
      Row() {
        ForEach([0, 1, 2, 3], (i: number) => {
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
