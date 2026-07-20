// 服务卡片的共享逻辑：读取快照 → 构建卡片数据；记录已添加卡片的 formId + 尺寸；
// 一次性刷新本应用全部卡片。
//
// 被两处复用：
//  - EntryFormAbility（卡片进程）：onAddForm/onUpdateForm 构建数据、增删 form 记录。
//  - EntryAbility（主进程）：onBackground 时用 updateAllForms 立即刷新桌面卡片，
//    实现「在 App 里改完课表、回到桌面即刷新」。
//
// 与 Android 侧 CardSnapshotReader.kt 共享同一份契约与状态算法：单节课状态、
// 实时活动焦点、状态行文案、以及「当前活动置顶」的重排都保持一致，让两端卡片观感一致。
//
// 尺寸（wide）由本层算好注入：卡片（form）UI 不支持 onAreaChange，故在 Ability 侧
// 用系统传入的 FormDimension 判定 2*2（窄）/2*4（宽），随数据一起下发给卡片。

import { common } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardData, FocusVM, LessonVM } from './CardTypes';

const DOMAIN = 0xEC01;
const TAG = 'CardData';

/// 与 Flutter 侧 lib/platform/card_snapshot.dart 约定的快照文件名。
const SNAPSHOT_FILE = 'card_snapshot.json';
/// 已添加到桌面的卡片记录（formId + 尺寸，本地持久化，供主进程刷新时枚举）。
const FORM_IDS_FILE = 'card_form_ids.json';

// ---- 快照文件里的原始结构（与 Dart 端 export 的 JSON 一一对应）----

interface LessonRaw {
  subjectId: string;
  name: string;
  room: string;
  teacher: string;
  start: string;
  end: string;
  startPeriod: number;
  endPeriod: number;
  color: string;
}

interface DayRaw {
  date: string;
  weekday: number;
  week: number | null;
  lessons: LessonRaw[];
}

interface SnapshotRaw {
  version: number;
  generatedAt: string;
  calendarName: string;
  days: DayRaw[];
}

/// 定位到「今天」后用于计算焦点/状态的中间态课程。
interface RawLesson {
  subjectId: string;
  name: string;
  room: string;
  teacher: string;
  start: string;
  end: string;
  startMin: number;
  endMin: number;
  startPeriod: number;
  endPeriod: number;
  color: string;
}

/// 桌面卡片记录：formId + 系统尺寸（FormDimension 枚举值，0=未知）。
interface FormRef {
  id: string;
  dim: number;
}

const WEEKDAY_CN: string[] = ['日', '一', '二', '三', '四', '五', '六', '日'];

/// 是否宽版：2*4（Dimension_2_4=3）及更宽（4*4=4）走宽版布局，其余窄版。
function isWide(dim: number): boolean {
  return dim === formInfo.FormDimension.Dimension_2_4 || dim === formInfo.FormDimension.Dimension_4_4;
}

