/**
 * Server List tab — port of Settings_Connections + ConnectionsAdapter +
 * server_card.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { Connection, ProxyType } from '../../core/Connection';
import { showSingleChoice, proxyTypeEntries, proxyTypeFromIndex, proxyTypeToIndex } from './SettingsCommon';

@Component
export struct ConnectionsTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State connections: Connection[] = [];
  @State remoteRandom: boolean = false;
  @State renderTick: number = 0;

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
    let primBtn: AlertDialogButtonBaseOptions = {
      value: R.s('keep'),
      fontColor: Theme.PRIMARY,
      action: () => {
      }
    };
    let secBtn: AlertDialogButtonBaseOptions = {
      value: R.s('delete'),
      fontColor: Theme.WARNING_RED,
      action: () => {
        this.profile.mConnections.splice(index, 1);
        this.connections = this.profile.mConnections.slice();
        this.renderTick++;
      }
    };
    let dialogParams: AlertDialogParamWithButtons = {
      title: R.s('query_delete_remote'),
      message: '',
      primaryButton: primBtn,
      secondaryButton: secBtn
    };
    AlertDialog.show(dialogParams);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // switch bar
        Row() {
          Text(R.s('remote_random'))
            .fontSize(14)
            .fontColor(Theme.TEXT_PRIMARY)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.remoteRandom })
            .selectedColor(Theme.ACCENT)
            .onChange((v: boolean) => {
              this.remoteRandom = v;
              this.profile.mRemoteRandom = v;
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#E6E6E6')

        Scroll() {
          Column() {
            if (!this.anyEnabled()) {
              Row() {
                Image($r('app.media.ic_warning'))
                  .width(20).height(20).fillColor(Theme.WARNING_RED)
                Text(R.s('remote_no_server_selected'))
                  .fontSize(14)
                  .fontColor(Theme.WARNING_RED)
                  .padding({ left: 8 })
              }
              .width('100%')
              .padding(12)
              .alignItems(VerticalAlign.Center)
            }

            ForEach(this.connections, (conn: Connection, index?: number) => {
              Column() {
                this.ConnectionCard(conn, index as number)
              }
              .borderRadius(10)
              .margin(10)
              .backgroundColor(Theme.CARD_BG)
            }, (conn: Connection, index?: number) => `${index}-${conn.mServerName}-${this.renderTick}`)

            Column()
              .height(90)
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      Button() {
        Image($r('app.media.ic_add'))
          .width(24).height(24).fillColor(Color.White)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(Theme.ACCENT)
      .margin(16)
      .shadow({ radius: 4, color: '#66000000', offsetX: 2, offsetY: 4 })
      .onClick(() => {
        this.addRemote();
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ConnectionCard(conn: Connection, index: number) {
    Column() {
      // server address
      Text(R.s('address'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ top: 8 })
      Row() {
        TextInput({ text: conn.mServerName })
          .layoutWeight(1)
          .backgroundColor(Theme.CARD_BG)
          .onChange((v: string) => {
            conn.mServerName = v;
          })

        Column() {
          Text(R.s('enabled_connection_entry'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
          Toggle({ type: ToggleType.Switch, isOn: conn.mEnabled })
            .selectedColor(Theme.ACCENT)
            .margin({ top: 2 })
            .onChange((v: boolean) => {
              conn.mEnabled = v;
              this.renderTick++;
            })
        }
        .margin({ left: 8 })
      }
      .width('100%')

      // port
      Text(R.s('port'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ top: 8 })
      Row() {
        TextInput({ text: conn.mServerPort })
          .layoutWeight(1)
          .type(InputType.Number)
          .backgroundColor(Theme.CARD_BG)
          .onChange((v: string) => {
            conn.mServerPort = v;
          })
      }
      .width('100%')

      // protocol
      Text(R.s('protocol'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ top: 8 })
      Row() {
        Radio({ value: 'udp', group: `proto${index}` })
          .checked(conn.mUseUdp)
          .onChange((checked: boolean) => {
            if (checked) {
              conn.mUseUdp = true;
              this.renderTick++;
            }
          })
        Text(R.s('udp_proto'))
          .fontSize(14)
          .margin({ left: 4 })
        Radio({ value: 'tcp', group: `proto${index}` })
          .checked(!conn.mUseUdp)
          .margin({ left: 24 })
          .onChange((checked: boolean) => {
            if (checked) {
              conn.mUseUdp = false;
              this.renderTick++;
            }
          })
        Text(R.s('tcp_proto'))
          .fontSize(14)
          .margin({ left: 4 })
      }
      .width('100%')

      // proxy
      Text(R.s('proxy'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ top: 8 })
      Column() {
        ForEach([0, 1, 2, 3], (pi: number) => {
          Row() {
            Radio({ value: `${pi}`, group: `proxy${index}` })
              .checked(proxyTypeToIndex(conn.mProxyType) === pi)
              .onChange((checked: boolean) => {
                if (checked) {
                  conn.mProxyType = proxyTypeFromIndex(pi);
                  this.renderTick++;
                }
              })
            Text(proxyTypeEntries()[pi])
              .fontSize(14)
              .margin({ left: 4 })
          }
          .width('100%')
        }, (pi: number) => `${pi}`)
      }
      .width('100%')

      if (conn.mProxyType === ProxyType.HTTP || conn.mProxyType === ProxyType.SOCKS5) {
        Text(R.s('address'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ top: 8 })
        TextInput({ text: conn.mProxyName })
          .width('100%')
          .backgroundColor(Theme.CARD_BG)
          .onChange((v: string) => {
            conn.mProxyName = v;
          })
        Text(R.s('port'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ top: 8 })
        TextInput({ text: conn.mProxyPort })
          .width('100%')
          .type(InputType.Number)
          .backgroundColor(Theme.CARD_BG)
          .onChange((v: string) => {
            conn.mProxyPort = v;
          })
      }

      if (conn.mProxyType === ProxyType.HTTP) {
        Row() {
          Checkbox()
            .select(conn.mUseProxyAuth)
            .selectedColor(Theme.PRIMARY)
            .onChange((v: boolean) => {
              conn.mUseProxyAuth = v;
              this.renderTick++;
            })
          Text(R.s('enableproxyauth'))
            .fontSize(14)
        }
        .width('100%')
        .padding({ top: 8 })

        if (conn.mUseProxyAuth) {
          Text(R.s('proxy_auth_username'))
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .padding({ top: 8 })
          TextInput({ text: conn.mProxyAuthUser === undefined ? '' : conn.mProxyAuthUser, placeholder: 'username' })
            .width('100%')
            .backgroundColor(Theme.CARD_BG)
            .onChange((v: string) => {
              conn.mProxyAuthUser = v;
            })
          Text(R.s('auth_pwquery'))
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .padding({ top: 8 })
          TextInput({ text: conn.mProxyAuthPassword === undefined ? '' : conn.mProxyAuthPassword })
            .type(InputType.Password)
            .width('100%')
            .backgroundColor(Theme.CARD_BG)
            .onChange((v: string) => {
              conn.mProxyAuthPassword = v;
            })
        }
      }

      // connect timeout
      Text(R.s('connect_timeout'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ top: 8 })
      Row() {
        Slider({
          value: conn.getTimeout(),
          min: 0,
          max: 300,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor(Theme.ACCENT)
          .onChange((value: number) => {
            conn.mConnectTimeout = Math.round(value);
            this.renderTick++;
          })
        Text(`${conn.getTimeout()} s`)
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .width(48)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // custom options
      Row() {
        Checkbox()
          .select(conn.mUseCustomConfig)
          .selectedColor(Theme.PRIMARY)
          .onChange((v: boolean) => {
            conn.mUseCustomConfig = v;
            this.renderTick++;
          })
        Text(R.s('custom_connection_options'))
          .fontSize(14)
      }
      .width('100%')
      .padding({ top: 8 })

      if (conn.mUseCustomConfig) {
        Text(R.s('custom_connection_options_warng'))
          .fontSize(12)
          .fontColor(Theme.WARNING_RED)
          .width('100%')
          .padding({ top: 4 })
        TextArea({ text: conn.mCustomConfiguration })
          .width('100%')
          .height(90)
          .backgroundColor(Theme.CARD_BG)
          .onChange((v: string) => {
            conn.mCustomConfiguration = v;
          })
      }

      // remove
      Row() {
        Blank()
        Image($r('app.media.ic_delete'))
          .width(22).height(22).fillColor(Theme.TEXT_SECONDARY)
          .padding(8)
          .onClick(() => {
            this.removeRemote(index);
          })
      }
      .width('100%')
    }
    .padding({ left: 8, right: 8, bottom: 8 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
