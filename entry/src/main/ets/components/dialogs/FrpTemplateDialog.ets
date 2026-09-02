/**
 * FRP configuration creation dialog. The caller decides where the created
 * configuration should be opened; this component only selects a type and a
 * packaged template (or a blank document).
 */

import { Theme } from '../../common/Theme';
import { FrpConfigTemplate, FrpTemplateManager } from '../../core/FrpTemplateManager';
import { FrpType } from '../../core/FrpType';

export type FrpTemplateSelection = (type: FrpType, template?: FrpConfigTemplate) => void;

@CustomDialog
export struct FrpTemplateDialog {
  controller?: CustomDialogController;
  @Prop darkMode: boolean = false;
  @State private selectedType: FrpType = FrpType.FRPC;
  @State private selectedFileName: string = '';
  @State private templates: FrpConfigTemplate[] = [];
  onSelected: FrpTemplateSelection = () => {
  };

  aboutToAppear(): void {
    this.reloadTemplates();
  }

  private reloadTemplates(): void {
    this.templates = FrpTemplateManager.list(this.selectedType);
    this.selectedFileName = '';
  }

  private selectType(type: FrpType): void {
    if (this.selectedType === type) {
      return;
    }
    this.selectedType = type;
    this.reloadTemplates();
  }

  private choose(): void {
    let selected: FrpConfigTemplate | undefined = undefined;
    for (let template of this.templates) {
      if (template.fileName === this.selectedFileName) {
        selected = template;
        break;
      }
    }
    this.controller?.close();
    this.onSelected(this.selectedType, selected);
  }

  @Builder
  private TypeChoice(type: FrpType, title: string, description: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedType === type
            ? (this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
            : (this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY))
        Text(description)
          .fontSize(12)
          .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Radio({ value: type, group: 'frp-type' })
        .checked(this.selectedType === type)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedType === type
      ? (this.darkMode ? Theme.DARK_SURFACE_ALT : '#EEF1FF')
      : (this.darkMode ? Theme.DARK_SURFACE : '#F7F8FC'))
    .border({
      width: this.selectedType === type ? 2 : 1,
      color: this.selectedType === type
        ? (this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
        : (this.darkMode ? Theme.DARK_BORDER : Theme.DIVIDER)
    })
    .borderRadius(12)
    .onClick(() => {
      this.selectType(type);
    })
  }

  @Builder
  private TemplateChoice(template: FrpConfigTemplate) {
    Row() {
      Column() {
        Text(template.displayName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedFileName === template.fileName
            ? (this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
            : (this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(template.fileName)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Radio({ value: template.fileName, group: 'frp-template' })
        .checked(this.selectedFileName === template.fileName)
    }
    .width('100%')
    .padding(12)
    .margin({ top: 8 })
    .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
    .border({
      width: this.selectedFileName === template.fileName ? 2 : 1,
      color: this.selectedFileName === template.fileName
        ? (this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
        : (this.darkMode ? Theme.DARK_BORDER : Theme.DIVIDER)
    })
    .borderRadius(10)
    .onClick(() => {
      this.selectedFileName = template.fileName;
    })
  }

  @Builder
  private BlankChoice() {
    Row() {
      Column() {
        Text('空白配置')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedFileName === ''
            ? (this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
            : (this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY))
        Text('打开原文编辑器，手动填写 TOML')
          .fontSize(12)
          .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Radio({ value: 'blank', group: 'frp-template' })
        .checked(this.selectedFileName === '')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
    .border({
      width: this.selectedFileName === '' ? 2 : 1,
      color: this.selectedFileName === ''
        ? (this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
        : (this.darkMode ? Theme.DARK_BORDER : Theme.DIVIDER)
    })
    .borderRadius(10)
    .onClick(() => {
      this.selectedFileName = '';
    })
  }

  build() {
    Column() {
      Text('新建 FRP 配置')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY)
        .width('100%')
      Text('选择运行类型和初始内容')
        .fontSize(14)
        .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 6, bottom: 14 })

      Row() {
        this.TypeChoice(FrpType.FRPC, 'frpc', '客户端，连接到 frps')
        this.TypeChoice(FrpType.FRPS, 'frps', '服务端，接受 frpc 连接')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Scroll() {
        Column() {
          this.BlankChoice()
          ForEach(this.templates, (template: FrpConfigTemplate) => {
            this.TemplateChoice(template)
          }, (template: FrpConfigTemplate) => `${template.type}:${template.fileName}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(220)
      .margin({ top: 8 })

      Row() {
        Blank()
        Button('取消')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(Theme.DIALOG_BUTTON_HEIGHT)
          .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.darkMode ? Theme.DARK_SURFACE_ALT : Theme.CARD_BG)
          .fontColor(this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
          .border({ width: 1, color: this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY })
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
          .backgroundColor(this.darkMode ? Theme.DARK_ACTION : Theme.PRIMARY)
          .fontColor(Theme.WHITE)
          .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
          .margin({ left: Theme.DIALOG_BUTTON_GAP })
          .onClick(() => {
            this.choose();
          })
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
    .borderRadius(this.darkMode ? Theme.DARK_CARD_RADIUS : 4)
  }
}
