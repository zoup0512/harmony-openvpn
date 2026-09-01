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
import { ConfirmDialog, ConfirmDialogModel } from '../components/ConfirmDialog';
import { ProfileShortcut } from '../common/ProfileShortcut';

interface RouteParams {
  uuid: string;
}

const EDIT_BACKGROUND: string = Theme.DARK_BACKGROUND;
const EDIT_TOOLBAR: string = Theme.DARK_TOOLBAR;
const EDIT_SURFACE: string = Theme.DARK_SURFACE;
const EDIT_SURFACE_ALT: string = Theme.DARK_SURFACE_ALT;
const EDIT_BORDER: string = Theme.DARK_BORDER;
const EDIT_TEXT: string = Theme.DARK_TEXT_PRIMARY;
const EDIT_MUTED: string = Theme.DARK_TEXT_SECONDARY;
const EDIT_DISABLED: string = Theme.DARK_TEXT_DISABLED;
const EDIT_SHORTCUT: string = Theme.DARK_ACCENT;
const EDIT_ACTION: string = Theme.DARK_ACTION;
const EDIT_DANGER: string = Theme.DARK_DANGER;
const EDIT_DANGER_BACKGROUND: string = Theme.DARK_DANGER_SURFACE;

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
    builder: InputDialog({ model: this.passwordDialogModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });
  private deleteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: true }),
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
    this.deleteDialogModel.title = R.s('remove_vpn_confirm_title');
    this.deleteDialogModel.message = R.s('remove_vpn_query', this.profile.getName());
    this.deleteDialogModel.cancelText = R.s('no');
    this.deleteDialogModel.confirmText = R.s('yes');
    this.deleteDialogModel.showCancel = true;
    this.deleteDialogModel.dangerous = true;
    this.deleteDialogModel.onConfirm = () => {
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

  @Builder
  SectionHeader(title: string, description: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(EDIT_TEXT)
        .width('100%')
      Text(description)
        .fontSize(13)
        .fontColor(EDIT_MUTED)
        .lineHeight(20)
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 24, bottom: 10 })
  }

  @Builder
  ConnectionCard() {
    Column() {
      Text(R.s('profilename'))
        .fontSize(12)
        .fontColor(EDIT_MUTED)
        .width('100%')
      TextInput({ text: this.profileName })
        .fontSize(17)
        .fontColor(EDIT_TEXT)
        .backgroundColor(Theme.TRANSPARENT)
        .padding({ left: 0, right: 0, top: 6, bottom: 8 })
        .width('100%')
        .onChange((value: string) => {
          this.profileName = value;
        })
      Divider()
        .color(EDIT_BORDER)
        .strokeWidth(1)

      Row() {
        Text(R.s('server_hostname_locked'))
          .fontSize(12)
          .fontColor(EDIT_MUTED)
          .layoutWeight(1)
        Text(R.s('profile_edit_locked_badge'))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(EDIT_DISABLED)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(EDIT_SURFACE_ALT)
          .borderRadius(10)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 18 })
      Text(this.hostname)
        .fontSize(17)
        .fontColor(EDIT_TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 7 })
      Text(R.s('profile_edit_locked_hint'))
        .fontSize(12)
        .fontColor(EDIT_DISABLED)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 4, bottom: 12 })
      Divider()
        .color(EDIT_BORDER)
        .strokeWidth(1)

      Text(R.s('server_override_optional'))
        .fontSize(12)
        .fontColor(EDIT_MUTED)
        .width('100%')
        .margin({ top: 18 })
      TextInput({ text: this.serverOverride, placeholder: R.s('profile_edit_override_placeholder') })
        .fontSize(17)
        .fontColor(EDIT_TEXT)
        .placeholderColor(EDIT_DISABLED)
        .backgroundColor(Theme.TRANSPARENT)
        .padding({ left: 0, right: 0, top: 6, bottom: 8 })
        .width('100%')
        .onChange((value: string) => {
          this.serverOverride = value;
        })
      Divider()
        .color(EDIT_BORDER)
        .strokeWidth(1)
      Text(R.s('profile_edit_override_hint'))
        .fontSize(12)
        .fontColor(EDIT_DISABLED)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  CredentialsCard() {
    Column() {
      Text(R.s('auth_username'))
        .fontSize(12)
        .fontColor(EDIT_MUTED)
        .width('100%')
      TextInput({ text: this.username })
        .fontSize(17)
        .fontColor(EDIT_TEXT)
        .backgroundColor(Theme.TRANSPARENT)
        .padding({ left: 0, right: 0, top: 6, bottom: 8 })
        .width('100%')
        .onChange((value: string) => {
          this.username = value;
        })
      Divider()
        .color(EDIT_BORDER)
        .strokeWidth(1)

      Row() {
        Checkbox()
          .width(24)
          .height(24)
          .select(this.savePassword)
          .selectedColor(EDIT_SHORTCUT)
          .onChange((selected: boolean) => {
            if (selected && this.passwordDraft === '') {
              this.requestPassword();
            } else {
              this.savePassword = selected;
            }
          })
        Column() {
          Text(R.s('save_password'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(EDIT_TEXT)
            .width('100%')
          Text(this.savePassword ? R.s('profile_edit_password_saved') : R.s('profile_edit_password_not_saved'))
            .fontSize(12)
            .fontColor(this.savePassword ? EDIT_SHORTCUT : EDIT_MUTED)
            .lineHeight(18)
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 16, bottom: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  ProfileIdCard() {
    Column() {
      Text(R.s('profile_id'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(EDIT_TEXT)
        .width('100%')
      Text(R.s('profile_id_description'))
        .fontSize(12)
        .fontColor(EDIT_MUTED)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 4 })
      Row() {
        Text(this.profileId)
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor(EDIT_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Image($r('app.media.ic_copy'))
          .width(36)
          .height(36)
          .fillColor(EDIT_TEXT)
          .padding(8)
          .backgroundColor(EDIT_SURFACE_ALT)
          .borderRadius(10)
          .margin({ left: 10 })
          .onClick(() => {
            this.copyProfileId();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  AdvancedEntry() {
    Row() {
      Column() {
        Text(R.s('advanced_settings'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(EDIT_TEXT)
          .width('100%')
        Text(R.s('profile_edit_advanced_description'))
          .fontSize(12)
          .fontColor(EDIT_MUTED)
          .lineHeight(18)
          .maxLines(2)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(28)
        .fontColor(EDIT_SHORTCUT)
        .margin({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .margin({ top: 10 })
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
    .onClick(() => {
      this.openAdvanced();
    })
  }

  @Builder
  QuickActionsCard() {
    Column() {
      Text(R.s('profile_edit_shortcut_description'))
        .fontSize(13)
        .fontColor(EDIT_MUTED)
        .lineHeight(20)
        .width('100%')
      Button(R.s('set_connect_shortcut'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(EDIT_ACTION)
        .height(50)
        .width('100%')
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.setShortcut();
        })

      Divider()
        .color(EDIT_BORDER)
        .strokeWidth(1)
        .margin({ top: 18, bottom: 18 })

      Text(R.s('profile_edit_proxy_description'))
        .fontSize(13)
        .fontColor(EDIT_MUTED)
        .lineHeight(20)
        .width('100%')
      Button(R.s('add_proxy'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(EDIT_ACTION)
        .height(50)
        .width('100%')
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.openAdvanced(1);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  DangerCard() {
    Column() {
      Text(R.s('profile_edit_delete_description'))
        .fontSize(13)
        .fontColor(EDIT_MUTED)
        .lineHeight(20)
        .width('100%')
      Button(R.s('delete_profile'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(EDIT_DANGER)
        .backgroundColor(EDIT_DANGER_BACKGROUND)
        .height(50)
        .width('100%')
        .border({ width: 1, color: EDIT_DANGER })
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.askDelete();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: 16, right: 16 })
          .onClick(() => {
            this.onBackPress();
          })
        Text(R.s('profile_edit'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        Text(R.s('save'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EDIT_SHORTCUT)
          .textAlign(TextAlign.Center)
          .width(72)
          .padding({ top: 12, bottom: 12 })
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
          this.SectionHeader(R.s('profile_edit_connection_section'), R.s('profile_edit_connection_hint'))
          this.ConnectionCard()

          this.SectionHeader(R.s('profile_edit_credentials_section'), R.s('profile_edit_credentials_hint'))
          this.CredentialsCard()

          this.SectionHeader(R.s('profile_edit_details_section'), R.s('profile_edit_details_hint'))
          this.ProfileIdCard()
          this.AdvancedEntry()

          this.SectionHeader(R.s('profile_edit_actions_section'), R.s('profile_edit_actions_hint'))
          this.QuickActionsCard()

          this.SectionHeader(R.s('profile_edit_management_section'), R.s('profile_edit_management_hint'))
          this.DangerCard()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32 })
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
