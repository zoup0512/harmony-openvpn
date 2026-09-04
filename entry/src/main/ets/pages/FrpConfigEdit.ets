/**
 * FRP configuration editor.
 *
 * The page keeps the existing FRP configuration CRUD flow while exposing a
 * light form editor for the conservative frpc subset and a full TOML editor.
 */

import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { socket } from '@kit.NetworkKit';
import {
  FrpClientFormDraft,
  FrpFormCodec,
  FrpFormParseResult,
  FrpFormValidationResult,
  FrpTunnelDraft,
  FrpTunnelType
} from '../core/FrpFormCodec';
import { FrpConfigTemplate, FrpQuickTemplate, FrpTemplateManager } from '../core/FrpTemplateManager';
import { FrpConfig } from '../core/FrpConfig';
import { FrpConfigManager } from '../core/FrpConfigManager';
import { FrpType, parseFrpType } from '../core/FrpType';
import { FrpValidator, FrpValidationResult } from '../core/FrpValidator';
import { FrpLogStore } from '../core/FrpLogStore';
import { FrpStatus } from '../core/FrpStatus';
import { FileUtil } from '../common/FileUtil';
import { Theme } from '../common/Theme';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { ConfirmDialog, ConfirmDialogModel } from '../components/ConfirmDialog';
import { FrpTemplateDialog } from '../components/dialogs/FrpTemplateDialog';
import { showSingleChoice } from '../components/settings/SettingsCommon';

interface FrpEditRouteParams {
  uuid?: string;
  type?: string;
  new?: boolean;
  templateFileName?: string;
}

export type FrpExportHandler = (config: FrpConfig, content: string) => void;

enum FrpEditMode {
  FORM = 'form',
  TOML = 'toml'
}

class FrpQuickTemplateRow {
  first: FrpQuickTemplate;
  second?: FrpQuickTemplate;

  constructor(first: FrpQuickTemplate, second?: FrpQuickTemplate) {
    this.first = first;
    this.second = second;
  }
}

const PAGE_BACKGROUND: string = Theme.FRP_PAGE_BG;
const CARD_BACKGROUND: string = Theme.FRP_CARD_BG;
const INPUT_BACKGROUND: string = Theme.FRP_INPUT_BG;
const BORDER_COLOR: string = Theme.FRP_BORDER;
const PRIMARY_TEXT: string = Theme.FRP_TEXT_PRIMARY;
const SECONDARY_TEXT: string = Theme.FRP_TEXT_SECONDARY;
const ACCENT_COLOR: string = Theme.FRP_ACCENT;
const ACTION_BACKGROUND: string = Theme.FRP_ACTION_BG;
const DANGER_COLOR: string = Theme.FRP_DANGER;
const DANGER_BACKGROUND: string = Theme.FRP_DANGER_BG;
const TOML_BACKGROUND: string = Theme.FRP_TOML_BG;
const TOML_TEXT: string = Theme.FRP_TOML_TEXT;

@Entry
@Component
struct FrpConfigEdit {
  @State private fileName: string = '';
  @State private displayName: string = '';
  @State private content: string = '';
  @State private autoStart: boolean = false;
  @State private formDirty: boolean = false;
  @State private formContentDirty: boolean = false;
  @State private configType: FrpType = FrpType.FRPC;
  @State private editMode: FrpEditMode = FrpEditMode.TOML;
  @State private formDraft: FrpClientFormDraft = FrpFormCodec.createDefaultDraft();
  @State private quickTemplates: FrpQuickTemplate[] = [];
  @State private selectedQuickTemplate: string = '';
  @State private tokenVisible: boolean = false;
  @State private testBusy: boolean = false;
  @State private validationText: string = '尚未验证';
  @State private validationColor: string = SECONDARY_TEXT;
  @State private validationWarnings: string = '';
  @State private loaded: boolean = false;
  @State private isNew: boolean = false;
  @State private renderTick: number = 0;

