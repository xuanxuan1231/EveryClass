# Dynamic Island Layout Refinement

## Goal

Refine the EveryClass iOS Live Activity presentation so compact and expanded
Dynamic Island states read as a native system surface: balanced horizontal
spacing, no decorative keyline over content, and text that remains clear at
all supported sizes.

## Scope

The change is limited to `ios/ClassWidget/ClassWidgetLiveActivity.swift`.
It does not change the Flutter method channel, ActivityKit attributes, lesson
data, Android notification UI, or Live Activity lifecycle.

## Design

Remove the explicit Dynamic Island `keylineTint`, which draws a visible outline
over the expanded presentation and competes with the course information.

In compact mode, give both leading and trailing content explicit 52-point
regions. Align the icon to the leading edge and align the monospaced timer text
and its frame to the trailing edge. This keeps the compact capsule at its native
size. Add a 6-point inset on each outer edge so the icon and timer move inward
toward the camera cutout by the same amount while remaining visually balanced.

In expanded mode, apply one consistent content margin to the leading, trailing,
and bottom regions. Leading course text remains one line; the countdown remains
right-aligned and monospaced. This keeps all content inside the Dynamic Island
safe area without relying on a decorative border.

## Acceptance Criteria

- Compact mode has no visible custom outline and the leading icon and trailing
  countdown have visually balanced system insets, each shifted 6 points toward
  the center from the edge-aligned layout.
- Expanded mode has no keyline crossing, obscuring, or competing with text.
- Course name, room, status label, and countdown remain readable and do not
  overlap at the existing supported content sizes.
- The Widget extension continues to compile for iOS 16.2 and later.

## Verification

Run the iOS simulator build without code signing. On a Dynamic Island-capable
simulator or device, start the existing debug preview and check compact and
expanded states against the acceptance criteria.
