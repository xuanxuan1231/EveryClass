# Dynamic Island Layout Refinement Implementation Plan

> **For agentic workers:** Use the available `implement` workflow to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the compact Dynamic Island spacing visually balanced and keep the expanded presentation free of borders that obscure text.

**Architecture:** Keep the existing ActivityKit data flow and SwiftUI region structure. Refine only region sizing, alignment, and margins in `ClassWidgetLiveActivity.swift`, relying on WidgetKit's native Dynamic Island shape and safe-area behavior.

**Tech Stack:** Swift 5, SwiftUI, WidgetKit, ActivityKit, iOS 16.2+

## Global Constraints

- Modify only `ios/ClassWidget/ClassWidgetLiveActivity.swift`.
- Do not change the Flutter method channel, ActivityKit attributes, Android notification, or Live Activity lifecycle.
- Keep the Widget extension deployment target at iOS 16.2.
- Add no dependencies.
- Keep the compact capsule width fixed while moving each compact content item 6 points toward the center.
- Move the expanded leading and trailing text stacks inward by 24 points without changing the bottom region.

---

### Task 1: Refine Dynamic Island Region Layout

**Files:**
- Modify: `ios/ClassWidget/ClassWidgetLiveActivity.swift:16-55`

**Interfaces:**
- Consumes: `ClassActivityAttributes.ContentState` and the existing `DynamicIsland` region closures.
- Produces: compact and expanded WidgetKit views with native outlining, symmetric 52-point compact regions, right-aligned timing text, and 12-point expanded-region margins.

- [ ] **Step 1: Record the current visual regression evidence**

Use the supplied screenshots as the baseline: compact mode has an oversized gap after the timer, and expanded mode shows the indigo keyline over the course content. No deterministic SwiftUI snapshot harness exists in the project, so this native system UI change uses simulator build plus manual screenshot verification rather than adding a brittle image test.

- [ ] **Step 2: Apply the minimal layout refinement**

Change the Dynamic Island construction to add the same margin to all expanded regions, use symmetric compact regions with edge-aligned content, and remove the custom keyline:

```swift
DynamicIslandExpandedRegion(.leading) {
    VStack(alignment: .leading, spacing: 2) {
        Text(context.state.phase)
            .font(.caption2).foregroundStyle(.secondary)
        Text(context.state.subject)
            .font(.headline).lineLimit(1)
    }
}
.contentMargins(.all, 12)

DynamicIslandExpandedRegion(.trailing) {
    VStack(alignment: .trailing, spacing: 2) {
        Text(context.state.statusLabel)
            .font(.caption2).foregroundStyle(.secondary)
        Text(
            timerInterval: context.state.countdownStart...context.state.countdownEnd,
            countsDown: true
        )
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 64)
    }
}
.contentMargins(.all, 12)

DynamicIslandExpandedRegion(.bottom) {
    if !context.state.room.isEmpty {
        Label(context.state.room, systemImage: "mappin.and.ellipse")
            .font(.subheadline)
    }
}
.contentMargins(.all, 12)

Image(systemName: "book.closed")
    .padding(.leading, 6)
    .frame(width: 52, alignment: .leading)

Text(
    timerInterval: context.state.countdownStart...context.state.countdownEnd,
    countsDown: true
)
.monospacedDigit()
.multilineTextAlignment(.trailing)
.padding(.trailing, 6)
.frame(width: 52, alignment: .trailing)

// End the DynamicIsland after the minimal region without keylineTint.
```

- [ ] **Step 3: Check source formatting and the focused diff**

Run: `git diff --check && git diff -- ios/ClassWidget/ClassWidgetLiveActivity.swift`

Expected: no whitespace errors; the diff contains only the three expanded-region margins, symmetric compact alignment, and removal of the keyline tint.

- [ ] **Step 4: Compile the iOS simulator app**

Run: `xcodebuild -project ios/Runner.xcodeproj -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: exit code 0 with `** BUILD SUCCEEDED **`; Runner and ClassWidget compile for the existing iOS 16.2 deployment target.

- [ ] **Step 5: Verify the Dynamic Island states**

On a Dynamic Island-capable simulator or device, start the existing debug Live Activity preview. Confirm compact mode has balanced native insets and expanded mode has no visible custom keyline; course name, room, status label, and countdown remain unobstructed.

- [ ] **Step 6: Commit the layout fix**

```bash
git add ios/ClassWidget/ClassWidgetLiveActivity.swift docs/superpowers/plans/2026-07-11-dynamic-island-layout.md
git commit -m "fix(ios): refine dynamic island layout"
```

---

### Task 2: Move Expanded Side Content Inward

**Files:**
- Modify: `ios/ClassWidget/ClassWidgetLiveActivity.swift:16-38`

**Interfaces:**
- Consumes: the existing expanded leading and trailing `VStack` views.
- Produces: the same content with 24-point directional padding toward the center.

- [ ] **Step 1: Capture the current simulator state**

Run: `xcrun simctl io booted screenshot /tmp/everyclass-expanded-before.png`

Expected: the expanded Live Activity screenshot shows both side labels touching the curved outer edges.

- [ ] **Step 2: Add directional padding**

Add `.padding(.leading, 24)` to the leading `VStack` and
`.padding(.trailing, 24)` to the trailing `VStack`. Keep the existing
`.contentMargins(.all, 12)` modifiers and all compact-region code unchanged.

- [ ] **Step 3: Compile and verify**

Run: `xcodebuild -project ios/Runner.xcodeproj -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **` and both expanded side stacks render fully inside the curved island boundary.