  private config?: FrpConfig = undefined;
  private routeTemplate?: string = undefined;
  private initialContent: string = '';
  private exportHandler?: FrpExportHandler = undefined;
  private overwriteTemplate?: FrpQuickTemplate = undefined;
  private pendingTemplateType?: FrpType = undefined;
  private pendingTemplate?: FrpConfigTemplate = undefined;
  private copyDialogModel: InputDialogModel = new InputDialogModel();
  private copyDialogController: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.copyDialogModel, darkMode: false }),
    autoCancel: true,
    customStyle: true
  });
  private deleteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.deleteDialogModel, darkMode: false }),
    autoCancel: true,
    customStyle: true
  });
  private overwriteDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private overwriteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.overwriteDialogModel, darkMode: false }),
    autoCancel: true,
    customStyle: true
  });
  private discardDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private discardDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.discardDialogModel, darkMode: false }),
    autoCancel: true,
    customStyle: true
  });
  private templateApplyDialogModel: ConfirmDialogModel = new ConfirmDialogModel();
  private templateApplyDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({ model: this.templateApplyDialogModel, darkMode: false }),
    autoCancel: true,
    customStyle: true
  });
  private templateDialogController: CustomDialogController = new CustomDialogController({
    builder: FrpTemplateDialog({
      darkMode: false,
      onSelected: (type: FrpType, template?: FrpConfigTemplate) => {
        this.requestTemplateApply(type, template);
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
    this.quickTemplates = FrpTemplateManager.quickTemplates();

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
      this.initialContent = this.content;
      this.formDirty = false;
      this.formContentDirty = false;
      this.isNew = false;
      this.loaded = true;
      this.loadExistingMode();
      return;
    }

    this.isNew = params !== undefined && params !== null && params.new === true;
    let requestedType = params === undefined || params === null ? undefined : params.type;
    let parsed = requestedType === undefined ? undefined : parseFrpType(requestedType);
    this.configType = parsed === undefined ? FrpType.FRPC : parsed;
    this.fileName = this.configType === FrpType.FRPC ? 'frpc.toml' : 'frps.toml';
    this.displayName = '';
    this.autoStart = false;
    this.content = '';
    this.initialContent = '';
    this.formDirty = false;
    this.formContentDirty = false;
    this.loaded = true;
    if (this.routeTemplate !== undefined && this.routeTemplate !== '') {
      let template = FrpTemplateManager.get(this.configType, this.routeTemplate);
      this.applyTemplate(this.configType, template);
    } else {
      this.applyTemplate(this.configType, undefined);
    }
  }

  onBackPress(): boolean {
    if (!this.formDirty) {
      router.back();
      return true;
    }
    this.discardDialogModel.title = '放弃未保存的修改？';
    this.discardDialogModel.message = '当前修改尚未保存，返回后将无法恢复。';
    this.discardDialogModel.cancelText = '继续编辑';
    this.discardDialogModel.confirmText = '放弃修改';
    this.discardDialogModel.dangerous = true;
    this.discardDialogModel.onConfirm = () => {
      router.back();
    };
    this.discardDialogController.open();
    return true;
  }

  private loadExistingMode(): void {
    this.selectedQuickTemplate = '';
    this.formContentDirty = false;
    if (this.configType !== FrpType.FRPC) {
      this.editMode = FrpEditMode.TOML;
      this.formDirty = false;
      this.markUnverified();
      return;
    }
    let parsed = FrpFormCodec.parse(this.content);
    if (parsed.compatible && parsed.draft !== undefined) {
      this.formDraft = parsed.draft;
      this.editMode = FrpEditMode.FORM;
    } else {
      this.editMode = FrpEditMode.TOML;
    }
    this.formDirty = false;
    this.markUnverified();
  }

  private applyTemplate(type: FrpType, template?: FrpConfigTemplate, userInitiated: boolean = false): void {
    this.configType = type;
    this.formContentDirty = false;
    this.selectedQuickTemplate = '';
    this.tokenVisible = false;
    if (template === undefined) {
      this.fileName = type === FrpType.FRPC ? 'frpc.toml' : 'frps.toml';
      if (this.isNew || this.displayName.trim() === '') {
        this.displayName = '';
      }
      if (type === FrpType.FRPC) {
        this.formDraft = FrpFormCodec.createDefaultDraft();
        this.content = FrpFormCodec.serialize(this.formDraft);
        this.formContentDirty = false;
        this.editMode = FrpEditMode.FORM;
      } else {
        this.content = '';
        this.editMode = FrpEditMode.TOML;
      }
    } else {
      this.fileName = template.fileName;
      if (this.isNew || this.displayName.trim() === '') {
        this.displayName = template.displayName;
      }
      this.content = FrpTemplateManager.read(template);
      if (type === FrpType.FRPC) {
        let parsed = FrpFormCodec.parse(this.content);
        if (parsed.compatible && parsed.draft !== undefined) {
          this.formDraft = parsed.draft;
          this.formContentDirty = false;
          this.editMode = FrpEditMode.FORM;
        } else {
          this.editMode = FrpEditMode.TOML;
        }
      } else {
        this.editMode = FrpEditMode.TOML;
      }
    }
    if (userInitiated) {
      this.markChanged();
    } else {
      this.initialContent = this.content;
      this.formDirty = false;
      this.validationText = template === undefined ? '尚未验证' : '已载入模板，尚未保存';
      this.validationColor = template === undefined ? SECONDARY_TEXT : ACCENT_COLOR;
      this.validationWarnings = '';
    }
  }

  private requestTemplateApply(type: FrpType, template?: FrpConfigTemplate): void {
    this.pendingTemplateType = type;
    this.pendingTemplate = template;
    if (this.content === '' || (!this.formDirty && this.content === this.initialContent)) {
      this.commitTemplateApply();
      return;
    }
    this.templateApplyDialogModel.title = '覆盖当前草稿？';
    this.templateApplyDialogModel.message = '应用模板将替换当前配置内容。';
    this.templateApplyDialogModel.cancelText = '取消';
    this.templateApplyDialogModel.confirmText = '应用模板';
    this.templateApplyDialogModel.dangerous = false;
    this.templateApplyDialogModel.onCancel = () => {
      this.clearPendingTemplate();
    };
    this.templateApplyDialogModel.onConfirm = () => {
      this.commitTemplateApply();
    };
    this.templateApplyDialogController.open();
  }

  private commitTemplateApply(): void {
    let type = this.pendingTemplateType;
    let template = this.pendingTemplate;
    this.clearPendingTemplate();
    if (type === undefined) {
      return;
    }
    this.applyTemplate(type, template, true);
  }

  private clearPendingTemplate(): void {
    this.pendingTemplateType = undefined;
    this.pendingTemplate = undefined;
  }

  private applyQuickTemplate(template: FrpQuickTemplate): void {
    if (template.id === '') {
      this.selectedQuickTemplate = '';
      this.markChanged();
      return;
    }
    if (this.content !== '' && this.content !== template.content) {
      this.overwriteTemplate = template;
      this.overwriteDialogModel.title = '覆盖当前内容？';
      this.overwriteDialogModel.message = `将使用“${template.label}”模板替换当前 TOML 内容。`;
      this.overwriteDialogModel.cancelText = '取消';
      this.overwriteDialogModel.confirmText = '覆盖';
      this.overwriteDialogModel.dangerous = false;
      this.overwriteDialogModel.onConfirm = () => {
        this.commitQuickTemplate();
      };
      this.overwriteDialogController.open();
      return;
    }
    this.overwriteTemplate = template;
    this.commitQuickTemplate();
  }

  private commitQuickTemplate(): void {
    let template = this.overwriteTemplate;
    if (template === undefined) {
      return;
    }
    this.content = template.content;
    if (template.formCompatible) {
      let parsed: FrpFormParseResult = FrpFormCodec.parse(this.content);
      if (parsed.compatible && parsed.draft !== undefined) {
        this.formDraft = parsed.draft;
      }
    }
    this.formContentDirty = false;
    if (this.displayName.trim() === '') {
      this.displayName = template.label;
    }
    this.selectedQuickTemplate = template.id;
    this.editMode = FrpEditMode.TOML;
    this.markChanged();
    this.overwriteTemplate = undefined;
  }

  private draftConfig(name: string = this.fileName): FrpConfig {
    if (this.config !== undefined && name === this.config.fileName) {
      return this.config;
    }
    return new FrpConfig(this.configType, name, this.displayName);
  }

  private markUnverified(): void {
    this.validationText = '尚未验证';
    this.validationColor = SECONDARY_TEXT;
    this.validationWarnings = '';
  }

  private markChanged(): void {
    this.formDirty = true;
    this.markUnverified();
  }

  private markFormChanged(): void {
    this.formContentDirty = true;
    this.markChanged();
  }

  private setValidationFailure(message: string, warnings: string[] = [], showToast: boolean = false): void {
    this.validationText = message === '' ? '验证失败' : message;
    this.validationColor = Theme.STATUS_ERROR;
    this.validationWarnings = warnings.join('\n');
    if (showToast) {
      promptAction.showToast({ message: this.validationText });
    }
  }

  private setValidationResult(result: FrpValidationResult, showToast: boolean): void {
    if (result.valid) {
      this.validationText = result.warnings.length > 0 ? '验证通过（有警告）' : '验证通过';
      this.validationColor = result.warnings.length > 0 ? Theme.STATUS_CONNECTING : Theme.STATUS_SUCCESS;
      this.validationWarnings = result.warnings.join('\n');
    } else {
      this.validationText = result.message === '' ? '验证失败' : result.message;
      this.validationColor = Theme.STATUS_ERROR;
      this.validationWarnings = result.warnings.join('\n');
    }
    if (showToast) {
      promptAction.showToast({ message: this.validationText });
    }
  }

  private prepareFormContent(showToast: boolean): boolean {
    if (this.editMode !== FrpEditMode.FORM) {
      return true;
    }
    let formValidation: FrpFormValidationResult = FrpFormCodec.validate(this.formDraft);
    if (!formValidation.valid) {
      this.setValidationFailure(formValidation.message, [], showToast);
      return false;
    }
    if (!this.formContentDirty) {
      return true;
    }
    try {
      this.content = FrpFormCodec.serialize(this.formDraft);
      return true;
    } catch (error) {
      let message = (error as Error).message;
      if (message === '') {
        message = '表单序列化失败';
      }
      this.setValidationFailure(message, [], showToast);
      return false;
    }
  }

  private validateDraft(showToast: boolean): FrpValidationResult {
    if (this.editMode === FrpEditMode.FORM) {
      if (!this.prepareFormContent(showToast)) {
        let formValidation: FrpFormValidationResult = FrpFormCodec.validate(this.formDraft);
        return new FrpValidationResult(false, [formValidation.message], []);
      }
    }
    let safeName = FrpValidator.normalizeFileName(this.fileName);
    let candidate = this.draftConfig(safeName);
    let result = FrpValidator.validateConfig(candidate, this.content);
    this.setValidationResult(result, showToast);
    return result;
  }

  private rollbackExistingSave(config: FrpConfig, originalFileName: string,
    originalDisplayName: string, originalAutoStart: boolean, originalContent: string): void {
    let restoredConfig = config;
    try {
      if (restoredConfig.fileName !== originalFileName) {
        restoredConfig = FrpConfigManager.rename(restoredConfig, originalFileName);
        this.config = restoredConfig;
      }
    } catch (renameError) {
      // Keep the in-memory draft when the best-effort file rollback fails.
    }
    restoredConfig.displayName = originalDisplayName;
    restoredConfig.autoStart = originalAutoStart;
    try {
      FrpConfigManager.save(restoredConfig, originalContent);
    } catch (restoreError) {
      // The original file is left untouched when restoration itself fails.
    }
  }

  private saveDraft(): boolean {
    if (!this.loaded) {
      return false;
    }
    if (this.editMode === FrpEditMode.FORM && !this.prepareFormContent(true)) {
      return false;
    }

    let safeName = FrpValidator.normalizeFileName(this.fileName);
    let nameValidation = FrpValidator.validateFileName(safeName);
    if (!nameValidation.valid) {
      this.setValidationFailure(nameValidation.message, nameValidation.warnings, true);
      return false;
    }
    let candidate = new FrpConfig(this.configType, safeName, this.displayName.trim());
    let validation = FrpValidator.validateConfig(candidate, this.content);
    if (!validation.valid) {
      this.setValidationFailure(validation.message, validation.warnings, true);
      return false;
    }

    let existingConfig: FrpConfig | undefined = this.config;
    let originalFileName: string = '';
    let originalDisplayName: string = '';
    let originalAutoStart: boolean = false;
    let originalContent: string = '';
    if (!this.isNew && existingConfig !== undefined) {
      originalFileName = existingConfig.fileName;
      originalDisplayName = existingConfig.displayName;
      originalAutoStart = existingConfig.autoStart;
      originalContent = FrpConfigManager.read(existingConfig);
    }

    try {
      if (this.isNew || existingConfig === undefined) {
        let created = FrpConfigManager.importContent(this.configType, safeName, this.content,
          this.displayName.trim());
        if (!FrpConfigManager.setAutoStart(created, this.autoStart)) {
          FrpConfigManager.remove(created);
          throw new Error('配置元数据保存失败');
        }
        this.config = created;
        this.isNew = false;
        this.fileName = created.fileName;
        this.loaded = true;
      } else {
        if (existingConfig.fileName !== safeName) {
          existingConfig = FrpConfigManager.rename(existingConfig, safeName);
          this.config = existingConfig;
        }
        existingConfig.displayName = this.displayName.trim();
        let saved = FrpConfigManager.save(existingConfig, this.content);
        if (!saved.valid) {
          this.rollbackExistingSave(existingConfig, originalFileName, originalDisplayName,
            originalAutoStart, originalContent);
          this.setValidationFailure(saved.message, saved.warnings, true);
          return false;
        }
        if (!FrpConfigManager.setAutoStart(existingConfig, this.autoStart)) {
          throw new Error('配置元数据保存失败');
        }
      }
    } catch (error) {
      if (!this.isNew && existingConfig !== undefined) {
        this.rollbackExistingSave(existingConfig, originalFileName, originalDisplayName,
          originalAutoStart, originalContent);
      }
      let message = (error as Error).message;
      if (message === '') {
        message = '配置保存失败';
      }
      this.setValidationFailure(message, [], true);
      return false;
    }
    this.validationText = validation.warnings.length > 0 ? '已保存（有警告）' : '已保存';
    this.validationColor = validation.warnings.length > 0 ? Theme.STATUS_CONNECTING : Theme.STATUS_SUCCESS;
    this.validationWarnings = validation.warnings.join('\n');
    this.initialContent = this.content;
    this.formDirty = false;
    this.formContentDirty = false;
    try {
      promptAction.showToast({ message: this.validationText });
    } catch (toastError) {
      // A notification failure must not change the already committed configuration.
    }
    return true;
  }

  private saveAndBack(): void {
    if (this.saveDraft()) {
      router.back();
    }
  }

  private copyContent(): void {
    if (this.editMode === FrpEditMode.FORM && !this.prepareFormContent(true)) {
      return;
    }
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
      if (this.editMode === FrpEditMode.FORM && !this.prepareFormContent(true)) {
        return;
      }
      if (this.config === undefined) {
        promptAction.showToast({ message: '请先保存新配置，再复制配置' });
        return;
      }
      try {
        let normalizedName = FrpValidator.normalizeFileName(value);
        let copy = FrpConfigManager.importContent(this.config.type, normalizedName, this.content, this.displayName);
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
    if (this.editMode === FrpEditMode.FORM && !this.prepareFormContent(true)) {
      return;
    }
    if (this.config === undefined) {
      promptAction.showToast({ message: '请先保存配置，再导出' });
      return;
    }
    let normalizedName = FrpValidator.normalizeFileName(this.fileName);
    let nameValidation = FrpValidator.validateFileName(normalizedName);
    if (!nameValidation.valid) {
      this.setValidationFailure(nameValidation.message, nameValidation.warnings, true);
      return;
    }
    if (this.exportHandler !== undefined) {
      let exportConfig = new FrpConfig(this.config.type, normalizedName, this.displayName);
      exportConfig.autoStart = this.autoStart;
      this.exportHandler(exportConfig, this.content);
      return;
    }
    let host = this.getUIContext().getHostContext();
    FileUtil.saveText(normalizedName, this.content, '.toml', host as common.UIAbilityContext).then(() => {
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

  private switchMode(mode: FrpEditMode): void {
    if (mode === this.editMode) {
      return;
    }
    if (this.configType === FrpType.FRPS && mode === FrpEditMode.FORM) {
      promptAction.showToast({ message: 'frps 仅支持 TOML 编辑' });
      return;
    }
    if (mode === FrpEditMode.TOML) {
      if (!this.prepareFormContent(true)) {
        return;
      }
      this.editMode = FrpEditMode.TOML;
      this.selectedQuickTemplate = '';
      return;
    }

    let parsed: FrpFormParseResult = FrpFormCodec.parse(this.content);
    if (!parsed.compatible || parsed.draft === undefined) {
      let reason = parsed.message === '' ? '当前内容不兼容表单模式' : parsed.message;
      promptAction.showToast({ message: `无法切换表单：${reason}` });
      return;
    }
    this.formDraft = parsed.draft;
    this.formContentDirty = false;
    this.editMode = FrpEditMode.FORM;
    this.selectedQuickTemplate = '';
    this.markUnverified();
  }

  private updateServerAddr(value: string): void {
    this.formDraft.serverAddr = value;
    this.renderTick++;
    this.markFormChanged();
  }

  private updateServerPort(value: string): void {
    this.formDraft.serverPort = value;
    this.renderTick++;
    this.markFormChanged();
  }

  private updateToken(value: string): void {
    this.formDraft.token = value;
    this.renderTick++;
    this.markFormChanged();
  }

  private updateUser(value: string): void {
    this.formDraft.user = value;
    this.renderTick++;
    this.markFormChanged();
  }

  private updateTunnel(index: number, field: string, value: string): void {
    let tunnel = this.formDraft.tunnels[index];
    if (field === 'name') {
      tunnel.name = value;
    } else if (field === 'localIP') {
      tunnel.localIP = value;
    } else if (field === 'localPort') {
      tunnel.localPort = value;
    } else if (field === 'remotePort') {
      tunnel.remotePort = value;
    }
    this.formDraft.tunnels = this.formDraft.tunnels.slice();
    this.renderTick++;
    this.markFormChanged();
  }

  private updateTunnelType(index: number, type: FrpTunnelType): void {
    this.formDraft.tunnels[index].type = type;
    this.formDraft.tunnels = this.formDraft.tunnels.slice();
    this.renderTick++;
    this.markFormChanged();
  }

  private removeTunnel(index: number): void {
    if (this.formDraft.tunnels.length <= 1) {
      promptAction.showToast({ message: '至少需要一个隧道' });
      return;
    }
    let tunnels = this.formDraft.tunnels.slice();
    tunnels.splice(index, 1);
    this.formDraft.tunnels = tunnels;
    this.renderTick++;
    this.markFormChanged();
  }

  private addTunnel(): void {
    let id = FrpFormCodec.nextTunnelId(this.formDraft);
    let tunnels = this.formDraft.tunnels.slice();
    tunnels.push(new FrpTunnelDraft(id, `tunnel-${tunnels.length + 1}`, FrpTunnelType.TCP,
      '127.0.0.1', '8080', '18080'));
    this.formDraft.tunnels = tunnels;
    this.renderTick++;
    this.markFormChanged();
  }

  private async runTcpTest(): Promise<void> {
    let host = this.formDraft.serverAddr.trim();
    let portText = this.formDraft.serverPort;
    let port = Number(portText);
    if (host === '') {
      promptAction.showToast({ message: '服务器地址不能为空' });
      return;
    }
    if (!/^[1-9][0-9]*$/.test(portText) || !isFinite(port) || port < 1 || port > 65535 || Math.floor(port) !== port) {
      promptAction.showToast({ message: '服务器端口必须是 1-65535 的整数' });
      return;
    }

    this.testBusy = true;
    let succeeded = false;
    let failureMessage = '';
    let tcp = socket.constructTCPSocketInstance();
    try {
      let family = host.indexOf(':') !== -1 ? 2 : 1;
      await tcp.connect({ address: { address: host, port: port, family: family }, timeout: 5000 });
      succeeded = true;
    } catch (error) {
      failureMessage = (error as Error).message;
      if (failureMessage === '') {
        failureMessage = '连接被拒绝或超时';
      }
    } finally {
      try {
        await tcp.close();
      } catch (closeError) {
        // The socket may already be closed after a failed connect.
      }
      this.testBusy = false;
    }
    if (succeeded) {
      promptAction.showToast({ message: 'TCP 端口可达；未验证 FRP 鉴权' });
    } else {
      promptAction.showToast({ message: `TCP 连接失败：${failureMessage}` });
    }
  }

  private testConnection(): void {
    this.runTcpTest().catch((error: Error) => {
      this.testBusy = false;
      let message = error.message;
      promptAction.showToast({ message: message === '' ? 'TCP 连接失败' : `TCP 连接失败：${message}` });
    });
  }

  private quickTemplateRows(): FrpQuickTemplateRow[] {
    let entries = this.quickTemplates.slice();
    entries.push(new FrpQuickTemplate('', '自定义', '', false));
    let rows: FrpQuickTemplateRow[] = [];
    for (let i = 0; i < entries.length; i += 2) {
      let second: FrpQuickTemplate | undefined = i + 1 < entries.length ? entries[i + 1] : undefined;
      rows.push(new FrpQuickTemplateRow(entries[i], second));
    }
    return rows;
  }

  @Builder
  private HeaderBar() {
    Row() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(22)
          .height(22)
          .fillColor(PRIMARY_TEXT)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(CARD_BACKGROUND)
      .borderRadius(20)
      .onClick(() => {
        this.onBackPress();
      })
      Blank()
        .layoutWeight(1)
      Text(this.isNew ? '新增配置' : '编辑配置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(PRIMARY_TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(3)
        .textAlign(TextAlign.Center)
      Blank()
        .layoutWeight(1)
      Row() {
        Image($r('app.media.ic_save'))
          .width(21)
          .height(21)
          .fillColor(Color.White)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ACCENT_COLOR)
      .borderRadius(20)
      .onClick(() => {
        this.saveAndBack();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private ModeSwitch() {
    Row() {
      Button('表单')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.editMode === FrpEditMode.FORM ? Color.White : SECONDARY_TEXT)
        .backgroundColor(this.editMode === FrpEditMode.FORM ? ACCENT_COLOR : INPUT_BACKGROUND)
        .layoutWeight(1)
        .height(36)
        .borderRadius(Theme.FRP_CHIP_RADIUS)
        .onClick(() => {
          this.switchMode(FrpEditMode.FORM);
        })
      Button('TOML')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.editMode === FrpEditMode.TOML ? Color.White : SECONDARY_TEXT)
        .backgroundColor(this.editMode === FrpEditMode.TOML ? ACCENT_COLOR : INPUT_BACKGROUND)
        .layoutWeight(1)
        .height(36)
        .borderRadius(Theme.FRP_CHIP_RADIUS)
        .margin({ left: 4 })
        .onClick(() => {
          this.switchMode(FrpEditMode.TOML);
        })
    }
    .width('100%')
    .padding(4)
    .backgroundColor(INPUT_BACKGROUND)
    .borderRadius(Theme.FRP_CHIP_RADIUS)
  }

  @Builder
  private NameCard() {
    Column() {
      Text('配置名')
        .fontSize(13)
        .fontColor(SECONDARY_TEXT)
        .width('100%')
      TextInput({ text: this.displayName, placeholder: '例如：家里 NAS' })
        .fontSize(16)
        .fontColor(PRIMARY_TEXT)
        .placeholderColor(SECONDARY_TEXT)
        .backgroundColor(INPUT_BACKGROUND)
        .borderRadius(Theme.FRP_INPUT_RADIUS)
        .padding({ left: 12, right: 12 })
        .height(46)
        .width('100%')
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.displayName = value;
          this.markChanged();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LabeledInput(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor(SECONDARY_TEXT)
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(16)
        .fontColor(PRIMARY_TEXT)
        .placeholderColor(SECONDARY_TEXT)
        .backgroundColor(INPUT_BACKGROUND)
        .borderRadius(Theme.FRP_INPUT_RADIUS)
        .padding({ left: 12, right: 12 })
        .height(44)
        .width('100%')
        .margin({ top: 6 })
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PortInput(label: string, value: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor(SECONDARY_TEXT)
        .width('100%')
      TextInput({ text: value, placeholder: '1-65535' })
        .type(InputType.Number)
        .fontSize(16)
        .fontColor(PRIMARY_TEXT)
        .placeholderColor(SECONDARY_TEXT)
        .backgroundColor(INPUT_BACKGROUND)
        .borderRadius(Theme.FRP_INPUT_RADIUS)
        .padding({ left: 12, right: 12 })
        .height(44)
        .width('100%')
        .margin({ top: 6 })
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ServerCard() {
    Column() {
      this.LabeledInput('服务器地址', this.formDraft.serverAddr, '例如 frp.example.com', (value: string) => {
        this.updateServerAddr(value);
      })
      Column() {
        this.PortInput('服务器端口', this.formDraft.serverPort, (value: string) => {
          this.updateServerPort(value);
        })
      }
      .width('100%')
      .margin({ top: 12 })
      Text('鉴权 Token')
        .fontSize(13)
        .fontColor(SECONDARY_TEXT)
        .width('100%')
        .margin({ top: 12 })
      Row() {
        TextInput({ text: this.formDraft.token, placeholder: '留空表示不设置' })
          .type(this.tokenVisible ? InputType.Normal : InputType.Password)
          .fontSize(16)
          .fontColor(PRIMARY_TEXT)
          .placeholderColor(SECONDARY_TEXT)
          .backgroundColor(INPUT_BACKGROUND)
          .borderRadius(Theme.FRP_INPUT_RADIUS)
          .padding({ left: 12, right: 12 })
          .height(44)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.updateToken(value);
          })
        Image($r('app.media.ic_view'))
          .width(21)
          .height(21)
          .fillColor(SECONDARY_TEXT)
          .margin({ left: 10, right: 12 })
          .onClick(() => {
            this.tokenVisible = !this.tokenVisible;
          })
      }
      .width('100%')
      .height(44)
      .backgroundColor(INPUT_BACKGROUND)
      .borderRadius(Theme.FRP_INPUT_RADIUS)
      .margin({ top: 6 })
      Column() {
        this.LabeledInput('用户（可选）', this.formDraft.user, 'frps 若配置了 user 则填写', (value: string) => {
          this.updateUser(value);
        })
      }
      .width('100%')
      .margin({ top: 12 })
      Button(this.testBusy ? '测试中…' : '测试连接')
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(ACCENT_COLOR)
        .height(38)
        .borderRadius(Theme.FRP_CHIP_RADIUS)
        .margin({ top: 14 })
        .enabled(!this.testBusy)
        .onClick(() => {
          this.testConnection();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  @Builder
  private TunnelCard(tunnel: FrpTunnelDraft, index: number) {
    Column() {
      Row() {
        Text(`隧道 ${index + 1}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_TEXT)
          .layoutWeight(1)
        Text('×')
          .fontSize(22)
          .fontColor(DANGER_COLOR)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .backgroundColor(DANGER_BACKGROUND)
          .borderRadius(16)
          .onClick(() => {
            this.removeTunnel(index);
          })
      }
      .width('100%')
      Column() {
        this.LabeledInput('名称', tunnel.name, '例如 ssh', (value: string) => {
          this.updateTunnel(index, 'name', value);
        })
      }
      .width('100%')
      .margin({ top: 14 })
      Row() {
        Text('类型')
          .fontSize(13)
          .fontColor(SECONDARY_TEXT)
          .layoutWeight(1)
        Text(this.renderTick >= 0 ? tunnel.type : '')
          .fontSize(15)
          .fontColor(ACCENT_COLOR)
        Text('›')
          .fontSize(22)
          .fontColor(SECONDARY_TEXT)
          .margin({ left: 8 })
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor(INPUT_BACKGROUND)
      .borderRadius(Theme.FRP_INPUT_RADIUS)
      .margin({ top: 12 })
      .onClick(() => {
        let selected = tunnel.type === FrpTunnelType.TCP ? 0 : 1;
        showSingleChoice('隧道类型', ['tcp', 'udp'], selected, (choice: number) => {
          this.updateTunnelType(index, choice === 0 ? FrpTunnelType.TCP : FrpTunnelType.UDP);
        });
      })
      Column() {
        this.LabeledInput('本地地址', tunnel.localIP, '例如 127.0.0.1', (value: string) => {
          this.updateTunnel(index, 'localIP', value);
        })
      }
      .width('100%')
      .margin({ top: 12 })
      Row() {
        Column() {
          this.PortInput('本地端口', tunnel.localPort, (value: string) => {
            this.updateTunnel(index, 'localPort', value);
          })
        }
        .layoutWeight(1)
        Column() {
          this.PortInput('远程端口', tunnel.remotePort, (value: string) => {
            this.updateTunnel(index, 'remotePort', value);
          })
        }
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  @Builder
  private FormEditor() {
    Column() {
      Text('服务器（frps）')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(PRIMARY_TEXT)
        .width('100%')
        .margin({ top: 18, bottom: 10 })
      this.ServerCard()
      Text(`隧道（${this.formDraft.tunnels.length}）`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(PRIMARY_TEXT)
        .width('100%')
        .margin({ top: 18, bottom: 10 })
      ForEach(this.formDraft.tunnels, (tunnel: FrpTunnelDraft, index: number) => {
        this.TunnelCard(tunnel, index);
      }, (tunnel: FrpTunnelDraft) => `${tunnel.id}`)
      Button('＋ 添加隧道')
        .fontSize(14)
        .fontColor(ACCENT_COLOR)
        .backgroundColor(ACTION_BACKGROUND)
        .height(42)
        .width('100%')
        .borderRadius(Theme.FRP_ACTION_RADIUS)
        .margin({ top: 12 })
        .onClick(() => {
          this.addTunnel();
        })
      Text('提示：表单生成标准 frpc TOML；高级参数（插件/transport 等）请切换到 TOML 模式')
        .fontSize(12)
        .fontColor(SECONDARY_TEXT)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 14 })
    }
    .width('100%')
  }

  @Builder
  private QuickTemplateButton(template: FrpQuickTemplate) {
    Button(template.label)
      .fontSize(13)
      .fontColor(this.selectedQuickTemplate === template.id ? Color.White : PRIMARY_TEXT)
      .backgroundColor(this.selectedQuickTemplate === template.id ? ACCENT_COLOR : CARD_BACKGROUND)
      .height(40)
      .layoutWeight(1)
      .borderRadius(Theme.FRP_BUTTON_RADIUS)
      .border({ width: this.selectedQuickTemplate === template.id ? 0 : 1, color: BORDER_COLOR })
      .onClick(() => {
        this.applyQuickTemplate(template);
      })
  }

  @Builder
  private QuickTemplatesCard() {
    Column() {
      Row() {
        Text('配置模板（常用端口映射）')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_TEXT)
          .layoutWeight(1)
        Text('选择后可继续编辑')
          .fontSize(12)
          .fontColor(SECONDARY_TEXT)
      }
      .width('100%')
      ForEach(this.quickTemplateRows(), (row: FrpQuickTemplateRow) => {
        Row() {
          this.QuickTemplateButton(row.first)
          if (row.second !== undefined) {
            this.QuickTemplateButton(row.second)
          } else {
            Blank()
              .layoutWeight(1)
              .height(40)
          }
        }
        .width('100%')
        .margin({ top: 8 })
      }, (row: FrpQuickTemplateRow) => row.first.id === '' ? 'custom' : row.first.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  @Builder
  private TomlEditor() {
    Column() {
      Row() {
        Text('配置内容（TOML）')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_TEXT)
          .layoutWeight(1)
        Button('验证')
          .fontSize(13)
          .fontColor(ACCENT_COLOR)
          .backgroundColor(ACTION_BACKGROUND)
          .height(34)
          .borderRadius(Theme.FRP_BUTTON_RADIUS)
          .onClick(() => {
            this.validateDraft(true);
          })
      }
      .width('100%')
      TextArea({ text: this.content, placeholder: '在此输入 FRP TOML 配置' })
        .fontSize(13)
        .fontFamily('monospace')
        .wordBreak(WordBreak.BREAK_ALL)
        .fontColor(TOML_TEXT)
        .placeholderColor('#6B8178')
        .backgroundColor(TOML_BACKGROUND)
        .border({ width: 1, color: '#263B33' })
        .borderRadius(Theme.FRP_INPUT_RADIUS)
        .height(360)
        .width('100%')
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.content = value;
          this.selectedQuickTemplate = '';
          this.markChanged();
        })
      Text('TOML 模式保留完整原文能力；切换到表单需要满足支持的字段子集。')
        .fontSize(12)
        .fontColor(SECONDARY_TEXT)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  @Builder
  private ValidationCard() {
    Column() {
      Row() {
        Text('验证结果')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_TEXT)
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
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  @Builder
  private FileAndActionCard() {
    Column() {
      Text('文件与操作')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(PRIMARY_TEXT)
        .width('100%')
      Text('文件名')
        .fontSize(13)
        .fontColor(SECONDARY_TEXT)
        .width('100%')
        .margin({ top: 14 })
      TextInput({ text: this.fileName, placeholder: 'frpc.toml' })
        .fontSize(16)
        .fontFamily('monospace')
        .fontColor(PRIMARY_TEXT)
        .placeholderColor(SECONDARY_TEXT)
        .backgroundColor(INPUT_BACKGROUND)
        .borderRadius(Theme.FRP_INPUT_RADIUS)
        .padding({ left: 12, right: 12 })
        .height(46)
        .width('100%')
        .margin({ top: 6 })
        .onChange((value: string) => {
          this.fileName = value;
          this.markChanged();
        })
      Text('仅支持安全的 .toml 文件名')
        .fontSize(12)
        .fontColor(SECONDARY_TEXT)
        .width('100%')
        .margin({ top: 5 })
      Row() {
        Column() {
          Text('自启动')
            .fontSize(15)
            .fontColor(PRIMARY_TEXT)
            .width('100%')
          Text('保留配置的自启动标记')
            .fontSize(12)
            .fontColor(SECONDARY_TEXT)
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.autoStart })
          .selectedColor(ACCENT_COLOR)
          .onChange((value: boolean) => {
            this.autoStart = value;
            this.markChanged();
          })
      }
      .width('100%')
      .padding({ top: 14, bottom: 2 })
      .alignItems(VerticalAlign.Center)
      Row() {
        Button('复制原文')
          .fontSize(13)
          .fontColor(ACCENT_COLOR)
          .backgroundColor(ACTION_BACKGROUND)
          .height(40)
          .layoutWeight(1)
          .borderRadius(Theme.FRP_BUTTON_RADIUS)
          .onClick(() => {
            this.copyContent();
          })
        Button('复制配置')
          .fontSize(13)
          .fontColor(ACCENT_COLOR)
          .backgroundColor(ACTION_BACKGROUND)
          .height(40)
          .layoutWeight(1)
          .borderRadius(Theme.FRP_BUTTON_RADIUS)
          .margin({ left: 8 })
          .onClick(() => {
            this.openCopyDialog();
          })
      }
      .width('100%')
      .margin({ top: 14 })
      Row() {
        Button('导出')
          .fontSize(13)
          .fontColor(ACCENT_COLOR)
          .backgroundColor(ACTION_BACKGROUND)
          .height(40)
          .layoutWeight(1)
          .borderRadius(Theme.FRP_BUTTON_RADIUS)
          .onClick(() => {
            this.exportConfig();
          })
        Button('清除日志')
          .fontSize(13)
          .fontColor(ACCENT_COLOR)
          .backgroundColor(ACTION_BACKGROUND)
          .height(40)
          .layoutWeight(1)
          .borderRadius(Theme.FRP_BUTTON_RADIUS)
          .margin({ left: 8 })
          .onClick(() => {
            this.clearLog();
          })
      }
      .width('100%')
      .margin({ top: 8 })
      if (this.isNew) {
        Button('更多模板')
          .fontSize(13)
          .fontColor(ACCENT_COLOR)
          .backgroundColor(ACTION_BACKGROUND)
          .height(42)
          .width('100%')
          .borderRadius(Theme.FRP_ACTION_RADIUS)
          .margin({ top: 8 })
          .onClick(() => {
            this.templateDialogController.open();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  @Builder
  private DangerCard() {
    Column() {
      Text('删除会同时清除该配置的 FRP 日志，运行中的配置不能删除。')
        .fontSize(13)
        .fontColor(SECONDARY_TEXT)
        .lineHeight(20)
        .width('100%')
      Button('删除配置')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(DANGER_COLOR)
        .backgroundColor(DANGER_BACKGROUND)
        .height(46)
        .width('100%')
        .border({ width: 1, color: DANGER_COLOR })
        .borderRadius(Theme.FRP_BUTTON_RADIUS)
        .margin({ top: 12 })
        .onClick(() => {
          this.askDelete();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(CARD_BACKGROUND)
    .border({ width: 1, color: BORDER_COLOR })
    .borderRadius(Theme.FRP_CARD_RADIUS)
  }

  build() {
    Column() {
      this.HeaderBar()
      Scroll() {
        Column() {
          if (this.configType === FrpType.FRPC) {
            Column() {
              this.ModeSwitch()
            }
            .width('100%')
            .margin({ top: 4 })
          }
          Column() {
            this.NameCard()
          }
          .width('100%')
          .margin({ top: 14 })
          if (this.configType === FrpType.FRPC && this.editMode === FrpEditMode.FORM) {
            this.FormEditor()
          } else {
            if (this.configType === FrpType.FRPC) {
              this.QuickTemplatesCard()
            }
            Column() {
              this.TomlEditor()
            }
            .width('100%')
            .margin({ top: 12 })
          }
          Column() {
            this.ValidationCard()
          }
          .width('100%')
          .margin({ top: 12 })
          Column() {
            this.FileAndActionCard()
          }
          .width('100%')
          .margin({ top: 12 })
          if (!this.isNew && this.config !== undefined) {
            Column() {
              this.DangerCard()
            }
            .width('100%')
            .margin({ top: 12 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32, top: 4 })
        .backgroundColor(PAGE_BACKGROUND)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(PAGE_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }
}
