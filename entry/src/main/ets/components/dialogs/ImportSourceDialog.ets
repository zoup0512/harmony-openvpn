import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';

const SOURCE_NONE: number = -1;
const SOURCE_LOCAL: number = 0;
const SOURCE_CLOUD: number = 1;
const SOURCE_SELECTED_BG: string = '#EEF1FF';
const SOURCE_NORMAL_BG: string = '#F7F8FC';

@CustomDialog
export struct ImportSourceDialog {
  controller?: CustomDialogController;
  onLocal: () => void = () => {
  };
  onCloud: () => void = () => {
  };
  @State private selectedSource: number = SOURCE_NONE;

  aboutToAppear(): void {
    this.selectedSource = SOURCE_NONE;
  }

  private confirmSelection(): void {
    if (this.selectedSource === SOURCE_NONE) {
      return;
    }
    let selectedSource = this.selectedSource;
    this.controller?.close();
    if (selectedSource === SOURCE_LOCAL) {
      this.onLocal();
    } else {
      this.onCloud();
    }
  }

  @Builder
  private LocalSourceCard() {
    Column() {
      Row() {
        Image($r('app.media.ic_import'))
          .width(32)
          .height(32)
          .fillColor(this.selectedSource === SOURCE_LOCAL ? Theme.PRIMARY : Theme.TEXT_SECONDARY)
        Blank()
        Radio({ value: 'local', group: 'import-source' })
          .checked(this.selectedSource === SOURCE_LOCAL)
          .onChange((checked: boolean) => {
            if (checked) {
              this.selectedSource = SOURCE_LOCAL;
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(R.s('import_from_local'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedSource === SOURCE_LOCAL ? Theme.PRIMARY : Theme.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 14 })
      Text(R.s('import_from_local_summary'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height(156)
    .padding(14)
    .margin({ right: 6 })
    .backgroundColor(this.selectedSource === SOURCE_LOCAL ? SOURCE_SELECTED_BG : SOURCE_NORMAL_BG)
    .border({
      width: this.selectedSource === SOURCE_LOCAL ? 2 : 1,
      color: this.selectedSource === SOURCE_LOCAL ? Theme.PRIMARY : Theme.DIVIDER
    })
    .borderRadius(12)
    .onClick(() => {
      this.selectedSource = SOURCE_LOCAL;
    })
  }

  @Builder
  private CloudSourceCard() {
    Column() {
      Row() {
        Image($r('app.media.ic_download'))
          .width(32)
          .height(32)
          .fillColor(this.selectedSource === SOURCE_CLOUD ? Theme.PRIMARY : Theme.TEXT_SECONDARY)
        Blank()
        Radio({ value: 'cloud', group: 'import-source' })
          .checked(this.selectedSource === SOURCE_CLOUD)
          .onChange((checked: boolean) => {
            if (checked) {
              this.selectedSource = SOURCE_CLOUD;
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(R.s('import_from_cloud'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedSource === SOURCE_CLOUD ? Theme.PRIMARY : Theme.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 14 })
      Text(R.s('import_from_cloud_summary'))
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height(156)
    .padding(14)
    .margin({ left: 6 })
    .backgroundColor(this.selectedSource === SOURCE_CLOUD ? SOURCE_SELECTED_BG : SOURCE_NORMAL_BG)
    .border({
      width: this.selectedSource === SOURCE_CLOUD ? 2 : 1,
      color: this.selectedSource === SOURCE_CLOUD ? Theme.PRIMARY : Theme.DIVIDER
    })
    .borderRadius(12)
    .onClick(() => {
      this.selectedSource = SOURCE_CLOUD;
    })
  }

  build() {
    Column() {
      Text(R.s('import_config'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      Text(R.s('import_source_hint'))
        .fontSize(14)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 6, bottom: 18 })

      Row() {
        this.LocalSourceCard()
        this.CloudSourceCard()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        Blank()
        Button(R.s('cancel'))
          .fontSize(14)
          .backgroundColor(0)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.controller?.close();
          })
        Button(R.s('continue_action'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(0)
          .fontColor(this.selectedSource === SOURCE_NONE ? Theme.TEXT_DISABLED : Theme.PRIMARY)
          .margin({ left: 8 })
          .enabled(this.selectedSource !== SOURCE_NONE)
          .onClick(() => {
            this.confirmSelection();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Theme.CARD_BG)
    .borderRadius(12)
  }
}