function pad2(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

function dateKey(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/// "HH:mm" → 距零点的分钟数；解析失败返回 -1。
function minutesOf(hhmm: string): number {
  const parts = hhmm.split(':');
  if (parts.length !== 2) {
    return -1;
  }
  const h = Number.parseInt(parts[0], 10);
  const m = Number.parseInt(parts[1], 10);
  if (Number.isNaN(h) || Number.isNaN(m)) {
    return -1;
  }
  return h * 60 + m;
}

function periodText(startPeriod: number, endPeriod: number): string {
  // 用 !(x > 0) 而非 x <= 0：老快照缺 startPeriod 字段时其值为 undefined，
  // 而 undefined <= 0 为 false 会漏过判断，最终渲染出「第undefined节」。
  if (!(startPeriod > 0)) {
    return '';
  }
  if (endPeriod > startPeriod) {
    return `第${startPeriod}-${endPeriod}节`;
  }
  return `第${startPeriod}节`;
}

function emptyFocus(mode: string, phaseText: string): FocusVM {
  return { mode, phaseText, subject: '', room: '', timeText: '', countdownText: '', nextLabel: '' };
}

/// 构建实时活动焦点：正在进行的课优先，其次下一节，都没有则「已结束/无课」。
function buildFocus(current: RawLesson | null, next: RawLesson | null, nowMin: number, hadLessons: boolean): FocusVM {
  if (current != null) {
    const m = Math.max(current.endMin - nowMin, 0);
    return {
      mode: 'inClass',
      phaseText: '正在进行',
      subject: current.name,
      room: current.room,
      timeText: `${current.start}-${current.end}`,
      countdownText: m <= 0 ? '即将下课' : `距下课 ${m} 分钟`,
      nextLabel: next != null ? `下一节 ${next.name}` : '',
    };
  }
  if (next != null) {
    const m = Math.max(next.startMin - nowMin, 0);
    return {
      mode: 'before',
      phaseText: '下一节',
      subject: next.name,
      room: next.room,
      timeText: `${next.start}-${next.end}`,
      countdownText: m <= 0 ? '即将上课' : `距上课 ${m} 分钟`,
      nextLabel: '',
    };
  }
  if (hadLessons) {
    return emptyFocus('ended', '今天课程已结束 🎉');
  }
  return emptyFocus('empty', '今日无课');
}

/// Flutter 的 getApplicationDocumentsDirectory() 在鸿蒙上解析为
/// applicationContext.filesDir + "/flutter"（见 path_provider_ohos 里的
/// PathUtils.getDataDirectory）。卡片进程必须用同一路径去读，才能读到 Flutter
/// 写的快照——要用 applicationContext（应用级、跨 Ability 一致），不能用
/// ctx.filesDir（那是模块级目录，且少了 /flutter 子目录）。
function snapshotPath(ctx: common.Context): string {
  let base = ctx.filesDir;
  try {
    const appCtx = ctx.getApplicationContext();
    if (appCtx && appCtx.filesDir && appCtx.filesDir.length > 0) {
      base = appCtx.filesDir;
    }
  } catch (e) {
    // 退回 ctx.filesDir（极少发生）。
  }
  return base + '/flutter/' + SNAPSHOT_FILE;
}

/// 读取快照 → 定位到今天 → 构建与尺寸无关的卡片视图模型（wide 先置 false）。
/// 文件 IO 只发生在这里；buildCardData / updateAllForms 再按各卡片尺寸覆盖 wide。
/// 任何异常都退化为占位数据，保证卡片始终有内容可渲染。
function buildCardCore(ctx: common.Context): CardData {
  const now = new Date();
  const dateText = `${now.getMonth() + 1}月${now.getDate()}日 周${WEEKDAY_CN[now.getDay()]}`;
  const empty: CardData = {
    title: '今日课程',
    dateText,
    weekText: '',
    statusText: '打开应用创建课表',
    hasData: false,
    wide: false,
    lessons: [],
    focus: emptyFocus('empty', '今日无课'),
  };

  let snap: SnapshotRaw;
  try {
    const path = snapshotPath(ctx);
    if (!fileIo.accessSync(path)) {
      return empty;
    }
    const text = fileIo.readTextSync(path);
    if (!text || text.length === 0) {
      return empty;
    }
    snap = JSON.parse(text) as SnapshotRaw;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read snapshot failed: %{public}s', JSON.stringify(e));
    return empty;
  }

  const todayKey = dateKey(now);
  let today: DayRaw | undefined = undefined;
  if (snap.days) {
    for (let i = 0; i < snap.days.length; i++) {
      if (snap.days[i].date === todayKey) {
        today = snap.days[i];
        break;
      }
    }
  }

  const title = snap.calendarName && snap.calendarName.length > 0 ? snap.calendarName : '今日课程';
  const weekText = today && today.week != null ? `第${today.week}周` : '';

  if (!today || !today.lessons || today.lessons.length === 0) {
    return {
      title,
      dateText,
      weekText,
      statusText: '今日无课 🎉',
      hasData: false,
      wide: false,
      lessons: [],
      focus: emptyFocus('empty', '今日无课'),
    };
  }

  // 原始课程按 start 排序（Dart 侧已排，保险再排一次），据此算状态与焦点。
  const raws: RawLesson[] = [];
  for (let i = 0; i < today.lessons.length; i++) {
    const l = today.lessons[i];
    raws.push({
      subjectId: l.subjectId ? l.subjectId : '',
      name: l.name,
      room: l.room,
      teacher: l.teacher,
      start: l.start,
      end: l.end,
      startMin: minutesOf(l.start),
      endMin: minutesOf(l.end),
      startPeriod: l.startPeriod,
      endPeriod: l.endPeriod,
      color: l.color,
    });
  }
  raws.sort((a: RawLesson, b: RawLesson) => a.startMin - b.startMin);

  const nowMin = now.getHours() * 60 + now.getMinutes();
  const lessons: LessonVM[] = [];
  let current: RawLesson | null = null;
  let next: RawLesson | null = null;
  for (let i = 0; i < raws.length; i++) {
    const r = raws[i];
    let state = 'todo';
    if (r.endMin >= 0 && nowMin >= r.endMin) {
      state = 'done';
    } else if (r.startMin >= 0 && nowMin >= r.startMin && nowMin < r.endMin) {
      state = 'now';
    }
    if (state === 'now') {
      current = r;
    }
    if (state === 'todo' && next == null) {
      next = r;
    }
    lessons.push({
      subjectId: r.subjectId,
      name: r.name,
      room: r.room,
      teacher: r.teacher,
      startText: r.start,
      endText: r.end,
      startMinute: r.startMin,
      periodText: periodText(r.startPeriod, r.endPeriod),
      color: r.color,
      state,
    });
  }

  const focus = buildFocus(current, next, nowMin, raws.length > 0);

  let statusText: string;
  if (current != null) {
    statusText = `正在进行 · ${current.name}`;
  } else if (next != null) {
    statusText = `下一节 ${next.start} · ${next.name}`;
  } else {
    statusText = '今天课程已结束 🎉';
  }

  // 默认置顶「当前活动」：未结束（正在进行 + 待上课，保持时序）在前，已结束的移到末尾。
  // 卡片列表无滚动定位 API，故用重排近似「滚动到当前活动」，与 Android 对齐。
  const active = lessons.filter((l: LessonVM) => l.state !== 'done');
  const done = lessons.filter((l: LessonVM) => l.state === 'done');
  const ordered = active.concat(done);

  return { title, dateText, weekText, statusText, hasData: true, wide: false, lessons: ordered, focus };
}

/// 只有 wide 与卡片尺寸相关：复制 core 并按尺寸覆盖 wide，得到单张卡片数据。
/// lessons/focus 只读，直接共享引用（不深拷贝），供多张卡片各自序列化。
function withWide(core: CardData, wide: boolean): CardData {
  return {
    title: core.title,
    dateText: core.dateText,
    weekText: core.weekText,
    statusText: core.statusText,
    hasData: core.hasData,
    wide,
    lessons: core.lessons,
    focus: core.focus,
  };
}

/// 读取快照并按 dim（系统传入的卡片尺寸）确定 wide，构建单张卡片数据。
export function buildCardData(ctx: common.Context, dim: number): CardData {
  return withWide(buildCardCore(ctx), isWide(dim));
}

// ---- form 记录持久化（formId + 尺寸）----

function readFormRefs(ctx: common.Context): FormRef[] {
  try {
    const path = ctx.filesDir + '/' + FORM_IDS_FILE;
    if (!fileIo.accessSync(path)) {
      return [];
    }
    const text = fileIo.readTextSync(path);
    if (!text || text.length === 0) {
      return [];
    }
    const parsed = JSON.parse(text) as Object[];
    const refs: FormRef[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const item = parsed[i];
      if (typeof item === 'string') {
        // 兼容旧格式（纯 formId 数组）：尺寸未知按窄版处理。
        refs.push({ id: item as string, dim: 0 });
      } else {
        const o = item as FormRef;
        if (o && o.id && o.id.length > 0) {
          refs.push({ id: o.id, dim: typeof o.dim === 'number' ? o.dim : 0 });
        }
      }
    }
    return refs;
  } catch (e) {
    return [];
  }
}

function writeFormRefs(ctx: common.Context, refs: FormRef[]): void {
  try {
    const path = ctx.filesDir + '/' + FORM_IDS_FILE;
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    // try/finally：writeSync 抛错（如磁盘写满）时也要 close，避免泄漏 fd。
    try {
      fileIo.writeSync(file.fd, JSON.stringify(refs));
    } finally {
      fileIo.closeSync(file);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'write formRefs failed: %{public}s', JSON.stringify(e));
  }
}

/// 记录（或更新）一张卡片的 formId 与尺寸。
export function addForm(ctx: common.Context, formId: string, dim: number): void {
  if (!formId || formId.length === 0) {
    return;
  }
  const refs = readFormRefs(ctx);
  let found = false;
  for (let i = 0; i < refs.length; i++) {
    if (refs[i].id === formId) {
      refs[i].dim = dim;
      found = true;
      break;
    }
  }
  if (!found) {
    refs.push({ id: formId, dim });
  }
  writeFormRefs(ctx, refs);
}

export function removeForm(ctx: common.Context, formId: string): void {
  const refs = readFormRefs(ctx);
  const next = refs.filter((r: FormRef) => r.id !== formId);
  if (next.length !== refs.length) {
    writeFormRefs(ctx, next);
  }
}

/// 查某张卡片记录的尺寸；无记录返回 0（按窄版处理）。
export function getFormDim(ctx: common.Context, formId: string): number {
  const refs = readFormRefs(ctx);
  for (let i = 0; i < refs.length; i++) {
    if (refs[i].id === formId) {
      return refs[i].dim;
    }
  }
  return 0;
}

/// 立即用最新快照刷新本应用已添加的全部卡片（各按其记录的尺寸构建数据）。
/// 全程吞异常，绝不向调用方抛出，避免影响宿主 Ability 的生命周期。
export function updateAllForms(ctx: common.Context): void {
  try {
    const refs = readFormRefs(ctx);
    if (refs.length === 0) {
      return;
    }
    // 快照只读一次；wide 是唯一与尺寸相关的字段，逐卡复制 core 覆盖即可，
    // 避免过去「每张卡片各读一次同一份 card_snapshot.json」的重复磁盘 IO/解析。
    const core = buildCardCore(ctx);
    for (let i = 0; i < refs.length; i++) {
      const ref = refs[i];
      const data = formBindingData.createFormBindingData(withWide(core, isWide(ref.dim)));
      formProvider.updateForm(ref.id, data).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}s', ref.id, JSON.stringify(err));
      });
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'updateAllForms failed: %{public}s', JSON.stringify(e));
  }
}
