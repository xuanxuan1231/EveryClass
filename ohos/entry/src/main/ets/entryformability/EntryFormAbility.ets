import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import type { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { addForm, buildCardData, getFormDim, removeForm } from '../cardcommon/CardData';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 记录 formId + 尺寸：formId 供主进程刷新时枚举；尺寸决定 2*2/2*4 布局。
    let formId = '';
    let dim = 0;
    const params = want.parameters;
    if (params) {
      formId = params[formInfo.FormParam.IDENTITY_KEY] as string;
      const d = params[formInfo.FormParam.DIMENSION_KEY];
      if (typeof d === 'number') {
        dim = d as number;
      } else if (typeof d === 'string') {
        // Want 参数类型不保证：DIMENSION_KEY 若以数字字符串下发也要解析，
        // 否则 2*4 卡片会退化成窄版（与 EntryAbility.parseLessonWant 的容错一致）。
        const n = Number.parseInt(d as string, 10);
        if (!Number.isNaN(n)) {
          dim = n;
        }
      }
    }
    addForm(this.context, formId, dim);
    return formBindingData.createFormBindingData(buildCardData(this.context, dim));
  }

  onCastToNormalForm(formId: string): void {
    // 常态卡片无需特殊处理。
  }

  onUpdateForm(formId: string): void {
    // 系统按 form_config.json 的 scheduledUpdateTime / updateDuration 触发；
    // 每次都重新读取快照，据此刷新「今天」这一天的数据与上课状态。
    // 尺寸取 onAddForm 时记录的值；老版本添加、无尺寸记录的卡片回退窄版（dim=0），
    // 重新添加即可恢复对应布局（表单进程拿不到运行中卡片的实时尺寸）。
    const dim = getFormDim(this.context, formId);
    const data = formBindingData.createFormBindingData(buildCardData(this.context, dim));
    formProvider.updateForm(formId, data).catch((err: BusinessError) => {
      hilog.error(0xEC01, 'EntryFormAbility', 'updateForm failed: %{public}s', JSON.stringify(err));
    });
  }

  onRemoveForm(formId: string): void {
    removeForm(this.context, formId);
  }
}
