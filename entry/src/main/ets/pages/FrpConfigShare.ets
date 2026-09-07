import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Theme } from '../common/Theme';
import { FileUtil } from '../common/FileUtil';
import { FrpConfig } from '../core/FrpConfig';
import { FrpConfigManager } from '../core/FrpConfigManager';

interface FrpShareRouteParams {
  uuid: string;
}

@Entry
@Component
struct FrpConfigShare {
  @State private name: string = '';
  @State private fileName: string = '';
  @State private content: string = '';
  @State private byteLength: number = 0;
  @State private errorMessage: string = '';
  @State private saving: boolean = false;
  private config?: FrpConfig = undefined;

  aboutToAppear(): void {
    let host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      FrpConfigManager.init(host);
    }
    let params = router.getParams() as FrpShareRouteParams;
    if (params !== undefined && params !== null && params.uuid !== undefined) {
      this.config = FrpConfigManager.getById(params.uuid);
    }
    this.loadContent();
  }

  private loadContent(): void {
    let config = this.config;
    if (config === undefined) {
      this.errorMessage = '配置不存在，请返回列表刷新';
      return;
    }
    this.name = config.name;
    this.fileName = config.fileName;
    this.content = FrpConfigManager.read(config);
    this.byteLength = new util.TextEncoder().encodeInto(this.content).byteLength;
    this.errorMessage = this.content === '' ? '配置为空或读取失败，无法生成二维码或导出' : '';
  }

  private canShowCode(): boolean {
    // ArkUI QRCode 超过 512 字符会截取。额外限制 UTF-8 字节数，
    // 避免多字节文本在不同系统实现上超限；始终传入完整原文。
    return this.content.length > 0 && this.content.length <= 512 && this.byteLength <= 512 &&
      this.content.indexOf('\u0000') === -1;
  }

  private async copyText(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.content));
      promptAction.showToast({ message: '完整 TOML 已复制' });
    } catch (error) {
      promptAction.showToast({ message: '复制失败，请重试' });
    }
  }

  private async saveFile(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      // 导出前再次读取持久化内容，绝不导出编辑器草稿或二维码截断内容。
      this.loadContent();
      if (this.errorMessage !== '') {
        throw new Error(this.errorMessage);
      }
      await FileUtil.saveText(this.fileName, this.content, '.toml',
        this.getUIContext().getHostContext() as common.UIAbilityContext);
      promptAction.showToast({ message: '配置已保存到手机' });
    } catch (error) {
      if ((error as Error).message !== 'cancelled') {
        promptAction.showToast({ message: `保存失败：${(error as Error).message}` });
      }
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('‹', { type: ButtonType.Normal })
          .fontSize(30).height(44).width(44).padding(0)
          .backgroundColor(Theme.TRANSPARENT).fontColor(Theme.FRP_TEXT_PRIMARY)
          .accessibilityText('返回').onClick(() => router.back())
        Text('分享配置').fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor(Theme.FRP_TEXT_PRIMARY).layoutWeight(1)
      }.width('100%').height(56).padding({ left: 8, right: 16 })
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 10 }) {
            Text(this.name === '' ? 'FRP 配置' : this.name)
              .fontSize(22).fontWeight(FontWeight.Medium).fontColor(Theme.FRP_TEXT_PRIMARY)
              .width('100%').textAlign(TextAlign.Center)
            Text(this.fileName).fontSize(13).fontColor(Theme.FRP_TEXT_SECONDARY)
            if (this.errorMessage !== '') {
              Text(this.errorMessage).fontSize(14).fontColor(Theme.FRP_DANGER)
            } else if (this.canShowCode()) {
              Column() {
                QRCode(this.content)
                  .width(240).height(240).color('#000000').backgroundColor('#FFFFFF')
                  .accessibilityText('当前配置完整 TOML 二维码')
              }.padding(20).backgroundColor('#FFFFFF')
              Text('扫描二维码获取完整 TOML 配置')
                .fontSize(13).fontColor(Theme.FRP_TEXT_SECONDARY)
            } else {
              Column({ space: 10 }) {
                Text('无法安全生成二维码').fontSize(18).fontWeight(FontWeight.Medium).fontColor(Theme.NOTICE_LIGHT)
                Text(`当前配置 ${this.byteLength} UTF-8 字节。二维码安全上限为 512 字节 / 512 字符，且不支持空字符。为防止截断，已停止生成，请保存完整 .toml 文件。`)
                  .fontSize(14).lineHeight(22).fontColor(Theme.NOTICE_LIGHT)
              }.width('100%').padding(20).backgroundColor(Theme.NOTICE_LIGHT_BG)
              .borderRadius(Theme.FRP_INPUT_RADIUS)
            }
          }.width('100%').padding(20).backgroundColor(Theme.FRP_CARD_BG)
          .borderRadius(Theme.FRP_CARD_RADIUS)
          Text('配置可能包含服务器地址、令牌和密码。请仅向可信设备展示或复制；本页不会上传配置。')
            .fontSize(12).lineHeight(20).fontColor(Theme.NOTICE_LIGHT).width('100%')
          Row({ space: 12 }) {
            Button('复制原文', { type: ButtonType.Normal })
              .layoutWeight(1).height(44).borderRadius(Theme.FRP_BUTTON_RADIUS)
              .backgroundColor(Theme.FRP_ACTION_BG).fontColor(Theme.FRP_ACCENT)
              .enabled(this.errorMessage === '' && this.content !== '')
              .onClick(() => { this.copyText(); })
            Button(this.saving ? '保存中…' : '保存 .toml', { type: ButtonType.Normal })
              .layoutWeight(1).height(44).borderRadius(Theme.FRP_BUTTON_RADIUS)
              .backgroundColor(Theme.FRP_ACCENT).fontColor(Theme.WHITE)
              .enabled(!this.saving && this.errorMessage === '' && this.content !== '')
              .onClick(() => { this.saveFile(); })
          }.width('100%')
          Column({ space: 12 }) {
            Row() {
              Text('配置原文').fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
                .fontColor(Theme.FRP_TEXT_SECONDARY)
              Text(`${this.byteLength} 字节`).fontSize(12).fontColor(Theme.FRP_TEXT_SECONDARY)
            }.width('100%')
            Text(this.content).fontSize(12).fontFamily('monospace')
              .fontColor(Theme.FRP_TOML_TEXT).lineHeight(20)
              .width('100%').padding(14).backgroundColor(Theme.FRP_TOML_BG)
              .borderRadius(Theme.FRP_INPUT_RADIUS).copyOption(CopyOptions.LocalDevice)
          }.width('100%')
        }.width('100%').padding(16)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor(Theme.FRP_PAGE_BG)
  }
}
