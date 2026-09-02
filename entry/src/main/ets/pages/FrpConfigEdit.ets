/**
 * FRP TOML editor.
 *
 * Route parameters:
 *   uuid: existing FrpConfig.key to edit
 *   type: frpc or frps when creating
 *   new: true when creating a new configuration
 *
 * Export uses the HarmonyOS DocumentViewPicker save flow; an optional callback
 * remains available for hosts that want to provide a custom export destination.
 */

import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { FrpConfigTemplate, FrpTemplateManager } from '../core/FrpTemplateManager';
import { FrpConfig } from '../core/FrpConfig';
import { FrpConfigManager } from '../core/FrpConfigManager';
import { FrpType, parseFrpType } from '../core/FrpType';
import { FrpValidator, FrpValidationResult } from '../core/FrpValidator';
import { FrpLogStore } from '../core/FrpLogStore';
import { FrpStatus, FrpRunState } from '../core/FrpStatus';
import { FileUtil } from '../common/FileUtil';
import { Theme } from '../common/Theme';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { ConfirmDialog, ConfirmDialogModel } from '../components/ConfirmDialog';
import { FrpTemplateDialog } from '../components/dialogs/FrpTemplateDialog';

interface FrpEditRouteParams {
  uuid?: string;
  type?: string;
  new?: boolean;
  templateFileName?: string;
}

export type FrpExportHandler = (config: FrpConfig, content: string) => void;

const EDIT_BACKGROUND: string = Theme.DARK_BACKGROUND;
const EDIT_TOOLBAR: string = Theme.DARK_TOOLBAR;
const EDIT_SURFACE: string = Theme.DARK_SURFACE;
const EDIT_SURFACE_ALT: string = Theme.DARK_SURFACE_ALT;
const EDIT_BORDER: string = Theme.DARK_BORDER;
const EDIT_TEXT: string = Theme.DARK_TEXT_PRIMARY;
const EDIT_MUTED: string = Theme.DARK_TEXT_SECONDARY;
const EDIT_DISABLED: string = Theme.DARK_TEXT_DISABLED;
const EDIT_ACTION: string = Theme.DARK_ACTION;
const EDIT_ACCENT: string = Theme.DARK_ACCENT;
const EDIT_DANGER: string = Theme.DARK_DANGER;
const EDIT_DANGER_BACKGROUND: string = Theme.DARK_DANGER_SURFACE;

@Entry
@Component
struct FrpConfigEdit {
  @State private fileName: string = '';
  @State private displayName: string = '';
  @State private content: string = '';
  @State private autoStart: boolean = false;
  @State private configType: FrpType = FrpType.FRPC;
  @State private validationText: string = '尚未验证';
  @State private validationColor: string = EDIT_MUTED;
  @State private validationWarnings: string = '';
  @State private loaded: boolean = false;
  @State private isNew: boolean = false;

