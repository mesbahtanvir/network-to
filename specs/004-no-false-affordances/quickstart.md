# Quickstart: No False Affordances

## iOS

```sh
xcodebuild test -project NetworkTo.xcodeproj -scheme NetworkTo \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The iOS workflow runs the same on the PR; a Release compile confirms nothing still references
the removed view.

## Manual checks (demonstration build, `--mock-backend`)

1. Open Today, view the introduction, tap Pass and confirm: the confirmation shows "Thanks for
   deciding" with one action, Return to Today. No link, sheet, or notice about feedback.
2. Return to Today: the searching state appears.
3. Open Profile, then Work verification: the company, the work email, the Verified mark, and the
   two explanations are shown; there is no button, and nothing appears when the screen is
   scrolled or tapped.

## Source check

```sh
grep -rn "PassFeedbackView\|showPassFeedback\|Feedback saved privately\|Verify a new work email\|reverification flow" NetworkTo
```

must print nothing. (Today's meetup card still says "Share private feedback when you’re ready"; that is the meetup feedback flow, which records feedback and stays.)
