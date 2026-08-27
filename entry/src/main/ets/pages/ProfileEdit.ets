/**
 * Profile summary editor matching the OpenVPN Connect profile edit screen.
 */

import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { App } from '../common/App';
import { R } from '../common/Res';
import { Theme } from '../common/Theme';
import { VpnProfile } from '../core/VpnProfile';
import { ProfileManager } from '../core/ProfileManager';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { ProfileShortcut } from '../common/ProfileShortcut';

interface RouteParams {
  uuid: string;
}

const EDIT_BACKGROUND: string = '#1D2425';
const EDIT_TOOLBAR: string = '#2F3738';
const EDIT_TEXT: string = '#EAEAEA';
const EDIT_MUTED: string = '#B9BBBB';
const EDIT_SHORTCUT: string = '#85AF00';
const EDIT_PROXY: string = '#ED7F22';
const EDIT_DELETE: string = '#999898';

@Entry
@Component
struct ProfileEdit {
  @State profileName: string = '';
  @State serverOverride: string = '';
  @State username: string = '';
  @State savePassword: boolean = false;
  @State passwordDraft: string = '';
  @State profileId: string = '';
  @State hostname: string = '';
  private profile: VpnProfile = new VpnProfile('unset');
  private loaded: boolean = false;
  private passwordDialogModel: InputDialogModel = new InputDialogModel();
  private passwordDialogController: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.passwordDialogModel }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let params = router.getParams() as RouteParams;
    if (params === undefined || params === null || params.uuid === undefined) {
      return;
    }
    let profile = ProfileManager.get(params.uuid);
    if (profile === undefined || profile === null) {
      promptAction.showToast({ message: R.s('profile_not_found') });
      return;
    }
    this.profile = profile;
    this.loaded = true;
    this.loadDraft();
  }

  onBackPress(): boolean {
    router.back();
    return true;
  }

  private loadDraft(): void {
    this.profileName = this.profile.mName;
    this.serverOverride = this.profile.mServerOverride;
    this.username = this.profile.mUsername === undefined ? '' : this.profile.mUsername;
    this.passwordDraft = this.profile.mPassword === undefined ? '' : this.profile.mPassword;
    this.savePassword = this.passwordDraft !== '';
    this.profileId = this.profile.getUUID();
    this.hostname = this.findHostname();
  }

  private findHostname(): string {
    let fallback = '';
    for (let connection of this.profile.mConnections) {
      let name = connection.mServerName.trim();
      if (name === '') {
        continue;
      }
      if (fallback === '') {
        fallback = name;
      }
      if (connection.mEnabled) {
        return name;
      }
    }
    if (fallback !== '') {
      return fallback;
    }
    if (this.profile.mServerName.trim() !== '') {
      return this.profile.mServerName.trim();
    }
    return R.s('no_data');
  }

  private persistDraft(): boolean {
    if (!this.loaded) {
      return false;
    }
    let name = this.profileName.trim();
    if (name === '') {
      promptAction.showToast({ message: R.s('profile_name_required') });
      return false;
    }
    let duplicate = ProfileManager.getProfileByName(name);
    if (duplicate !== undefined && duplicate !== null && duplicate.getUUID() !== this.profile.getUUID()) {
      promptAction.showToast({ message: R.s('duplicate_profile_name') });
      return false;
    }
    this.profile.mName = name;
    this.profile.mServerOverride = this.serverOverride.trim();
    this.profile.mUsername = this.username === '' ? undefined : this.username;
    this.profile.mPassword = this.savePassword && this.passwordDraft !== '' ? this.passwordDraft : undefined;
    try {
      ProfileManager.saveProfile(this.profile);
      return true;
    } catch (e) {
      promptAction.showToast({ message: R.s('profile_save_failed') });
      return false;
    }
  }

  private saveAndBack(): void {
    if (this.persistDraft()) {
      promptAction.showToast({ message: R.s('profile_saved') });
      router.back();
    }
  }

  private openAdvanced(tab: number = 0): void {
    if (!this.persistDraft()) {
      return;
    }
    let params: Record<string, Object> = {
      'uuid': this.profile.getUUID(),
      'tab': tab
    };
    router.pushUrl({ url: 'pages/VPNPreferences', params: params });
  }

  private copyProfileId(): void {
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.profileId);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: R.s('profile_id_copied') });
    }).catch(() => {
      promptAction.showToast({ message: R.s('profile_copy_failed') });
    });
  }

  private askDelete(): void {
    let dialogParams: AlertDialogParamWithButtons = {
      title: R.s('remove_vpn_confirm_title'),
      message: R.s('remove_vpn_query', this.profile.getName()),
      primaryButton: {
        value: R.s('no'),
        action: () => {
        }
      },
      secondaryButton: {
        value: R.s('yes'),
        fontColor: Theme.WARNING_RED,
        action: () => {
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

  private requestPassword(): void {
    this.savePassword = false;
    this.passwordDialogModel.title = R.s('save_password_title');
    this.passwordDialogModel.message = R.s('save_password_message');
    this.passwordDialogModel.placeholder = R.s('password_placeholder');
    this.passwordDialogModel.initial = this.passwordDraft;
    this.passwordDialogModel.isPassword = true;
    this.passwordDialogModel.okText = R.s('ok');
    this.passwordDialogModel.cancelText = R.s('cancel');
    this.passwordDialogModel.neutralText = '';
    this.passwordDialogModel.onOk = (value: string) => {
      if (value === '') {
        this.passwordDraft = '';
        this.savePassword = false;
        return;
      }
      this.passwordDraft = value;
      this.savePassword = true;
    };
    this.passwordDialogController.open();
  }

  private setShortcut(): void {
    if (!this.persistDraft()) {
      return;
    }
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ProfileShortcut.create(context, this.profile).then(() => {
      promptAction.showToast({ message: R.s('shortcut_created') });
    }).catch(() => {
      promptAction.showToast({ message: R.s('shortcut_failed') });
    });
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: 12, right: 12 })
          .onClick(() => {
            this.onBackPress();
          })
        Text(R.s('profile_edit'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        Text(R.s('save'))
          .fontSize(16)
          .fontColor(Color.White)
          .margin({ left: 12, right: 16 })
          .onClick(() => {
            this.saveAndBack();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(EDIT_TOOLBAR)
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text(R.s('profilename'))
            .fontSize(12)
            .fontColor(EDIT_TEXT)
            .width('100%')
            .margin({ top: 22 })
          TextInput({ text: this.profileName })
            .fontSize(16)
            .fontColor(EDIT_TEXT)
            .backgroundColor('#00000000')
            .padding({ left: 0, right: 0, top: 4, bottom: 8 })
            .width('100%')
            .onChange((value: string) => {
              this.profileName = value;
            })
          Divider()
            .color(EDIT_MUTED)
            .strokeWidth(1)

          Text(R.s('server_hostname_locked'))
            .fontSize(12)
            .fontColor(EDIT_MUTED)
            .width('100%')
            .margin({ top: 30 })
          Text(this.hostname)
            .fontSize(16)
            .fontColor(EDIT_TEXT)
            .width('100%')
            .margin({ top: 4, bottom: 8 })
          Divider()
            .color(EDIT_MUTED)
            .strokeWidth(1)

          if (this.serverOverride !== '') {
            Text(R.s('server_override_optional'))
              .fontSize(12)
              .fontColor(EDIT_TEXT)
              .width('100%')
              .margin({ top: 30 })
          }
          TextInput({ text: this.serverOverride, placeholder: R.s('server_override_optional') })
            .fontSize(16)
            .fontColor(EDIT_TEXT)
            .placeholderColor(EDIT_TEXT)
            .backgroundColor('#00000000')
            .padding({ left: 0, right: 0, top: this.serverOverride === '' ? 38 : 4, bottom: 8 })
            .width('100%')
            .onChange((value: string) => {
              this.serverOverride = value;
            })
          Divider()
            .color(Color.White)
            .strokeWidth(1)

          Text(R.s('auth_username'))
            .fontSize(12)
            .fontColor(EDIT_TEXT)
            .width('100%')
            .margin({ top: 30 })
          TextInput({ text: this.username })
            .fontSize(16)
            .fontColor(EDIT_TEXT)
            .backgroundColor('#00000000')
            .padding({ left: 0, right: 0, top: 4, bottom: 8 })
            .width('100%')
            .onChange((value: string) => {
              this.username = value;
            })
          Divider()
            .color(EDIT_MUTED)
            .strokeWidth(1)

          Row() {
            Checkbox()
              .select(this.savePassword)
              .selectedColor(EDIT_SHORTCUT)
              .onChange((selected: boolean) => {
                if (selected && this.passwordDraft === '') {
                  this.requestPassword();
                } else {
                  this.savePassword = selected;
                }
              })
            Text(R.s('save_password'))
              .fontSize(16)
              .fontColor(EDIT_TEXT)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 20, bottom: 18 })

          Row() {
            Text(R.s('profile_id'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Blank()
            Text(R.s('advanced_settings'))
              .fontSize(13)
              .fontColor(EDIT_SHORTCUT)
              .onClick(() => {
                this.openAdvanced();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 2 })

          Text(R.s('profile_id_description'))
            .fontSize(13)
            .fontColor(EDIT_TEXT)
            .width('100%')
            .margin({ top: 10 })
          Row() {
            Text(this.profileId)
              .fontSize(15)
              .fontColor(EDIT_TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Image($r('app.media.ic_copy'))
              .width(28)
              .height(28)
              .fillColor(Color.White)
              .padding(4)
              .onClick(() => {
                this.copyProfileId();
              })
          }
          .width('100%')
          .margin({ top: 6 })

          Button(R.s('set_connect_shortcut'))
            .fontSize(14)
            .fontColor(EDIT_SHORTCUT)
            .backgroundColor(Color.White)
            .height(42)
            .width('100%')
            .borderRadius(6)
            .margin({ top: 28 })
            .onClick(() => {
              this.setShortcut();
            })

          Blank()
            .height(54)

          Row() {
            Button(R.s('delete_profile'))
              .fontSize(13)
              .fontColor(EDIT_DELETE)
              .backgroundColor(Color.White)
              .height(42)
              .layoutWeight(1)
              .borderRadius(6)
              .onClick(() => {
                this.askDelete();
              })
            Button(R.s('add_proxy'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor(EDIT_PROXY)
              .height(42)
              .layoutWeight(1)
              .borderRadius(6)
              .margin({ left: 18 })
              .onClick(() => {
                this.openAdvanced(1);
              })
          }
          .width('100%')
          .margin({ top: 16, bottom: 18 })
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
        .backgroundColor(EDIT_BACKGROUND)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(EDIT_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EDIT_BACKGROUND)
  }
}
