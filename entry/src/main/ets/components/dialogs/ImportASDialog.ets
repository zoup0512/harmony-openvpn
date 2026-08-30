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

interface AccessServerChallenge {
  state: string;
  username: string;
  challenge: string;
}

@CustomDialog
export struct ImportASDialog {
  controller?: CustomDialogController;
  @State private useAs: boolean = true;
  @State private host: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private autologin: boolean = false;
  @State private downloading: boolean = false;
  @State private otpVisible: boolean = false;
  @State private otp: string = '';
  @State private otpTitle: string = '';
  @State private otpMessage: string = '';
  @State private otpChallenge: string = '';
  @State private otpUsername: string = '';

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

  private authorizationHeader(user: string, secret: string): string {
    let b64 = new util.Base64Helper().encodeToStringSync(
      new util.TextEncoder().encodeInto(`${user}:${secret}`));
    return `Basic ${b64}`;
  }

  private continueToConverter(text: string): void {
    this.controller?.close();
    let rp: Record<string, Object> = { 'text': text, 'fileName': '' };
    let opt: router.RouterOptions = {
      url: 'pages/ConfigConverter',
      params: rp
    };
    router.pushUrl(opt);
  }

  private parseAccessServerChallenge(body: string): AccessServerChallenge | undefined {
    let marker = body.search(/CRV1\s*:/i);
    if (marker === -1) {
      return undefined;
    }
    let candidate = body.substring(marker);
    candidate = candidate.replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/&quot;/gi, '"')
      .replace(/&apos;/gi, '\'').replace(/&#39;/g, '\'').replace(/&amp;/gi, '&');
    candidate = candidate.replace(/<!\[CDATA\[/gi, '').replace(/\]\]>/g, '');
    let closingMessage = candidate.search(/<\s*\/\s*Message\b/i);
    if (closingMessage !== -1) {
      candidate = candidate.substring(0, closingMessage);
    }
    let lineEnd = candidate.search(/[\r\n]/);
    if (lineEnd !== -1) {
      candidate = candidate.substring(0, lineEnd);
    }
    let prefixEnd = candidate.indexOf(':');
    if (prefixEnd === -1 || candidate.substring(0, prefixEnd).trim().toUpperCase() !== 'CRV1') {
      return undefined;
    }
    let fields = candidate.substring(prefixEnd + 1).split(':');
    if (fields.length < 4 || fields[1].trim() === '' || fields[3].trim() === '') {
      return undefined;
    }
    let username = '';
    try {
      let encoded = fields[2].trim();
      let bytes = new util.Base64Helper().decodeSync(encoded);
      username = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(bytes));
    } catch (e) {
      return undefined;
    }
    return {
      state: fields[1].trim(),
      username: username,
      challenge: fields.slice(3).join(':').trim()
    };
  }

  private showOtpInput(challenge: AccessServerChallenge): void {
    this.otp = '';
    this.otpTitle = R.s('import_otp_title');
    this.otpMessage = R.s('import_otp_message', challenge.challenge);
    this.otpChallenge = challenge.state;
    this.otpUsername = challenge.username;
    this.otpVisible = true;
  }

  private cancelOtp(): void {
    this.otp = '';
    this.otpChallenge = '';
    this.otpUsername = '';
    this.otpVisible = false;
  }

  private submitOtp(): void {
    let response = this.otp.trim();
    if (response === '') {
      promptAction.showToast({ message: R.s('import_otp_empty') });
      return;
    }
    let challenge = this.otpChallenge;
    let username = this.otpUsername;
    if (challenge.trim() === '' || /[\r\n:]/.test(challenge) || /[\r\n]/.test(response)) {
      this.cancelOtp();
      promptAction.showToast({ message: R.s('import_error_message') });
      return;
    }
    let secret = `CRV1::${challenge}::${response}`;
    this.cancelOtp();
    this.downloading = true;
    this.requestProfile(username, secret, true);
  }

  private requestProfile(user: string, secret: string, retried: boolean): void {
    let url = this.buildUrl();
    let client = http.createHttp();
    let header: Record<string, string> = {};
    if (user !== '' || secret !== '') {
      header['Authorization'] = this.authorizationHeader(user, secret);
    }
    let reqOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 15000
    };
    client.request(url, reqOptions).then((resp: http.HttpResponse) => {
      client.destroy();
      let body = resp.result as string;
      if (resp.responseCode === 200) {
        this.downloading = false;
        this.continueToConverter(body);
      } else if (resp.responseCode === 401 && !retried) {
        let challenge = this.parseAccessServerChallenge(body);
        if (challenge !== undefined) {
          this.downloading = false;
          this.showOtpInput(challenge);
        } else {
          this.downloading = false;
          promptAction.showToast({ message: R.s('import_error_message') });
        }
      } else if (resp.responseCode === 401) {
        this.downloading = false;
        promptAction.showToast({ message: R.s('import_otp_failed') });
      } else {
        this.downloading = false;
        promptAction.showToast({ message: `${R.s('import_error_message')} (HTTP ${resp.responseCode})` });
      }
    }).catch((e: Error) => {
      client.destroy();
      this.downloading = false;
      promptAction.showToast({ message: `${R.s('import_error_message')}: ${e.message}` });
    });
  }

  private doImport(): void {
    if (this.host.trim() === '') {
      return;
    }
    this.downloading = true;
    GP.setString('as-hostname', this.host.trim());
    GP.setString('as-username', this.username);
    GP.setString('as-selected', this.useAs ? 'as' : 'url');
    this.requestProfile(this.username, this.password, false);
  }

  build() {
    Column() {
      if (this.otpVisible) {
        Text(this.otpTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .padding({ bottom: 8 })
        Text(this.otpMessage)
          .fontSize(14)
          .width('100%')
          .textAlign(TextAlign.Start)
        TextInput({ text: this.otp, placeholder: R.s('import_otp_placeholder') })
          .type(InputType.Password)
          .onChange((v: string) => {
            this.otp = v;
          })
          .width('100%')
          .margin({ top: 12 })
        Row() {
          Blank()
          Button(R.s('cancel'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(Theme.DIALOG_BUTTON_HEIGHT)
            .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
            .padding({ left: 16, right: 16 })
            .backgroundColor(Theme.CARD_BG)
            .fontColor(Theme.PRIMARY)
            .border({ width: 1, color: Theme.PRIMARY })
            .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
            .onClick(() => {
              this.cancelOtp();
            })
          Button(R.s('import_config'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(Theme.DIALOG_BUTTON_HEIGHT)
            .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
            .padding({ left: 16, right: 16 })
            .backgroundColor(Theme.PRIMARY)
            .fontColor(Theme.WHITE)
            .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
            .margin({ left: Theme.DIALOG_BUTTON_GAP })
            .onClick(() => {
              this.submitOtp();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      } else {
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
            .fontWeight(FontWeight.Medium)
            .height(Theme.DIALOG_BUTTON_HEIGHT)
            .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
            .padding({ left: 16, right: 16 })
            .backgroundColor(Theme.CARD_BG)
            .fontColor(Theme.PRIMARY)
            .border({ width: 1, color: Theme.PRIMARY })
            .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
            .onClick(() => {
              this.controller?.close();
            })
          Button(this.downloading ? R.s('importing') : R.s('import_config'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(Theme.DIALOG_BUTTON_HEIGHT)
            .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.downloading ? Theme.DIALOG_BUTTON_DISABLED_BG : Theme.PRIMARY)
            .fontColor(this.downloading ? Theme.DIALOG_BUTTON_DISABLED_TEXT : Theme.WHITE)
            .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
            .margin({ left: Theme.DIALOG_BUTTON_GAP })
            .enabled(!this.downloading)
            .onClick(() => {
              this.doImport();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(4)
  }
}

