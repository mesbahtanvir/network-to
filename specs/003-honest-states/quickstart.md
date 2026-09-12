# Quickstart: Honest States

## Backend

```sh
bash scratchpad/harness/run_db_tests.sh          # local: all migrations, then the pgTAP files
supabase db reset && supabase test db             # with Docker Desktop, as CI does
```

`introduction_privacy.test.sql` must pass with its declared plan; `production_behavior.test.sql`
still exercises matching.

## iOS

```sh
xcodebuild test -project NetworkTo.xcodeproj -scheme NetworkTo \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The iOS workflow runs the same on the PR.

## Manual checks (demonstration build, `--mock-backend`)

1. Open Today, choose Interested: the private waiting state appears. Previews cannot make the
   other member pass; the backend rule is covered by pgTAP.
2. Turn on Available today: the banner appears; no notice. (Failures are only reachable
   through tests, which set the mock's failure trigger.)
3. Save introduction preferences: "Introduction preferences saved" appears only after the
   mock latency, with the success symbol, and dismisses itself.
4. With VoiceOver on, trigger any notice: it is announced; on an error, Retry and Dismiss are
   reachable and at least 44 pt.
5. Turn on Reduce Motion: notices appear without sliding.

## Manual checks (staging backend, two accounts)

1. Two members hold one introduction. Member A passes. Member B's Today is unchanged; B
   chooses Interested and sees the waiting state; nothing arrives on B's phone.
2. Set the introduction's `expires_at` to the past in SQL and run
   `select private.run_retention_maintenance();`. B's next refresh shows "This introduction
   didn't work out" once; Continue returns Today to searching.
3. Repeat with A never answering: identical copy and behaviour.
4. Turn on airplane mode and save meeting preferences: the previous values return, the error
   notice stays with Retry; turn airplane mode off and Retry: "Meeting preferences saved".
5. Submit private feedback in airplane mode: the sheet stays open with the inline error; Retry
   after reconnecting closes it and creates the Connection when chosen.
