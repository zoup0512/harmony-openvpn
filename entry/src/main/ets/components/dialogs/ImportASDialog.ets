/**
 * Port of fragments/ImportRemoteConfig — import a profile from an OpenVPN
 * Access Server or an arbitrary URL.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { GP } from '../../common/GP';
import { router, promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

@CustomDialog
export struct ImportASDialog {
  controller?: CustomDialogController;
  @State private useAs: boolean = true;
  @State private host: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private autologin: boolean = false;
  @State private downloading: boolean = false;

  aboutToAppear(): void {
    this.host = GP.getString('as-hostname', '');
    this.username = GP.getString('as-username', '');
    this.autologin = GP.getString('as-selected', '') === 'as';
  }

  private buildUrl(): string {
    let host = this.host.trim();
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      host = `https://${host}`;
    }
    if (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    if (this.useAs) {
      let rest = this.autologin ? '/rest/GetAutologin?tls-cryptv2=1' : '/rest/GetUserlogin?tls-cryptv2=1';
      return host + rest;
    }
    return host;
  }

  private doImport(): void {
    if (this.host.trim() === '') {
      return;
    }
    this.downloading = true;
    GP.setString('as-hostname', this.host.trim());
    GP.setString('as-username', this.username);
    GP.setString('as-selected', this.useAs ? 'as' : 'url');

    let url = this.buildUrl();
    let client = http.createHttp();
    let header: Record<string, string> = {};
    if (this.username !== '' || this.password !== '') {
      let b64 = new util.Base64Helper().encodeToStringSync(
        new util.TextEncoder().encodeInto(`${this.username}:${this.password}`));
      header['Authorization'] = `Basic ${b64}`;
    }
    let reqOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 15000
    };
    client.request(url, reqOptions).then((resp: http.HttpResponse) => {
      this.downloading = false;
      client.destroy();
      if (resp.responseCode === 200) {
        let text = resp.result as string;
        this.controller?.close();
        let rp: Record<string, Object> = { 'text': text, 'fileName': '' };
        let opt: router.RouterOptions = {
          url: 'pages/ConfigConverter',
          params: rp
        };
        router.pushUrl(opt);
      } else if (resp.responseCode === 401) {
        promptAction.showToast({ message: R.s('import_error_message') });
      } else {
        promptAction.showToast({ message: `${R.s('import_error_message')} (HTTP ${resp.responseCode})` });
      }
    }).catch((e: Error) => {
      this.downloading = false;
      client.destroy();
      promptAction.showToast({ message: `${R.s('import_error_message')}: ${e.message}` });
    });
  }

  build() {
    Column() {
      Text(R.s('import_from_as'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ bottom: 12 })

      Row() {
        Radio({ value: 'as', group: 'importsrc' })
          .checked(this.useAs)
          .onChange((checked: boolean) => {
            if (checked) {
              this.useAs = true;
            }
          })
        Text(R.s('import_from_access_server'))
          .fontSize(14)
          .margin({ left: 4 })
        Radio({ value: 'url', group: 'importsrc' })
          .checked(!this.useAs)
          .margin({ left: 16 })
          .onChange((checked: boolean) => {
            if (checked) {
              this.useAs = false;
            }
          })
        Text(R.s('import_from_URL'))
          .fontSize(14)
          .margin({ left: 4 })
      }
      .width('100%')

      TextInput({ text: this.host, placeholder: this.useAs ? R.s('as_servername') : R.s('server_url') })
        .onChange((v: string) => {
          this.host = v;
        })
        .width('100%')
        .margin({ top: 8 })

      TextInput({ text: this.username, placeholder: R.s('auth_username') })
        .onChange((v: string) => {
          this.username = v;
        })
        .width('100%')
        .margin({ top: 8 })

      TextInput({ text: this.password, placeholder: R.s('password') })
        .type(InputType.Password)
        .onChange((v: string) => {
          this.password = v;
        })
        .width('100%')
        .margin({ top: 8 })

      if (this.useAs) {
        Row() {
          Checkbox()
            .select(this.autologin)
            .selectedColor(Theme.PRIMARY)
            .onChange((v: boolean) => {
              this.autologin = v;
            })
          Text(R.s('request_autologin'))
            .fontSize(14)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      Row() {
        Blank()
        Button(R.s('cancel'))
          .fontSize(14)
          .backgroundColor(0)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.controller?.close();
          })
        Button(this.downloading ? R.s('importing') : R.s('import_config'))
          .fontSize(14)
          .backgroundColor(0)
          .fontColor(Theme.PRIMARY)
          .margin({ left: 8 })
          .enabled(!this.downloading)
          .onClick(() => {
            this.doImport();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(4)
  }
}