  private config?: FrpConfig = undefined;
  private routeTemplate?: string = undefined;
  private exportHandler?: FrpExportHandler = undefined;
  private copyDialogModel: InputDialogModel = new InputDialogModel();
  private copyDialogController: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.copyDialogModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });
  private deleteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });
  private templateDialogController: CustomDialogController = new CustomDialogController({
    builder: FrpTemplateDialog({
      darkMode: true,
      onSelected: (type: FrpType, template?: FrpConfigTemplate) => {
        this.applyTemplate(type, template);
      }
    }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      FrpConfigManager.init(context);
      FrpTemplateManager.init(context);
    }
    let params = router.getParams() as FrpEditRouteParams;
    this.routeTemplate = params === undefined || params === null ? undefined : params.templateFileName;
    let uuid = params === undefined || params === null ? undefined : params.uuid;
    let existing: FrpConfig | undefined = uuid === undefined ? undefined : FrpConfigManager.getById(uuid);
    if (uuid !== undefined && existing === undefined && !(params !== undefined && params !== null && params.new === true)) {
      promptAction.showToast({ message: 'FRP 配置不存在' });
      router.back();
      return;
    }
    if (existing !== undefined) {
      this.config = existing;
      this.configType = existing.type;
      this.fileName = existing.fileName;
      this.displayName = existing.displayName;
      this.autoStart = existing.autoStart;
      this.content = FrpConfigManager.read(existing);
      this.isNew = false;
      this.loaded = true;
      this.validateDraft(false);
      return;
    }

    this.isNew = params !== undefined && params !== null && params.new === true;
    let requestedType = params === undefined || params === null ? undefined : params.type;
    let parsed = requestedType === undefined ? undefined : parseFrpType(requestedType);
    this.configType = parsed === undefined ? FrpType.FRPC : parsed;
    this.fileName = this.configType === FrpType.FRPC ? 'frpc.toml' : 'frps.toml';
    this.displayName = '';
    this.content = '';
    this.autoStart = false;
    this.loaded = true;
    if (this.routeTemplate !== undefined && this.routeTemplate !== '') {
      let template = FrpTemplateManager.get(this.configType, this.routeTemplate);
      this.applyTemplate(this.configType, template);
    }
  }

  onBackPress(): boolean {
    router.back();
    return true;
  }

  private applyTemplate(type: FrpType, template?: FrpConfigTemplate): void {
    this.configType = type;
    if (template === undefined) {
      this.fileName = type === FrpType.FRPC ? 'frpc.toml' : 'frps.toml';
      this.displayName = '';
      this.content = '';
      this.validationText = '尚未验证';
      this.validationColor = EDIT_MUTED;
      this.validationWarnings = '';
      return;
    }
    this.fileName = template.fileName;
    this.displayName = template.displayName;
    this.content = FrpTemplateManager.read(template);
    this.validationText = '已载入模板，尚未保存';
    this.validationColor = EDIT_ACCENT;
    this.validationWarnings = '';
  }

  private draftConfig(name: string = this.fileName): FrpConfig {
    if (this.config !== undefined && name === this.config.fileName) {
      return this.config;
    }
    return new FrpConfig(this.configType, name, this.displayName);
  }

  private validateDraft(showToast: boolean): FrpValidationResult {
    let safeName = FrpValidator.normalizeFileName(this.fileName);
    let candidate = this.draftConfig(safeName);
    let result = FrpValidator.validateConfig(candidate, this.content);
    if (result.valid) {
      this.validationText = result.warnings.length > 0 ? '验证通过（有警告）' : '验证通过';
      this.validationColor = result.warnings.length > 0 ? Theme.STATUS_CONNECTING : Theme.STATUS_SUCCESS;
      this.validationWarnings = result.warnings.join('\n');
      if (showToast) {
        promptAction.showToast({ message: this.validationText });
      }
    } else {
      this.validationText = result.message === '' ? '验证失败' : result.message;
      this.validationColor = Theme.STATUS_ERROR;
      this.validationWarnings = result.warnings.join('\n');
      if (showToast) {
        promptAction.showToast({ message: this.validationText });
      }
    }
    return result;
  }

  private saveDraft(): boolean {
    if (!this.loaded) {
      return false;
    }
    let safeName = FrpValidator.normalizeFileName(this.fileName);
    let nameValidation = FrpValidator.validateFileName(safeName);
    if (!nameValidation.valid) {
      this.validationText = nameValidation.message;
      this.validationColor = Theme.STATUS_ERROR;
      promptAction.showToast({ message: nameValidation.message });
      return false;
    }
    let candidate = new FrpConfig(this.configType, safeName, this.displayName.trim());
    let validation = FrpValidator.validateConfig(candidate, this.content);
    if (!validation.valid) {
      this.validationText = validation.message;
      this.validationColor = Theme.STATUS_ERROR;
      this.validationWarnings = validation.warnings.join('\n');
      promptAction.showToast({ message: validation.message });
      return false;
    }

    try {
      if (this.isNew || this.config === undefined) {
        let created = FrpConfigManager.importContent(this.configType, safeName, this.content,
          this.displayName.trim());
        FrpConfigManager.setAutoStart(created, this.autoStart);
        this.config = created;
        this.isNew = false;
        this.fileName = created.fileName;
        this.loaded = true;
      } else {
        if (this.config.fileName !== safeName) {
          this.config = FrpConfigManager.rename(this.config, safeName);
        }
        this.config.displayName = this.displayName.trim();
        let saved = FrpConfigManager.save(this.config, this.content);
        if (!saved.valid) {
          this.validationText = saved.message;
          this.validationColor = Theme.STATUS_ERROR;
          promptAction.showToast({ message: saved.message });
          return false;
        }
        FrpConfigManager.setAutoStart(this.config, this.autoStart);
      }
      this.validationText = validation.warnings.length > 0 ? '已保存（有警告）' : '已保存';
      this.validationColor = validation.warnings.length > 0 ? Theme.STATUS_CONNECTING : Theme.STATUS_SUCCESS;
      this.validationWarnings = validation.warnings.join('\n');
      promptAction.showToast({ message: this.validationText });
      return true;
    } catch (error) {
      let message = (error as Error).message;
      if (message === '') {
        message = '配置保存失败';
      }
      this.validationText = message;
      this.validationColor = Theme.STATUS_ERROR;
      promptAction.showToast({ message: message });
      return false;
    }
  }

  private saveAndBack(): void {
    if (this.saveDraft()) {
      router.back();
    }
  }

  private copyContent(): void {
    if (this.content === '') {
      promptAction.showToast({ message: '暂无可复制内容' });
      return;
    }
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.content);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '配置原文已复制' });
    }).catch(() => {
      promptAction.showToast({ message: '配置复制失败' });
    });
  }

  private openCopyDialog(): void {
    let source = this.fileName.toLowerCase().endsWith('.toml')
      ? this.fileName.substring(0, this.fileName.length - 5) : this.fileName;
    this.copyDialogModel.title = '复制配置';
    this.copyDialogModel.message = '输入新文件名（可省略 .toml）';
    this.copyDialogModel.placeholder = 'new-config.toml';
    this.copyDialogModel.initial = `${source}-copy.toml`;
    this.copyDialogModel.okText = '复制';
    this.copyDialogModel.cancelText = '取消';
    this.copyDialogModel.neutralText = '';
    this.copyDialogModel.validate = (value: string): boolean => {
      let safe = FrpValidator.normalizeFileName(value);
      let result = FrpValidator.validateFileName(safe);
      if (!result.valid) {
        promptAction.showToast({ message: result.message });
        return false;
      }
      return true;
    };
    this.copyDialogModel.onOk = (value: string) => {
      if (this.config === undefined) {
        promptAction.showToast({ message: '请先保存新配置，再复制配置' });
        return;
      }
      try {
        let copy = FrpConfigManager.copy(this.config, FrpValidator.normalizeFileName(value), this.displayName);
        promptAction.showToast({ message: `已复制为 ${copy.fileName}` });
        router.pushUrl({ url: 'pages/FrpConfigEdit', params: { 'uuid': copy.key } });
      } catch (error) {
        promptAction.showToast({ message: (error as Error).message });
      }
    };
    this.copyDialogController.open();
  }

  private askDelete(): void {
    if (this.config === undefined) {
      router.back();
      return;
    }
    let snapshot = FrpStatus.get(this.config);
    if (FrpStatus.isActive(snapshot.state)) {
      promptAction.showToast({ message: '配置运行中，停止后才能删除' });
      return;
    }
    let config = this.config;
    this.deleteDialogModel.title = '删除 FRP 配置';
    this.deleteDialogModel.message = `确定删除“${config.name}”及其日志吗？`;
    this.deleteDialogModel.cancelText = '取消';
    this.deleteDialogModel.confirmText = '删除';
    this.deleteDialogModel.dangerous = true;
    this.deleteDialogModel.onConfirm = () => {
      if (FrpConfigManager.remove(config)) {
        promptAction.showToast({ message: '配置已删除' });
        router.back();
      } else {
        promptAction.showToast({ message: '配置删除失败' });
      }
    };
    this.deleteDialogController.open();
  }

  private exportConfig(): void {
    if (this.config === undefined) {
      promptAction.showToast({ message: '请先保存配置，再导出' });
      return;
    }
    if (this.exportHandler !== undefined) {
      this.exportHandler(this.config, this.content);
      return;
    }
    let host = this.getUIContext().getHostContext();
    FileUtil.saveText(this.config.fileName, this.content, '.toml', host as common.UIAbilityContext).then(() => {
      promptAction.showToast({ message: '配置已导出' });
    }).catch((error: Error) => {
      if (error.message !== 'cancelled') {
        promptAction.showToast({ message: `导出失败：${error.message}` });
      }
    });
  }

  private clearLog(): void {
    if (this.config === undefined) {
      return;
    }
    if (FrpLogStore.clear(this.config)) {
      promptAction.showToast({ message: '日志已清除' });
    } else {
      promptAction.showToast({ message: '日志清除失败' });
    }
  }

  @Builder
  private HeaderCard() {
    Row() {
      Column() {
        Text('运行类型')
          .fontSize(12)
          .fontColor(EDIT_MUTED)
        Text(this.configType === FrpType.FRPC ? 'frpc 客户端' : 'frps 服务端')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(EDIT_TEXT)
          .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.isNew ? '新建配置' : '已保存配置')
        .fontSize(12)
        .fontColor(EDIT_ACCENT)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(EDIT_SURFACE_ALT)
        .borderRadius(10)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  private IdentityCard() {
    Column() {
      Text('显示名')
        .fontSize(12)
        .fontColor(EDIT_MUTED)
        .width('100%')
      TextInput({ text: this.displayName, placeholder: '留空则使用文件名' })
        .fontSize(17)
        .fontColor(EDIT_TEXT)
        .placeholderColor(EDIT_DISABLED)
        .backgroundColor(Theme.TRANSPARENT)
        .padding({ left: 0, right: 0, top: 6, bottom: 8 })
        .width('100%')
        .onChange((value: string) => {
          this.displayName = value;
        })
      Divider()
        .color(EDIT_BORDER)
        .strokeWidth(1)
      Text('文件名')
        .fontSize(12)
        .fontColor(EDIT_MUTED)
        .width('100%')
        .margin({ top: 16 })
      TextInput({ text: this.fileName, placeholder: 'frpc.toml' })
        .fontSize(17)
        .fontFamily('monospace')
        .fontColor(EDIT_TEXT)
        .placeholderColor(EDIT_DISABLED)
        .backgroundColor(Theme.TRANSPARENT)
        .padding({ left: 0, right: 0, top: 6, bottom: 8 })
        .width('100%')
        .onChange((value: string) => {
          this.fileName = value;
        })
      Text('文件名仅支持安全的 .toml 路径组件')
        .fontSize(12)
        .fontColor(EDIT_DISABLED)
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  private EditorCard() {
    Column() {
      Row() {
        Text('TOML 原文')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(EDIT_TEXT)
          .layoutWeight(1)
        Text('验证')
          .fontSize(13)
          .fontColor(EDIT_ACCENT)
          .onClick(() => {
            this.validateDraft(true);
          })
      }
      .width('100%')
      TextArea({ text: this.content, placeholder: '在此输入 FRP TOML 配置' })
        .fontSize(13)
        .fontFamily('monospace')
        .wordBreak(WordBreak.BREAK_ALL)
        .fontColor(EDIT_TEXT)
        .placeholderColor(EDIT_DISABLED)
        .backgroundColor(EDIT_SURFACE_ALT)
        .border({ width: 1, color: EDIT_BORDER })
        .borderRadius(10)
        .height(320)
        .width('100%')
        .margin({ top: 10 })
        .onChange((value: string) => {
          this.content = value;
          this.validationText = '内容已修改，尚未验证';
          this.validationColor = EDIT_MUTED;
        })
      Text('验证器会检查文件名、基本 TOML 结构以及 frpc/frps 必需字段。')
        .fontSize(12)
        .fontColor(EDIT_DISABLED)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  private ValidationCard() {
    Column() {
      Row() {
        Text('验证结果')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(EDIT_TEXT)
          .layoutWeight(1)
        Text(this.validationText)
          .fontSize(13)
          .fontColor(this.validationColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      if (this.validationWarnings !== '') {
        Text(this.validationWarnings)
          .fontSize(12)
          .fontColor(Theme.STATUS_CONNECTING)
          .lineHeight(18)
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  private ActionCard() {
    Column() {
      Row() {
        Button('复制原文')
          .fontSize(13)
          .fontColor(EDIT_ACCENT)
          .backgroundColor(EDIT_SURFACE_ALT)
          .height(42)
          .layoutWeight(1)
          .borderRadius(10)
          .onClick(() => {
            this.copyContent();
          })
        Button('复制配置')
          .fontSize(13)
          .fontColor(EDIT_ACCENT)
          .backgroundColor(EDIT_SURFACE_ALT)
          .height(42)
          .layoutWeight(1)
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick(() => {
            this.openCopyDialog();
          })
      }
      .width('100%')
      Row() {
        Button('导出')
          .fontSize(13)
          .fontColor(EDIT_ACCENT)
          .backgroundColor(EDIT_SURFACE_ALT)
          .height(42)
          .layoutWeight(1)
          .borderRadius(10)
          .onClick(() => {
            this.exportConfig();
          })
        Button('清除日志')
          .fontSize(13)
          .fontColor(EDIT_ACCENT)
          .backgroundColor(EDIT_SURFACE_ALT)
          .height(42)
          .layoutWeight(1)
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick(() => {
            this.clearLog();
          })
      }
      .width('100%')
      .margin({ top: 8 })
      if (this.isNew) {
        Button('选择模板')
          .fontSize(13)
          .fontColor(EDIT_ACCENT)
          .backgroundColor(EDIT_SURFACE_ALT)
          .height(42)
          .width('100%')
          .borderRadius(10)
          .margin({ top: 8 })
          .onClick(() => {
            this.templateDialogController.open();
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  @Builder
  private DangerCard() {
    Column() {
      Text('删除会同时清除该配置的 FRP 日志，运行中的配置不能删除。')
        .fontSize(13)
        .fontColor(EDIT_MUTED)
        .lineHeight(20)
        .width('100%')
      Button('删除配置')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(EDIT_DANGER)
        .backgroundColor(EDIT_DANGER_BACKGROUND)
        .height(46)
        .width('100%')
        .border({ width: 1, color: EDIT_DANGER })
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.askDelete();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(EDIT_SURFACE)
    .border({ width: 1, color: EDIT_BORDER })
    .borderRadius(16)
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(32)
          .fontColor(Color.White)
          .width(42)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onBackPress();
          })
        Text(this.isNew ? '新建 FRP 配置' : '编辑 FRP 配置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('保存')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EDIT_ACCENT)
          .padding({ left: 8, right: 12, top: 12, bottom: 12 })
          .onClick(() => {
            this.saveAndBack();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(EDIT_TOOLBAR)
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          this.HeaderCard()
          Column() {
            this.IdentityCard()
          }
          .width('100%')
          .margin({ top: 10 })
          Row() {
            Text('自启动')
              .fontSize(16)
              .fontColor(EDIT_TEXT)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoStart })
              .selectedColor(EDIT_ACCENT)
              .onChange((value: boolean) => {
                this.autoStart = value;
              })
          }
          .width('100%')
          .padding(16)
          .margin({ top: 10 })
          .backgroundColor(EDIT_SURFACE)
          .border({ width: 1, color: EDIT_BORDER })
          .borderRadius(16)
          Column() {
            this.EditorCard()
          }
          .width('100%')
          .margin({ top: 10 })
          Column() {
            this.ValidationCard()
          }
          .width('100%')
          .margin({ top: 10 })
          Column() {
            this.ActionCard()
          }
          .width('100%')
          .margin({ top: 10 })
          if (!this.isNew && this.config !== undefined) {
            Column() {
              this.DangerCard()
            }
            .width('100%')
            .margin({ top: 10 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32, top: 12 })
        .backgroundColor(EDIT_BACKGROUND)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(EDIT_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EDIT_BACKGROUND)
  }
}
