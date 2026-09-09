/**
 * FRP entry dialog. The caller decides whether to import a TOML file or
 * create a new configuration; this component only captures that choice.
 */

import { Theme } from '../../common/Theme';

const ENTRY_NONE: number = -1;
const ENTRY_IMPORT: number = 0;
const ENTRY_NEW: number = 1;
const ENTRY_SELECTED_BG: string = '#EEF1FF';
const ENTRY_NORMAL_BG: string = '#F7F8FC';

@CustomDialog
export struct FrpEntryDialog {
  controller?: CustomDialogController;
  onImport: () => void = () => {
  };
  onNew: () => void = () => {
  };
  @State private selectedEntry: number = ENTRY_NONE;

  aboutToAppear(): void {
    this.selectedEntry = ENTRY_NONE;
  }

  private confirmSelection(): void {
    if (this.selectedEntry === ENTRY_NONE) {
      return;
    }
    let selectedEntry = this.selectedEntry;
    this.controller?.close();
    if (selectedEntry === ENTRY_IMPORT) {
      this.onImport();
    } else {
      this.onNew();
    }
  }

  @Builder
  private EntryCard(entry: number, icon: Resource, title: string, summary: string) {
    Column() {
      Row() {
        Image(icon)
          .width(32)
          .height(32)
          .fillColor(this.selectedEntry === entry ? Theme.PRIMARY : Theme.TEXT_SECONDARY)
        Blank()
        Radio({ value: `${entry}`, group: 'frp-entry' })
          .checked(this.selectedEntry === entry)
          .onChange((checked: boolean) => {
            if (checked) {
              this.selectedEntry = entry;
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedEntry === entry ? Theme.PRIMARY : Theme.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 14 })
      Text(summary)
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height(156)
    .padding(14)
    .margin({ left: entry === ENTRY_NEW ? 6 : 0, right: entry === ENTRY_IMPORT ? 6 : 0 })
    .backgroundColor(this.selectedEntry === entry ? ENTRY_SELECTED_BG : ENTRY_NORMAL_BG)
    .border({
      width: this.selectedEntry === entry ? 2 : 1,
      color: this.selectedEntry === entry ? Theme.PRIMARY : Theme.DIVIDER
    })
    .borderRadius(12)
    .onClick(() => {
      this.selectedEntry = entry;
    })
  }

  build() {
    Column() {
      Text('添加 FRP 配置')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      Text('选择导入已有配置，或从模板/空白配置开始')
        .fontSize(14)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 6, bottom: 18 })

      Row() {
        this.EntryCard(ENTRY_IMPORT, $r('app.media.ic_import'), '导入 TOML', '选择设备上的 TOML 文件并导入配置')
        this.EntryCard(ENTRY_NEW, $r('app.media.ic_add'), '新建配置', '从空白配置或预置模板开始')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        Blank()
        Button('取消')
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
        Button('继续')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(Theme.DIALOG_BUTTON_HEIGHT)
          .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.selectedEntry === ENTRY_NONE
            ? Theme.DIALOG_BUTTON_DISABLED_BG : Theme.PRIMARY)
          .fontColor(this.selectedEntry === ENTRY_NONE
            ? Theme.DIALOG_BUTTON_DISABLED_TEXT : Theme.WHITE)
          .border({
            width: 1,
            color: this.selectedEntry === ENTRY_NONE
              ? Theme.DIALOG_BUTTON_DISABLED_BORDER : Theme.PRIMARY
          })
          .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
          .margin({ left: Theme.DIALOG_BUTTON_GAP })
          .enabled(this.selectedEntry !== ENTRY_NONE)
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
