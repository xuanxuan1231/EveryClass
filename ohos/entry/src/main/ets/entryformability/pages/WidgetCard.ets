// EveryClass 桌面服务卡片 UI。
//
// 数据由 EntryFormAbility 从 card_snapshot.json 解析后通过 createFormBindingData
// 注入，这里只做纯展示；卡片不能做文件 IO / 复杂逻辑。
// 布局对 2*2 与 2*4 自适应：同一套结构，卡片越高、可见的课程行越多。

interface LessonVM {
  name: string;
  time: string;
  room: string;
  color: string;
  state: string; // 'done' | 'now' | 'todo'
}

interface CardAction {
  action: string;
  abilityName: string;
  params: Record<string, Object>;
}

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = '今日课程';
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('statusText') statusText: string = '';
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('lessons') lessons: LessonVM[] = [];

  private readonly accent: ResourceColor = $r('app.color.card_accent');

  private barColor(l: LessonVM): ResourceColor {
    if (l.color && l.color.length > 0) {
      return l.color;
    }
    return $r('app.color.card_accent');
  }

  build() {
    Column() {
      // 顶部：日期 + 周次，右侧课表名。
      Row() {
        Column() {
          Text(this.dateText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_text_primary'))
          if (this.weekText.length > 0) {
            Text(this.weekText)
              .fontSize(10)
              .fontColor($r('app.color.card_text_secondary'))
              .margin({ top: 1 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.title)
          .fontSize(10)
          .fontColor($r('app.color.card_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '45%' })
      }
      .width('100%')

      // 状态行：正在上课 / 下一节 / 已结束。
      Text(this.statusText)
        .fontSize(11)
        .fontColor(this.accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 4, bottom: 6 })

      // 课程列表 / 空态。
      if (this.hasData && this.lessons.length > 0) {
        Column({ space: 4 }) {
          ForEach(this.lessons, (l: LessonVM) => {
            Row() {
              Column()
                .width(3)
                .height(28)
                .borderRadius(2)
                .backgroundColor(this.barColor(l))
              Column() {
                Text(l.name)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.card_text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (l.room.length > 0) {
                  Text(l.room)
                    .fontSize(10)
                    .fontColor($r('app.color.card_text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 1 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 8 })

              Text(l.time)
                .fontSize(10)
                .fontColor($r('app.color.card_text_secondary'))
            }
            .width('100%')
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(8)
            .backgroundColor(l.state === 'now'
              ? $r('app.color.card_now_bg')
              : Color.Transparent)
            .opacity(l.state === 'done' ? 0.45 : 1)
          }, (l: LessonVM, index: number) => `${index}-${l.name}-${l.time}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .clip(true)
      } else {
        Column() {
          Text(this.statusText.length > 0 ? this.statusText : '今天没有课')
            .fontSize(13)
            .fontColor($r('app.color.card_text_secondary'))
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
    .onClick(() => {
      const action: CardAction = {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { 'targetPage': 'index' } as Record<string, Object>,
      };
      postCardAction(this, action);
    })
  }
}
