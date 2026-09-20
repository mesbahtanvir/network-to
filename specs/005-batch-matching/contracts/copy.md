# Copy Contracts: Explanations and Meeting Context

Member-facing text created by `private.compose_introduction_copy`. Canonical vocabulary only;
no exclamation points, no urgency, no score, no "AI"; the other member is named by first
name or referred to as "they". Every piece comes from what the members chose or wrote; an
empty piece is omitted with its sentence. Area names are lower-cased on their first letter
unless the term starts with an acronym (`private.lower_first_word`). Free text is quoted
verbatim inside typographic quotes.

Notation: the reader is R, the other member is O. `first(O)` is O's first name (the text
before the first space of `name`, or the whole name). `g_R` is R's growth area served by O,
`c_O` is O's contribution area that serves it, `help_O` is the first of O's help formats,
`words_O` is O's `contribution`, `ambition_O` is O's `professional_ambition`.

## Why you should meet (`reason_for_R`)

```text
You want to grow in {g_R}. {first(O)} offers {c_O}[ and can {lower(help_O)}].[ In their words: “{words_O}”][ What {first(O)} is working toward: “{ambition_O}”]
```

Example: *You want to grow in platform strategy. Maya offers product strategy and can
compare approaches. In their words: “Lessons from building product teams and developer
platforms from early stage through scale.” What Maya is working toward: “Help build a
durable product company and mentor the next generation of technical product leaders.”*

## Why they may want to meet you (`reciprocal_for_R`)

```text
{first(O)} wants to grow in {g_O}. You offer {c_R}[ and can {lower(help_R)}].[ In your words: “{words_R}”]
```

Example: *Maya wants to grow in executive communication. You offer engineering leadership and can
review a challenge. In your words: “Experience scaling distributed platforms and engineering
organizations.”*

## Meeting context (`meeting_context`, unchanged wording)

```text
You are both in the same city and prefer {format} around {area}. Confirm a public place together after mutual interest.
```

`format` is the first shared format in member A's order, lower-cased on its first letter.
`area` is the first shared area in member A's order other than "Flexible within the city";
when the overlap is only through one member's flexibility, it is the first area of the member
who is not flexible. When both are flexible the sentence reads "You are both in the same city
and prefer {format} and are flexible about where in the city. Confirm a public place together
after mutual interest." When the members share no format, `format` falls back to "a coffee".

## Rules checked by pgTAP

- Both explanations of an introduction name the served growth area and the serving
  contribution area for their reader.
- "Why you should meet" quotes the other member's `contribution` and `professional_ambition`
  when present and omits the sentence when empty.
- No text contains "!" or the words match, compatibility, score, like, swipe, deck, streak,
  or AI.
- Existing rows keep their previous display after the backfill.
