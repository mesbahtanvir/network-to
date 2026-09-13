# network.to design-level accessibility review

Status: **Passed for UI design lock; native runtime verification pending implementation**  
Version: 1.0  
Reviewed: 2026-09-04  
Scope: authentication, verification, onboarding, Today, Introduction, Available Today, mutual-interest messaging, meetup feedback, Connection, and the component-state sheet

## 1. What this review proves

This review verifies that the proposed UI and interactive design artifacts contain the accessibility behavior needed to lock the design direction. It does not claim that an unbuilt SwiftUI app has passed VoiceOver or Dynamic Type runtime testing.

## 2. Evidence

| Gate | Evidence | Result |
| --- | --- | --- |
| Semantic structure | Named regions, native buttons and fields, labeled navigation, progress semantics, alerts, status/live regions, and current-page state | Pass |
| Keyboard operation | All actions use native controls; onboarding validation returns focus to the invalid field; state changes preserve or deliberately move focus | Pass |
| Modal behavior | Available Today sheet is a named modal dialog with background inerting, focus entry, focus loop, Escape dismissal, and focus return | Pass |
| Touch targets | Interactive controls and fields have at least 44 × 44 pt effective targets in the design artifacts | Pass |
| Minimum prototype text | No visible prototype label is below 11 px; editable fields are 16 px | Pass |
| Colour contrast | Key light and dark token pairs were calculated against WCAG relative-luminance rules | Pass |
| Colour independence | Selected, verification, availability, feedback, error, and system states combine colour with text, symbols, borders, or control state | Pass |
| Compact layout | Onboarding, Introduction, and component states were visually reviewed at 320 px without clipping or horizontal page scrolling | Pass |
| Standard layout | All three artifacts were reviewed at 736 px | Pass |
| Dark appearance | Forced-dark visual review completed for onboarding and the complete Introduction screen; remaining components use the same verified tokens | Pass |
| Reduced motion | Transient progress, notification, and toast transitions are disabled under `prefers-reduced-motion` | Pass |
| Error recovery | Consumer-email rejection, failed-message state, availability expiry, and offline state remain readable and actionable | Pass |

## 3. Contrast results

All primary text/action pairs exceed the WCAG AA 4.5:1 requirement for normal text.

| Foreground on background | Ratio |
| --- | ---: |
| `text-primary` on `background`, light | 13.50:1 |
| `text-primary` on `background`, dark | 15.72:1 |
| `text-secondary` on `background`, light | 5.28:1 |
| `text-secondary` on `background`, dark | 8.99:1 |
| `accent` on `surface`, light | 5.74:1 |
| `accent` on `surface`, dark | 9.67:1 |
| Primary-button foreground on `accent-strong`, light | 9.17:1 |
| Primary-button foreground on `accent-strong`, dark | 9.37:1 |
| Meeting-context text on meeting surface, light | 5.85:1 |
| Meeting-context text on meeting surface, dark | 6.68:1 |
| `company-mark-glyph` on `company-mark-backing`, both appearances | 8.07:1 |
| `company-mark-backing` on `surface`, dark (non-text, ≥ 3:1 required) | 14.02:1 |

Company marks and company monograms are decorative (`accessibilityHidden`); the company name and the verification wording remain the accessible text, so no ratio is required for the tile on the light surface. The tile is the height of its text line at every Dynamic Type size, including accessibility sizes, and wraps inline with the text at 320 pt.

## 4. Interaction regression evidence

- Onboarding: seven focused context steps, review, and completion state compile and pass state-transition coverage.
- Authentication: native work-email entry and one-time-code semantics are implemented; sign-up and sign-in state transitions passed unit coverage.
- Introduction lifecycle: Introduction → private interest → mutual interest → chat → meetup feedback → Connection passed.
- Mutual-interest notification appeared only in the waiting state.
- Component sheet: category switching and keyboard message submission passed.
- Browser console: no errors or warnings across the three revised artifacts.

## 5. Native implementation gates

The SwiftUI implementation must still be tested on device or Simulator for:

- VoiceOver reading order and custom action names;
- the notification invitation card on Today: first in the reading order while it is showing, both buttons announced with label and hint, no truncation at the largest accessibility text size at 320 pt, nothing animating;
- Dynamic Type through the largest accessibility sizes;
- Bold Text, Button Shapes, Differentiate Without Colour, and Increased Contrast;
- Reduce Motion and Reduce Transparency;
- hardware-keyboard navigation and dismissal;
- sheet detents and focus restoration under native presentation;
- localization expansion for dates, time windows, introduction reasons, and safety copy.

These are implementation acceptance tests. Failure requires the SwiftUI layout to adapt without changing the approved information hierarchy or interaction model.
