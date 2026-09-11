# Design philosophy: calm technology

**Status**: Adopted 2026-09-11 · Owner: product owner · Governs: `.specify/memory/constitution.md` Principle VIII

network.to is calm technology. The phrase comes from Mark Weiser and John Seely Brown's
1996 essay "The Coming Age of Calm Technology" and Amber Case's 2015 principles. The idea is
simple: the best technology requires the least attention, informs without demanding, and gets
out of the way so people can get on with their lives. For a product whose entire purpose is
to get two people to meet in person, calm is not a style; it is the product working.

Every screen, notification, animation, and line of copy is judged against the eight
principles below. Each principle is stated, then made concrete for network.to. The concrete
rules are binding; the principle explains why.

## 1. Require the smallest possible amount of attention

Technology should occupy the smallest possible amount of a person's attention and return it
as soon as it can.

- Today shows one introduction or one next action. There is nothing else to look at.
- An introduction is a full screen with a clear decision, readable in under a minute. Pass
  and Interested are equally easy; neither asks for a reason.
- The app has no reason to be opened when nothing has changed. There are no streaks, no daily
  check-ins, and no content to consume.
- Onboarding asks for what the product needs and nothing more, and the résumé fast path fills
  in the factual parts so the member only writes what only they can write.

## 2. Inform and create calm

Technology should inform without alarming and should leave the person calmer than it found
them.

- Copy states what is true and what happens next, in plain professional language. There are no
  exclamation points, no urgency, no countdowns, and no "don't miss out".
- Waiting states are honest and reassuring: "Your interest is private. We'll let you know
  only if it's mutual." A non-mutual outcome never blames anyone.
- Empty states explain and offer at most one action. Sending nothing is treated as normal.
- Errors say what was saved, what was not, and what the member can do. Retry is always
  available for recoverable failures.

## 3. Make use of the periphery

Information should move between the periphery and the centre of attention easily, and most
of it should stay in the periphery.

- Status lives in small, quiet signals: a status pill, a tab badge that counts only actionable
  items, a company mark next to a name. Nothing pulses, bounces, or animates to attract the
  eye.
- Notifications are the only thing that reaches a member outside the app, and only for the
  five meaningful moments: an introduction is ready, interest is mutual, a message arrived, a
  meeting is coming up, feedback is due. Their copy is short and never includes message
  bodies.
- Available Today is a light, temporary signal with a visible expiry, not a status the member
  has to manage.

## 4. Amplify the best of technology and the best of humanity

Technology should not try to be human; it should make people more able to be human with each
other.

- The product introduces and then steps back. Messaging exists to arrange a coffee; the
  relationship happens in person.
- Introductions explain reciprocal professional value in the member's own words and context.
  There is no compatibility score, no ranking, and no "AI-powered" label; the reasoning is
  visible and the machinery is not.
- Members write their own ambition. The product may draft facts from a résumé, never goals,
  personality, or what someone is willing to give.

## 5. Communicate without speaking

Technology can convey status through simple signals and should not narrate.

- Symbols, monograms, and company marks identify people and companies at a glance without a
  photo before mutual interest.
- Sound is used only for the system notification sound. The app never plays its own.
- Progress is shown with native, indeterminate indicators and real stage names, not with
  playful loaders or skeleton people cards.

## 6. Work even when it fails

Technology should degrade gracefully and never leave a person stranded.

- The app opens to its last known state and refreshes when it can. Realtime updates are an
  enhancement; returning to the foreground always refreshes.
- Every network action has an offline state that says whether it was saved, queued, or not
  submitted, and offers retry.
- A company mark that cannot load falls back to a monogram. A notification that cannot be
  delivered leaves the in-app state intact. A missing configuration on the server records a
  failure instead of crashing.
- Membership expiry pauses only new introductions; existing conversations and connections
  keep working.

## 7. Use the minimum amount of technology needed

The right amount of technology is the least that solves the problem.

- Passwordless magic links instead of passwords, codes to copy, or social login.
- Coarse, temporary location instead of continuous tracking or maps.
- Plain-text messages with timestamps instead of reactions, voice notes, stories, or
  disappearing content.
- Native platform controls, focus, and accessibility instead of custom re-implementations.
- One monthly membership after one free month; nothing gamified, nothing upsold in flows.

## 8. Respect social norms

Technology should fit the norms of the people using it, in the situations they are in.

- Interest is private until it is mutual, because that is how professionals actually behave.
- Passing is easy and socially inexpensive; nobody is told they were passed on.
- Verification means control of a company email and says so; the product never implies
  employer endorsement.
- Safety actions (report, block, end) are always reachable, never prominent, and never
  performative.
- Gender is not collected, displayed, filtered, or ranked on. The network is never split into
  pools.

## How to apply this

When a proposal is on the table, ask in order: does it reduce or add attention? Does it inform
or alarm? Can it live in the periphery? Does it help two people meet, or does it keep them in
the app? Can it fail quietly? Is there a simpler way? Would a thoughtful professional find it
normal? A proposal that fails any question is redesigned or dropped. These questions are the
Calm Technology check required by the constitution at the specification and plan gates.
