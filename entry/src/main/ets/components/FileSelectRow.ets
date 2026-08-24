/**
 * Port of de.blinkt.openvpn.views.FileSelectLayout — a row that lets the user
 * select a file (inlined into the profile) or clear the selection.
 */

import { Theme } from '../common/Theme';
import { VpnProfile } from '../core/VpnProfile';
import { FileUtil } from '../common/FileUtil';
import { X509Utils } from '../core/X509Utils';
import { R } from '../common/Res';
import { promptAction } from '@kit.ArkUI';

@Component
export struct FileSelectRow {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop certificate: boolean = false;
  @Prop showClear: boolean = false;
  @Prop suffixes: string = '.pem,.crt,.cer,.key,.ovpn,.conf,.txt';
  onSelect: (value: string) => void = () => {
  };
  @State private certDesc: string = '';

  private displayValue(): string {
    if (VpnProfile.isEmbedded(this.value)) {
      if (this.value.startsWith(VpnProfile.DISPLAYNAME_TAG)) {
        let name = VpnProfile.getDisplayName(this.value);
        return R.s('imported_from_file', name);
      }
      return R.s('inline_file_data');
    }
    if (this.value === '' || this.value === undefined) {
      return R.s('no_data');
    }
    return this.value;
  }

  private updateCertDesc(): void {
    this.certDesc = '';
    if (this.certificate && VpnProfile.isEmbedded(this.value)) {
      let content = VpnProfile.getEmbeddedContent(this.value);
      let summary = X509Utils.getCertificateFriendlyName(content);
      if (summary.isValid()) {
        let desc = summary.friendlyName;
        if (summary.validNotBefore !== '' && summary.validNotAfter !== '') {
          desc += ` (${summary.validNotBefore} - ${summary.validNotAfter})`;
        }
        this.certDesc = desc;
      }
    }
  }

  aboutToAppear(): void {
    this.updateCertDesc();
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
        .padding({ bottom: 4 })
      Text(this.displayValue())
        .fontSize(14)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .padding({ bottom: 2 })
        .onClick(() => {
          this.pick();
        })
      if (this.certDesc !== '') {
        Text(this.certDesc)
          .fontSize(13)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 2 })
      }
      Row() {
        Button(R.s('select'))
          .fontSize(13)
          .height(32)
          .backgroundColor(0)
          .fontColor(Theme.PRIMARY)
          .borderRadius(2)
          .border({ width: 1, color: Theme.PRIMARY })
          .onClick(() => {
            this.pick();
          })
        if (this.showClear && this.value !== '') {
          Button(R.s('clear'))
            .fontSize(13)
            .height(32)
            .backgroundColor(0)
            .fontColor(Theme.PRIMARY)
            .borderRadius(2)
            .border({ width: 1, color: Theme.PRIMARY })
            .margin({ left: 8 })
            .onClick(() => {
              this.value = '';
              this.certDesc = '';
              this.onSelect('');
            })
        }
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Theme.CARD_BG)
    .border({ width: { bottom: 1 }, color: '1F000000' })
    .alignItems(HorizontalAlign.Start)
  }

  private pick(): void {
    let suffixList = this.suffixes.split(',');
    FileUtil.pickAndRead(suffixList).then((f) => {
      if (f.content.length > VpnProfile.MAX_EMBED_FILE_SIZE) {
        promptAction.showToast({ message: R.s('import_error_message') });
        return;
      }
      this.value = VpnProfile.DISPLAYNAME_TAG + f.name + VpnProfile.INLINE_TAG + f.content;
      this.updateCertDesc();
      this.onSelect(this.value);
    }).catch(() => {
    });
  }
}
