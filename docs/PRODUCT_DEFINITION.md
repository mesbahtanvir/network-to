# Product definition: who network.to is for

**Status**: Adopted 2026-09-11, amended 2026-09-12 · Owner: product owner · Referenced by: `.specify/memory/constitution.md` Principle I (the constitution wins on conflict; changes to the audience or the widening order here are constitution amendments made in the same PR)

## The person we build for

network.to is for someone who has just moved to a big North American city, works in
technology, and wants to find like-minded people: people with shared goals and things to do
together, without romantic or sexual tension, and without the transactional feel of
networking events. They are not looking for a quick interaction. They want a few genuine
relationships that are built slowly, in person, and that survive a job change.

The canonical member: moved to Toronto in the last year or two, works at a technology company,
and wants to build a startup. They know the people they need exist in the city. They do not
know where to find them, and cold outreach feels wrong. network.to answers the question "where
do I find these people?" by bringing one worthwhile person to them at a time, with a reason to
meet, and by making the first coffee easy to arrange.

## Primary and secondary members

- **Primary: the newcomer builder.** New to the city (typically within two years), employed in
  technology, ambitious about a concrete goal such as founding a company, joining an early
  team, changing specialty, or leading a larger organization. Wants peers and adjacent people
  who are working toward similar things and would enjoy doing things together: coffee, a
  walk, a co-working afternoon, a talk, a weekend project.
- **Secondary: the resident whose network went stale.** Has lived in the city for years, but a
  job change, a return from parental leave, a move to remote work, or a shift in ambition left
  their professional circle out of date. Same need, same product.
- **Secondary: the founder or early builder looking for collaborators**, while they still hold
  a qualifying work email (founders without one are not members until step 2 below). Wants to
  meet people who might later become a co-founder, a collaborator, or a peer a few months
  ahead. Hiring and fundraising are not reasons to join and matching never uses them.

## What members are looking for

- Shared goals before shared interests: someone moving toward a similar destination, even
  from a different company or industry.
- Things to do together in the real world, starting with a 1:1 coffee and continuing however
  the two people choose. The product's job ends when the meeting is arranged and the private
  feedback is recorded.
- A relationship that is allowed to be slow. One good introduction a week is plenty; none is
  better than a weak one.
- Safety and clarity: a verified work email at a listed company (verification means only that,
  and the product says so), no gender data or filters, no romantic framing, easy private
  passing, blocking and reporting that work.

## Who we are not building for

- People looking for dates or hookups. The product has no photos before mutual interest, no
  swiping, no compatibility scores, and no romantic vocabulary, and it never will.
- Recruiters, salespeople, and investors prospecting for candidates, customers, or deals. There
  is no directory, no search, no cold messaging, and no way to contact someone without a mutual
  introduction.
- People seeking an audience: no feed, no followers, no public profiles, no popularity signals.
- People who want to browse. Today shows one introduction or one next action, never a list.

## Where we start and where we go next

We start with technology because verification is simple (a company email at a listed
technology company) and shared goals are easy to articulate; Toronto is the first city we
expect to reach useful density. The verified company registry is therefore a curated list of
well-known North American technology companies and technology employers, expanded only by a
product decision recorded in a migration (constitution, Product and Platform Constraints),
with company marks so a verified company is recognisable at a glance.

Today: technology employees at listed companies in any North American city. Matching is
same-city, so a city works only once it has enough members. Role is never a gate: anyone with
a work email at a listed company is a member, whatever their job.

The audience widens deliberately, in this order:

1. Employers adjacent to technology: fintech and health-tech operators, technology-focused law
   and accounting firms, research labs, and design or data consultancies. A registry migration
   as a product decision.
2. Founders and independent builders without a company email, once a verification path that
   does not depend on an employer domain exists. This admits members without a qualifying work
   email, loosens constitution Principle IV, and requires a MAJOR amendment before any spec is
   written.
3. Wider professional audiences, once the introduction quality bar can be maintained without
   the company signal. Also a MAJOR amendment to Principle IV.

Widening the audience never changes the shape of the product: one same-city introduction at
a time, reciprocal interest as the only gate, and an in-person 1:1 meeting as the outcome.

## Success signals

Product success is measured by real-world outcomes, not engagement:

- Time to first introduction: median days from onboarding completion to first introduction,
  and the share of members with none after seven days. Both are reviewed, never driven to zero
  by lowering the quality threshold.
- Members meet in person: the share of mutual introductions that lead to a recorded meeting.
- Members record private feedback: the share of feedback-due meetups where feedback is
  recorded within seven days. The single `feedback_due` notification is the only prompt; no
  other re-engagement notification exists.
- Connections persist: the share of connections still present (not ended or blocked) 90 days
  after creation. Measuring survival across a job change would need recorded company changes,
  which do not exist yet and are a separate product decision.
- In feedback interviews, members say they would tell a newly arrived colleague about the
  product. This is asked, not instrumented: no invite feature or referral tracking is implied.

## Vocabulary

Use the canonical vocabulary in `docs/UI_DESIGN_SPEC.md` section 12 (Introduction, Interested,
Pass, mutual interest, conversation, Connection, Meet, member, Available today, Verified
company, company mark). Describe members as newcomers, builders, and peers; never as matches,
singles, leads, candidates, users, or followers. "Audience" is used only in this document and
the constitution for whom the product serves, never for members in copy.
