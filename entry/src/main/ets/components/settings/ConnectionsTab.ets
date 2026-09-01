/**
 * Server List tab — port of Settings_Connections + ConnectionsAdapter +
 * server_card.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { Connection, ProxyType } from '../../core/Connection';
import { ConfirmDialog, ConfirmDialogModel } from '../ConfirmDialog';
import { proxyTypeEntries, proxyTypeFromIndex, proxyTypeToIndex } from './SettingsCommon';

@Component
export struct ConnectionsTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State connections: Connection[] = [];
  @State remoteRandom: boolean = false;
  @State renderTick: number = 0;
  private deleteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    this.connections = this.profile.mConnections;
    this.remoteRandom = this.profile.mRemoteRandom;
  }

  private anyEnabled(): boolean {
    for (let c of this.connections) {
      if (c.mEnabled) {
        return true;
      }
    }
    return false;
  }

  private addRemote(): void {
    this.profile.mConnections.push(new Connection());
    this.connections = this.profile.mConnections.slice();
    this.renderTick++;
  }

  private removeRemote(index: number): void {
    this.deleteDialogModel.title = R.s('query_delete_remote');
    this.deleteDialogModel.message = '';
    this.deleteDialogModel.cancelText = R.s('keep');
    this.deleteDialogModel.confirmText = R.s('delete');
    this.deleteDialogModel.showCancel = true;
    this.deleteDialogModel.dangerous = true;
    this.deleteDialogModel.onConfirm = () => {
      this.profile.mConnections.splice(index, 1);
      this.connections = this.profile.mConnections.slice();
      this.renderTick++;
    };
    this.deleteDialogController.open();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          Column() {
            Text(R.s('remote_random'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.DARK_TEXT_PRIMARY)
              .width('100%')
            Text(R.s('server_list'))
              .fontSize(12)
              .fontColor(Theme.DARK_TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.remoteRandom })
            .selectedColor(Theme.DARK_ACCENT)
            .onChange((v: boolean) => {
              this.remoteRandom = v;
              this.profile.mRemoteRandom = v;
            })
        }
        .width('100%')
        .padding(16)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(Theme.DARK_SURFACE)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_CARD_RADIUS)
        .margin({ top: 12, bottom: 4 })

        Scroll() {
          Column() {
            if (!this.anyEnabled()) {
              Row() {
                Image($r('app.media.ic_warning'))
                  .width(20)
                  .height(20)
                  .fillColor(Theme.DARK_DANGER)
                Text(R.s('remote_no_server_selected'))
                  .fontSize(14)
                  .fontColor(Theme.DARK_DANGER)
                  .lineHeight(20)
                  .layoutWeight(1)
                  .padding({ left: 8 })
              }
              .width('100%')
              .padding(12)
              .alignItems(VerticalAlign.Center)
              .backgroundColor(Theme.DARK_DANGER_SURFACE)
              .border({ width: 1, color: Theme.DARK_DANGER })
              .borderRadius(Theme.DARK_ROW_RADIUS)
              .margin({ top: 8, bottom: 4 })
            }

            ForEach(this.connections, (conn: Connection, index?: number) => {
              this.ConnectionCard(conn, index as number)
            }, (conn: Connection, index?: number) => `${index}-${conn.mServerName}-${this.renderTick}`)

            Column()
              .height(96)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
          .backgroundColor(Theme.DARK_BACKGROUND)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Theme.DARK_BACKGROUND)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.DARK_BACKGROUND)

      Button() {
        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(Theme.DARK_ACCENT)
      .margin(16)
      .shadow({ radius: 4, color: '#66000000', offsetX: 2, offsetY: 4 })
      .onClick(() => {
        this.addRemote();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.DARK_BACKGROUND)
  }

  @Builder
  ConnectionCard(conn: Connection, index: number) {
    Column() {
      Row() {
        Column() {
          Text(`${R.s('server_list')} ${index + 1}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .width('100%')
          Text(conn.mEnabled ? '●' : '○')
            .fontSize(12)
            .fontColor(conn.mEnabled ? Theme.DARK_ACCENT : Theme.DARK_TEXT_DISABLED)
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(R.s('enabled_connection_entry'))
            .fontSize(11)
            .fontColor(Theme.DARK_TEXT_SECONDARY)
          Toggle({ type: ToggleType.Switch, isOn: conn.mEnabled })
            .selectedColor(Theme.DARK_ACCENT)
            .margin({ top: 2 })
            .onChange((v: boolean) => {
              conn.mEnabled = v;
              this.renderTick++;
            })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(Theme.DARK_BORDER)
        .strokeWidth(1)
        .margin({ top: 14, bottom: 2 })

      Text(R.s('address'))
        .fontSize(12)
        .fontColor(Theme.DARK_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: conn.mServerName })
        .fontSize(17)
        .fontColor(Theme.DARK_TEXT_PRIMARY)
        .placeholderColor(Theme.DARK_TEXT_DISABLED)
        .backgroundColor(Theme.DARK_SURFACE_ALT)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_INPUT_RADIUS)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .width('100%')
        .onChange((v: string) => {
          conn.mServerName = v;
        })

      Text(R.s('port'))
        .fontSize(12)
        .fontColor(Theme.DARK_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 14 })
      TextInput({ text: conn.mServerPort })
        .fontSize(17)
        .fontColor(Theme.DARK_TEXT_PRIMARY)
        .placeholderColor(Theme.DARK_TEXT_DISABLED)
        .backgroundColor(Theme.DARK_SURFACE_ALT)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_INPUT_RADIUS)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .type(InputType.Number)
        .width('100%')
        .onChange((v: string) => {
          conn.mServerPort = v;
        })

      Divider()
        .color(Theme.DARK_BORDER)
        .strokeWidth(1)
        .margin({ top: 16, bottom: 2 })

      Text(R.s('protocol'))
        .fontSize(12)
        .fontColor(Theme.DARK_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 8 })
      Row() {
        Row() {
          Radio({ value: 'udp', group: `proto${index}` })
            .checked(conn.mUseUdp)
            .radioStyle({
              checkedBackgroundColor: Theme.DARK_ACCENT,
              uncheckedBorderColor: Theme.DARK_BORDER,
              indicatorColor: Theme.DARK_BACKGROUND
            })
            .onChange((checked: boolean) => {
              if (checked) {
                conn.mUseUdp = true;
                this.renderTick++;
              }
            })
          Text(R.s('udp_proto'))
            .fontSize(14)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .margin({ left: 6 })
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(Theme.DARK_SURFACE_ALT)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_ROW_RADIUS)

        Row() {
          Radio({ value: 'tcp', group: `proto${index}` })
            .checked(!conn.mUseUdp)
            .radioStyle({
              checkedBackgroundColor: Theme.DARK_ACCENT,
              uncheckedBorderColor: Theme.DARK_BORDER,
              indicatorColor: Theme.DARK_BACKGROUND
            })
            .onChange((checked: boolean) => {
              if (checked) {
                conn.mUseUdp = false;
                this.renderTick++;
              }
            })
          Text(R.s('tcp_proto'))
            .fontSize(14)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .margin({ left: 6 })
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(Theme.DARK_SURFACE_ALT)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_ROW_RADIUS)
        .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(Theme.DARK_BORDER)
        .strokeWidth(1)
        .margin({ top: 16, bottom: 2 })

      Text(R.s('proxy'))
        .fontSize(12)
        .fontColor(Theme.DARK_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 8 })
      Column() {
        ForEach([0, 1, 2, 3], (pi: number) => {
          Row() {
            Radio({ value: `${pi}`, group: `proxy${index}` })
              .checked(proxyTypeToIndex(conn.mProxyType) === pi)
              .radioStyle({
                checkedBackgroundColor: Theme.DARK_ACCENT,
                uncheckedBorderColor: Theme.DARK_BORDER,
                indicatorColor: Theme.DARK_BACKGROUND
              })
              .onChange((checked: boolean) => {
                if (checked) {
                  conn.mProxyType = proxyTypeFromIndex(pi);
                  this.renderTick++;
                }
              })
            Text(proxyTypeEntries()[pi])
              .fontSize(14)
              .fontColor(Theme.DARK_TEXT_PRIMARY)
              .layoutWeight(1)
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(Theme.DARK_SURFACE_ALT)
          .border({ width: 1, color: Theme.DARK_BORDER })
          .borderRadius(Theme.DARK_ROW_RADIUS)
          .margin({ top: pi === 0 ? 0 : 6 })
        }, (pi: number) => `${pi}`)
      }
      .width('100%')

      if (conn.mProxyType === ProxyType.HTTP || conn.mProxyType === ProxyType.SOCKS5) {
        Column() {
          Text(R.s('address'))
            .fontSize(12)
            .fontColor(Theme.DARK_TEXT_SECONDARY)
            .width('100%')
          TextInput({ text: conn.mProxyName })
            .fontSize(16)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .placeholderColor(Theme.DARK_TEXT_DISABLED)
            .backgroundColor(Theme.DARK_SURFACE)
            .border({ width: 1, color: Theme.DARK_BORDER })
            .borderRadius(Theme.DARK_INPUT_RADIUS)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .width('100%')
            .margin({ top: 6 })
            .onChange((v: string) => {
              conn.mProxyName = v;
            })
          Text(R.s('port'))
            .fontSize(12)
            .fontColor(Theme.DARK_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 12 })
          TextInput({ text: conn.mProxyPort })
            .fontSize(16)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .placeholderColor(Theme.DARK_TEXT_DISABLED)
            .backgroundColor(Theme.DARK_SURFACE)
            .border({ width: 1, color: Theme.DARK_BORDER })
            .borderRadius(Theme.DARK_INPUT_RADIUS)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .type(InputType.Number)
            .width('100%')
            .margin({ top: 6 })
            .onChange((v: string) => {
              conn.mProxyPort = v;
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(Theme.DARK_SURFACE)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_ROW_RADIUS)
        .margin({ top: 10 })
      }

      if (conn.mProxyType === ProxyType.HTTP) {
        Column() {
          Row() {
            Checkbox()
              .width(24)
              .height(24)
              .select(conn.mUseProxyAuth)
              .selectedColor(Theme.DARK_ACCENT)
              .onChange((v: boolean) => {
                conn.mUseProxyAuth = v;
                this.renderTick++;
              })
            Column() {
              Text(R.s('enableproxyauth'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.DARK_TEXT_PRIMARY)
                .width('100%')
              Text(R.s('proxy_auth_username'))
                .fontSize(12)
                .fontColor(Theme.DARK_TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 3 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (conn.mUseProxyAuth) {
            Text(R.s('proxy_auth_username'))
              .fontSize(12)
              .fontColor(Theme.DARK_TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 12 })
            TextInput({ text: conn.mProxyAuthUser === undefined ? '' : conn.mProxyAuthUser, placeholder: R.s('proxy_auth_username') })
              .fontSize(16)
              .fontColor(Theme.DARK_TEXT_PRIMARY)
              .placeholderColor(Theme.DARK_TEXT_DISABLED)
              .backgroundColor(Theme.DARK_SURFACE)
              .border({ width: 1, color: Theme.DARK_BORDER })
              .borderRadius(Theme.DARK_INPUT_RADIUS)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .width('100%')
              .margin({ top: 6 })
              .onChange((v: string) => {
                conn.mProxyAuthUser = v;
              })
            Text(R.s('auth_pwquery'))
              .fontSize(12)
              .fontColor(Theme.DARK_TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 12 })
            TextInput({ text: conn.mProxyAuthPassword === undefined ? '' : conn.mProxyAuthPassword })
              .fontSize(16)
              .fontColor(Theme.DARK_TEXT_PRIMARY)
              .placeholderColor(Theme.DARK_TEXT_DISABLED)
              .backgroundColor(Theme.DARK_SURFACE)
              .border({ width: 1, color: Theme.DARK_BORDER })
              .borderRadius(Theme.DARK_INPUT_RADIUS)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .type(InputType.Password)
              .width('100%')
              .margin({ top: 6 })
              .onChange((v: string) => {
                conn.mProxyAuthPassword = v;
              })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(Theme.DARK_SURFACE)
        .border({ width: 1, color: Theme.DARK_BORDER })
        .borderRadius(Theme.DARK_ROW_RADIUS)
        .margin({ top: 10 })
      }

      Divider()
        .color(Theme.DARK_BORDER)
        .strokeWidth(1)
        .margin({ top: 16, bottom: 2 })

      Text(R.s('connect_timeout'))
        .fontSize(12)
        .fontColor(Theme.DARK_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 8 })
      Row() {
        Slider({
          value: conn.getTimeout(),
          min: 0,
          max: 300,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor(Theme.DARK_ACCENT)
          .onChange((value: number) => {
            conn.mConnectTimeout = Math.round(value);
            this.renderTick++;
          })
        Text(`${conn.getTimeout()} s`)
          .fontSize(14)
          .fontColor(Theme.DARK_TEXT_PRIMARY)
          .width(48)
          .textAlign(TextAlign.End)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ top: 6, bottom: 4 })

      Row() {
        Checkbox()
          .width(24)
          .height(24)
          .select(conn.mUseCustomConfig)
          .selectedColor(Theme.DARK_ACCENT)
          .onChange((v: boolean) => {
            conn.mUseCustomConfig = v;
            this.renderTick++;
          })
        Column() {
          Text(R.s('custom_connection_options'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.DARK_TEXT_PRIMARY)
            .width('100%')
          Text(conn.mUseCustomConfig ? R.s('custom_connection_options_warng') : R.s('no_data'))
            .fontSize(12)
            .fontColor(conn.mUseCustomConfig ? Theme.DARK_WARNING : Theme.DARK_TEXT_SECONDARY)
            .width('100%')
            .lineHeight(18)
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .padding(12)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Theme.DARK_SURFACE_ALT)
      .border({ width: 1, color: Theme.DARK_BORDER })
      .borderRadius(Theme.DARK_ROW_RADIUS)
      .margin({ top: 12 })

      if (conn.mUseCustomConfig) {
        TextArea({ text: conn.mCustomConfiguration })
          .fontSize(14)
          .fontColor(Theme.DARK_TEXT_PRIMARY)
          .placeholderColor(Theme.DARK_TEXT_DISABLED)
          .backgroundColor(Theme.DARK_SURFACE_ALT)
          .border({ width: 1, color: Theme.DARK_BORDER })
          .borderRadius(Theme.DARK_INPUT_RADIUS)
          .padding(12)
          .width('100%')
          .height(110)
          .margin({ top: 8 })
          .onChange((v: string) => {
            conn.mCustomConfiguration = v;
          })
      }

      Row() {
        Text(R.s('delete'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.DARK_DANGER)
          .layoutWeight(1)
        Image($r('app.media.ic_delete'))
          .width(36)
          .height(36)
          .padding(8)
          .fillColor(Theme.DARK_DANGER)
          .onClick(() => {
            this.removeRemote(index);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 4, top: 6, bottom: 6 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Theme.DARK_DANGER_SURFACE)
      .border({ width: 1, color: Theme.DARK_DANGER })
      .borderRadius(Theme.DARK_ROW_RADIUS)
      .margin({ top: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Theme.DARK_SURFACE)
    .border({ width: 1, color: Theme.DARK_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
    .margin({ top: 8, bottom: 8 })
  }
}
