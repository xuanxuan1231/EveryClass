import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import type { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { addFormId, buildCardData, removeFormId } from '../cardcommon/CardData';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 记录 formId，供主进程（EntryAbility.onBackground）刷新时枚举。
    const params = want.parameters;
    if (params) {
      const formId = params[formInfo.FormParam.IDENTITY_KEY] as string;
      addFormId(this.context, formId);
    }
    return formBindingData.createFormBindingData(buildCardData(this.context));
  }

  onCastToNormalForm(formId: string): void {
    // 常态卡片无需特殊处理。
  }

  onUpdateForm(formId: string): void {
    // 系统按 form_config.json 的 scheduledUpdateTime / updateDuration 触发；
    // 每次都重新读取快照，据此刷新「今天」这一天的数据与上课状态。
    const data = formBindingData.createFormBindingData(buildCardData(this.context));
    formProvider.updateForm(formId, data).catch((err: BusinessError) => {
      hilog.error(0xEC01, 'EntryFormAbility', 'updateForm failed: %{public}s', JSON.stringify(err));
    });
  }

  onRemoveForm(formId: string): void {
    removeFormId(this.context, formId);
  }
}
