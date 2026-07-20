// EveryClass 今日课表服务卡片 UI（对齐 Android 的 TodayScheduleWidget）。
//
// 数据由 EntryFormAbility 从 card_snapshot.json 解析后通过 createFormBindingData
// 注入，这里只做纯展示；卡片不能做文件 IO / 复杂逻辑。
// 布局对 2*2 与 2*4 自适应：宽版（wide，由 Ability 侧按 FormDimension 判定后注入）
// 副信息更全、色条更宽；卡片越高可见的课程行越多。每节课单独可点，点课回应用唤出
// 该课详情浮窗。

import { CardAction, LessonVM } from '../../cardcommon/CardTypes';

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = '今日课程';
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('statusText') statusText: string = '';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('lessons') lessons: LessonVM[] = [];
  // 是否宽版（2*4）：卡片 UI 不支持 onAreaChange，故由 Ability 侧算好随数据注入。
  @LocalStorageProp('wide') wide: boolean = false;

  private readonly accent: ResourceColor = $r('app.color.card_accent');
  private readonly secondary: ResourceColor = $r('app.color.card_text_secondary');
  private readonly primary: ResourceColor = $r('app.color.card_text_primary');

  /// 未结束课程用课程色（快照里已是解析后的展示色），缺省回退强调色；
  /// 已结束课程整体降为次要色以弱化存在感。
  private barColor(l: LessonVM): ResourceColor {
    if (l.state === 'done') {
      return this.secondary;
    }
    if (l.color && l.color.length > 0) {
      return l.color;
    }
    return this.accent;
  }

  /// 副信息：教室 · 教师 · 节次（教师/节次仅在宽版展示，窄版只留教室避免截断）。
  private subText(l: LessonVM): string {
    const parts: string[] = [];
    if (l.room && l.room.length > 0) {
      parts.push(l.room);
    }
    if (this.wide && l.teacher && l.teacher.length > 0) {
      parts.push(l.teacher);
    }
    if (this.wide && l.periodText && l.periodText.length > 0) {
      parts.push(l.periodText);
    }
    return parts.join(' · ');
  }

  /// 点这行课→显式启动 EntryAbility，带上 subjectId + startMinute；
  /// 主进程解析后经 everyclass/deeplink 通道转交 Flutter，定位该课并弹详情浮窗。
  private openLesson(l: LessonVM): void {
    const action: CardAction = {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        'targetPage': 'lesson',
        'subjectId': l.subjectId,
        'startMinute': l.startMinute,
      } as Record<string, Object>,
    };
    postCardAction(this, action);
  }

  private openApp(): void {
    const action: CardAction = {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { 'targetPage': 'index' } as Record<string, Object>,
    };
    postCardAction(this, action);
  }

  @Builder
  LessonRow(l: LessonVM) {
    // 已结束课程：更矮的行 + 更小的字号，进一步弱化存在感（色条已降为次要色）。
    Row() {
      // 整高色条：左缘随行圆角，右缘直角紧贴内容。
      Column()
        .width(this.wide ? 5 : 4)
        .height('100%')
        .borderRadius({ topLeft: 8, bottomLeft: 8 })
        .backgroundColor(this.barColor(l))

      Column() {
        Text(l.name)
          .fontSize(l.state === 'done' ? 11 : 13)
          .fontWeight(FontWeight.Medium)
          .fontColor(l.state === 'done' ? this.secondary : this.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subText(l).length > 0) {
          Text(this.subText(l))
            .fontSize(l.state === 'done' ? 9 : 10)
            .fontColor(this.secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })

      Column() {
        Text(l.startText)
          .fontSize(l.state === 'done' ? 9 : 10)
          .fontColor(this.secondary)
          .maxLines(1)
        if (l.endText && l.endText.length > 0) {
          Text(l.endText)
            .fontSize(l.state === 'done' ? 9 : 10)
            .fontColor(this.secondary)
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.End)
      .margin({ left: 6 })
    }
    .width('100%')
    .height(l.state === 'done' ? (this.wide ? 32 : 30) : (this.wide ? 38 : 36))
    .padding({ right: 8 })
    .borderRadius(8)
    .backgroundColor(l.state === 'now' ? $r('app.color.card_now_bg') : Color.Transparent)
    .onClick(() => this.openLesson(l))
  }

  build() {
    Column() {
      // 顶部：日期 + 周次，右侧课表名。
      Row() {
        Column() {
          Text(this.dateText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primary)
          if (this.weekText.length > 0) {
            Text(this.weekText)
              .fontSize(10)
              .fontColor(this.secondary)
              .margin({ top: 1 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.title)
          .fontSize(10)
          .fontColor(this.secondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '45%' })
      }
      .width('100%')

      // 状态行：正在进行 / 下一节 / 已结束。
      Text(this.statusText)
        .fontSize(11)
        .fontColor(this.accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 4, bottom: 6 })

      // 课程列表 / 空态。服务卡片不响应滚动手势，超出可见区域的行会被裁剪；
      // 已在数据侧把「当前/待上课」重排到顶部，保证最相关的课优先可见可点。
      if (this.hasData && this.lessons.length > 0) {
        List({ space: 4 }) {
          ForEach(this.lessons, (l: LessonVM) => {
            ListItem() {
              this.LessonRow(l)
            }
          }, (l: LessonVM, index: number) => `${index}-${l.name}-${l.startText}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      } else {
        Column() {
          Text(this.statusText.length > 0 ? this.statusText : '今天没有课')
            .fontSize(13)
            .fontColor(this.secondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .onClick(() => this.openApp())
  }
}
