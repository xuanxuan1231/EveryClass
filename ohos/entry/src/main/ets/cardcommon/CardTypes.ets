// 服务卡片共享的纯类型定义（只含 interface，无任何 kit/运行时依赖）。
//
// 单独成文件的原因有二：
//  1. 卡片页面（form 页）跑在受限沙箱里，不宜 import 带 @kit.FormKit / fileIo 的
//     CardData.ets；这里只放接口，import 后编译期即被擦除，零运行时footprint。
//  2. 两张卡片页面若各自 `interface LessonVM {...}`，会在 form 编译单元里同名合并
//     报错（arkts-no-decl-merging）；统一从本文件 import 即可避免。

/// 传给卡片 UI 的单节课视图模型。
export interface LessonVM {
  subjectId: string;  // 所属课程 ID，供点课深链定位（可空字符串）
  name: string;
  room: string;
  teacher: string;
  startText: string;  // "08:00"
  endText: string;    // "08:45"（自定义单一时刻可能为空）
  startMinute: number; // 距零点分钟数，供点课深链定位（-1=未知）
  periodText: string; // "第1节" / "第1-2节" / ""（自定义时刻）
  color: string;      // "#RRGGBB" / ""
  state: string;      // 'done' | 'now' | 'todo'
}

/// 实时活动焦点：当前课或下一节 + 倒计时文案。
export interface FocusVM {
  mode: string;        // 'inClass' | 'before' | 'ended' | 'empty'
  phaseText: string;   // "正在进行" / "下一节" / "今天课程已结束 🎉" / "今日无课"
  subject: string;     // 焦点科目（ended/empty 为空）
  room: string;
  timeText: string;    // "08:00-08:45"
  countdownText: string; // "距下课 23 分钟" / "距上课 5 分钟" / "即将上课" / ""
  nextLabel: string;   // 上课中且有下一节时："下一节 XX"；其余为空
}

/// 今日卡片整体视图模型（两张卡片共用；各取所需字段）。
export interface CardData {
  title: string;
  dateText: string;
  weekText: string;
  statusText: string;
  hasData: boolean;
  wide: boolean;       // 是否宽版（2*4）——由卡片尺寸在 Ability 侧算好注入
  lessons: LessonVM[];
  focus: FocusVM;
}

/// postCardAction 的参数结构。
export interface CardAction {
  action: string;
  abilityName: string;
  params: Record<string, Object>;
}
