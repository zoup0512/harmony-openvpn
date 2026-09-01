/**
 * Routing tab — port of Settings_Routing + vpn_routing.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { PrefCategory, CheckRow, TapRow } from '../PrefRows';
import { InputDialog, InputDialogModel } from '../InputDialog';

const TAB_BACKGROUND: string = Theme.DARK_BACKGROUND;
const TAB_SURFACE: string = Theme.DARK_SURFACE;
const TAB_BORDER: string = Theme.DARK_BORDER;

@Component
export struct RoutingTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State routenopull: boolean = false;
  @State unblockLocal: boolean = false;
  @State blockUnusedAF: boolean = true;
  @State useDefaultRoute: boolean = true;
  @State customRoutes: string = '';
  @State excludedRoutes: string = '';
  @State useDefaultRoutev6: boolean = true;
  @State customRoutesv6: string = '';
  private editModel: InputDialogModel = new InputDialogModel();
  private editDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.editModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let p = this.profile;
    this.routenopull = p.mRoutenopull;
    this.unblockLocal = p.mAllowLocalLAN;
    this.blockUnusedAF = p.mBlockUnusedAddressFamilies;
    this.useDefaultRoute = p.mUseDefaultRoute;
    this.customRoutes = p.mCustomRoutes === undefined ? '' : p.mCustomRoutes;
    this.excludedRoutes = p.mExcludedRoutes === undefined ? '' : p.mExcludedRoutes;
    this.useDefaultRoutev6 = p.mUseDefaultRoutev6;
    this.customRoutesv6 = p.mCustomRoutesv6;
  }

  private promptEdit(titleKey: string, messageKey: string, initial: string, onOk: (v: string) => void): void {
    this.editModel.title = R.s(titleKey);
    this.editModel.message = messageKey === '' ? '' : R.s(messageKey);
    this.editModel.initial = initial;
    this.editModel.multiLine = false;
    this.editModel.okText = R.s('ok');
    this.editModel.cancelText = R.s('cancel');
    this.editModel.neutralText = '';
    this.editModel.onOk = onOk;
    this.editDialog.open();
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          CheckRow({
            title: R.s('ignored_pushed_routes'),
            summary: R.s('ignore_routes_summary'),
            checked: this.routenopull,
            darkMode: true,
            onChange: (v: boolean) => {
              this.routenopull = v;
              this.profile.mRoutenopull = v;
            }
          })
          CheckRow({
            title: R.s('blocklocal_title'),
            summary: R.s('blocklocal_summary'),
            checked: this.unblockLocal,
            darkMode: true,
            onChange: (v: boolean) => {
              this.unblockLocal = v;
              this.profile.mAllowLocalLAN = v;
            }
          })
          CheckRow({
            title: R.s('title_block_address_families'),
            summary: R.s('summary_block_address_families'),
            checked: this.blockUnusedAF,
            showDivider: false,
            darkMode: true,
            onChange: (v: boolean) => {
              this.blockUnusedAF = v;
              this.profile.mBlockUnusedAddressFamilies = v;
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 12 })

        PrefCategory({ title: 'IPv4', darkMode: true })
        Column() {
          CheckRow({
            title: R.s('use_default_title'),
            summary: R.s('default_route_summary'),
            checked: this.useDefaultRoute,
            darkMode: true,
            onChange: (v: boolean) => {
              this.useDefaultRoute = v;
              this.profile.mUseDefaultRoute = v;
            }
          })
          TapRow({
            title: R.s('custom_routes_title'),
            summary: this.customRoutes,
            rowEnabled: !this.useDefaultRoute,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('custom_routes_title', 'custom_route_message', this.customRoutes, (v: string) => {
                this.customRoutes = v;
                this.profile.mCustomRoutes = v === '' ? undefined : v;
              });
            }
          })
          TapRow({
            title: R.s('custom_routes_title_excluded'),
            summary: this.excludedRoutes,
            rowEnabled: !this.useDefaultRoute,
            showDivider: false,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('custom_routes_title_excluded', 'custom_route_message_excluded', this.excludedRoutes,
                (v: string) => {
                  this.excludedRoutes = v;
                  this.profile.mExcludedRoutes = v === '' ? undefined : v;
                });
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 0, bottom: 0 })

        PrefCategory({ title: 'IPv6', darkMode: true })
        Column() {
          CheckRow({
            title: R.s('use_default_title'),
            summary: R.s('default_route_summary'),
            checked: this.useDefaultRoutev6,
            darkMode: true,
            onChange: (v: boolean) => {
              this.useDefaultRoutev6 = v;
              this.profile.mUseDefaultRoutev6 = v;
            }
          })
          TapRow({
            title: R.s('custom_routes_title'),
            summary: this.customRoutesv6,
            rowEnabled: !this.useDefaultRoutev6,
            showDivider: false,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('custom_routes_title', 'custom_route_message', this.customRoutesv6, (v: string) => {
                this.customRoutesv6 = v;
                this.profile.mCustomRoutesv6 = v;
              });
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ bottom: 32 })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(TAB_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TAB_BACKGROUND)
  }
}
