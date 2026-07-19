// 服务卡片的共享逻辑：读取快照 → 构建卡片数据；记录已添加卡片的 formId；
// 一次性刷新本应用全部卡片。
//
// 被两处复用：
//  - EntryFormAbility（卡片进程）：onAddForm/onUpdateForm 构建数据、增删 formId。
//  - EntryAbility（主进程）：onBackground 时用 updateAllForms 立即刷新桌面卡片，
//    实现「在 App 里改完课表、回到桌面即刷新」。

import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0xEC01;
const TAG = 'CardData';

/// 与 Flutter 侧 lib/platform/card_snapshot.dart 约定的快照文件名。
const SNAPSHOT_FILE = 'card_snapshot.json';
/// 已添加到桌面的卡片 formId 列表（本地持久化，供主进程刷新时枚举）。
const FORM_IDS_FILE = 'card_form_ids.json';

// ---- 快照文件里的原始结构（与 Dart 端 export 的 JSON 一一对应）----

interface LessonRaw {
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

// ---- 传给卡片 UI 的视图模型 ----

export interface LessonVM {
  name: string;
  time: string;
  room: string;
  color: string;
  state: string; // 'done' | 'now' | 'todo'
}

export interface CardData {
  title: string;
  dateText: string;
  weekText: string;
  statusText: string;
  hasData: boolean;
  lessons: LessonVM[];
}

const WEEKDAY_CN: string[] = ['日', '一', '二', '三', '四', '五', '六', '日'];

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

/// 读取快照 → 定位到今天 → 构建卡片视图模型。任何异常都退化为占位数据，
/// 保证卡片始终有内容可渲染。
export function buildCardData(ctx: common.Context): CardData {
  const now = new Date();
  const dateText = `${now.getMonth() + 1}月${now.getDate()}日 周${WEEKDAY_CN[now.getDay()]}`;
  const empty: CardData = {
    title: '今日课程',
    dateText,
    weekText: '',
    statusText: '打开应用创建课表',
    hasData: false,
    lessons: [],
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
      statusText: '今天没有课 🎉',
      hasData: false,
      lessons: [],
    };
  }

  const nowMin = now.getHours() * 60 + now.getMinutes();
  const lessons: LessonVM[] = [];
  let nowName = '';
  let nextName = '';
  let nextTime = '';
  for (let i = 0; i < today.lessons.length; i++) {
    const l = today.lessons[i];
    const s = minutesOf(l.start);
    const e = minutesOf(l.end);
    let state = 'todo';
    if (e >= 0 && nowMin >= e) {
      state = 'done';
    } else if (s >= 0 && e >= 0 && nowMin >= s && nowMin < e) {
      state = 'now';
      nowName = l.name;
    }
    if (state === 'todo' && nextName.length === 0) {
      nextName = l.name;
      nextTime = l.start;
    }
    lessons.push({
      name: l.name,
      time: `${l.start}-${l.end}`,
      room: l.room,
      color: l.color,
      state,
    });
  }

  let statusText: string;
  if (nowName.length > 0) {
    statusText = `正在上课 · ${nowName}`;
  } else if (nextName.length > 0) {
    statusText = `下一节 ${nextTime} · ${nextName}`;
  } else {
    statusText = '今天课程已结束';
  }

  return { title, dateText, weekText, statusText, hasData: true, lessons };
}

// ---- formId 持久化 ----

function readFormIds(ctx: common.Context): string[] {
  try {
    const path = ctx.filesDir + '/' + FORM_IDS_FILE;
    if (!fileIo.accessSync(path)) {
      return [];
    }
    const text = fileIo.readTextSync(path);
    if (!text || text.length === 0) {
      return [];
    }
    return JSON.parse(text) as string[];
  } catch (e) {
    return [];
  }
}

function writeFormIds(ctx: common.Context, ids: string[]): void {
  try {
    const path = ctx.filesDir + '/' + FORM_IDS_FILE;
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    fileIo.writeSync(file.fd, JSON.stringify(ids));
    fileIo.closeSync(file);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'write formIds failed: %{public}s', JSON.stringify(e));
  }
}

export function addFormId(ctx: common.Context, formId: string): void {
  if (!formId || formId.length === 0) {
    return;
  }
  const ids = readFormIds(ctx);
  if (ids.indexOf(formId) < 0) {
    ids.push(formId);
    writeFormIds(ctx, ids);
  }
}

export function removeFormId(ctx: common.Context, formId: string): void {
  const ids = readFormIds(ctx);
  const next = ids.filter((id: string) => id !== formId);
  if (next.length !== ids.length) {
    writeFormIds(ctx, next);
  }
}

/// 立即用最新快照刷新本应用已添加的全部卡片。全程吞异常，绝不向调用方抛出，
/// 避免影响宿主 Ability 的生命周期。
export function updateAllForms(ctx: common.Context): void {
  try {
    const ids = readFormIds(ctx);
    if (ids.length === 0) {
      return;
    }
    const data = formBindingData.createFormBindingData(buildCardData(ctx));
    for (let i = 0; i < ids.length; i++) {
      formProvider.updateForm(ids[i], data).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}s', ids[i], JSON.stringify(err));
      });
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'updateAllForms failed: %{public}s', JSON.stringify(e));
  }
}
