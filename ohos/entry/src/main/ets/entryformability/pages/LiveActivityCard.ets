// EveryClass 实时活动服务卡片 UI（对齐 Android 的 LiveActivityWidget）。
//
// 与今日课表卡片共用同一份卡片数据（EntryFormAbility 注入），这里聚焦「当前/下一节」：
//  2*2 —— 单一焦点面板：状态 + 大字科目 + 教室 + 倒计时。
//  2*4 —— 左＝焦点面板，右＝今日课程列表（Header + 列表，无状态行）。
// 焦点面板点击打开应用；右侧每节课单独可点，点课回应用唤出该课详情浮窗。

import { CardAction, FocusVM, LessonVM } from '../../cardcommon/CardTypes';

const EMPTY_FOCUS: FocusVM = {
  mode: 'empty', phaseText: '今日无课', subject: '', room: '', timeText: '', countdownText: '', nextLabel: '',
};

@Entry
@Component
struct LiveActivityCard {
  @LocalStorageProp('title') title: string = '今日课程';
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('lessons') lessons: LessonVM[] = [];
  @LocalStorageProp('focus') focus: FocusVM = EMPTY_FOCUS;
  // 是否宽版（2*4，焦点 + 列表）：由 Ability 侧按 FormDimension 判定后注入。
  @LocalStorageProp('wide') wide: boolean = false;

  private readonly accent: ResourceColor = $r('app.color.card_accent');
  private readonly secondary: ResourceColor = $r('app.color.card_text_secondary');
  private readonly primary: ResourceColor = $r('app.color.card_text_primary');

  /// 焦点科目字号：无原生 autosize，按名称长度分档——短名更大、长名收缩避免截断。
  private focusSubjectSize(subject: string): number {
    const n = subject.length;
    if (n <= 4) {
      return 24;
    }
    if (n <= 6) {
      return 20;
    }
    if (n <= 8) {
      return 17;
    }
    return 15;
  }

  /// 焦点状态字号：短状态放大更醒目；长状态（今天课程已结束 🎉）逐级收窄避免截断。
  private focusPhaseSize(phase: string): number {
    const n = phase.length;
    if (n <= 4) {
      return 15;
    }
    if (n <= 5) {
      return 13;
    }
    if (n <= 7) {
      return 11;
    }
    return 10;
  }

  private barColor(l: LessonVM): ResourceColor {
    if (l.state === 'done') {
      return this.secondary;
    }
    if (l.color && l.color.length > 0) {
      return l.color;
    }
    return this.accent;
  }

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

  /// 焦点面板：状态 + 大字科目 + 教室 + 倒计时。「下一节」提示由宽版调用点在底部追加
  /// （见 build），以便用 Blank 在定高容器里做低端对齐。
  @Builder
  FocusPane() {
    Column() {
      Text(this.focus.phaseText)
        .fontSize(this.focusPhaseSize(this.focus.phaseText))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.focus.subject.length > 0) {
        Text(this.focus.subject)
          .fontSize(this.focusSubjectSize(this.focus.subject))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      if (this.focus.room.length > 0) {
        Text(this.focus.room)
          .fontSize(12)
          .fontColor(this.secondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      if (this.tailText().length > 0) {
        Text(this.tailText())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.focus.countdownText.length > 0 ? this.accent : this.secondary)
          .maxLines(1)
          .margin({ top: 6 })
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  private tailText(): string {
    return this.focus.countdownText.length > 0 ? this.focus.countdownText : this.focus.timeText;
  }

  /// 宽版右栏的紧凑课程行（只留教室，右侧起止时间）。
  @Builder
  CompactRow(l: LessonVM) {
    Row() {
      Column()
        .width(4)
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
        if (l.room && l.room.length > 0) {
          Text(l.room)
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
    .height(l.state === 'done' ? 30 : 36)
    .padding({ right: 8 })
    .borderRadius(8)
    .backgroundColor(l.state === 'now' ? $r('app.color.card_now_bg') : Color.Transparent)
    .onClick(() => this.openLesson(l))
  }

  /// 宽版右栏：Header（日期/周次 + 课表名）+ 课程列表 / 空态。服务卡片不响应滚动手势，
  /// 超出可见区域的行会被裁剪；已在数据侧把当前/待上课重排到顶部，保证最相关的课优先可见。
  @Builder
  TodayColumn() {
    Column() {
      Row() {
        Column() {
          Text(this.dateText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primary)
            .maxLines(1)
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
          .constraintSize({ maxWidth: '55%' })
      }
      .width('100%')
      .margin({ bottom: 6 })

      if (this.hasData && this.lessons.length > 0) {
        List({ space: 4 }) {
          ForEach(this.lessons, (l: LessonVM) => {
            ListItem() {
              this.CompactRow(l)
            }
          }, (l: LessonVM, index: number) => `${index}-${l.name}-${l.startText}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      } else {
        Column() {
          Text('今日无课')
            .fontSize(13)
            .fontColor(this.secondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  build() {
    if (this.wide) {
      Row() {
        Column() {
          this.FocusPane()
          // 上课中且有下一节：把提示推到左栏底部实现低端对齐。
          if (this.focus.nextLabel.length > 0) {
            Blank()
            Text(this.focus.nextLabel)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(12)

        this.TodayColumn()
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .backgroundColor($r('app.color.card_bg'))
      .onClick(() => this.openApp())
    } else {
      Column() {
        this.FocusPane()
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.card_bg'))
      .onClick(() => this.openApp())
    }
  }
}
