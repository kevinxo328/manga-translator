---
name: investigate
version: 1.0.0
description: |
  Research an open question with discipline: verify-don't-assume → evaluate → report → exhaustively question. Use whenever the user is making a solution / architecture / setup decision — technology selection, architectural design, third-party option evaluation, configuration choices, feasibility studies, or breaking into an unfamiliar codebase. Triggers include: "investigate", "evaluate", "research", "how should we design X", "what should we use for Y", "is X viable".
allowed-tools:
  - Read
  - Glob
---

# Investigate

A discipline for researching an open question. Four phases, run in order. Skipping any phase requires stating why and getting the user's agreement first.

## Core Principle

**Do before think.** Every conclusion must rest on verifiable evidence. Assumptions do not count as evidence.

## Anti-Pattern: Evaluating from Unverified Premises

**DO NOT discuss the merits of any option before completing Phase 1.**

This produces **garbage conclusions**:

- Intuition scores dressed up as criteria
- Comparing two options when basic facts about neither have been checked
- Inferring real-world quality from a README intro or a paper's metric
- Assuming an API / flag / setting exists without reading source or running the command

```
WRONG (lateral inference):
  "Option A looks good, quality should be fine"  → license/real-sample not checked
  "This library should have a streaming API"     → source not read
  "The current architecture should plug in fine" → relevant modules not read
  "The detector probably catches it"             → overlay images not viewed

RIGHT (verify, then evaluate):
  Read LICENSE → confirm commercial use → then evaluate further
  Read source / run --help → confirm API exists → then design integration
  Read existing modules → confirm interface + coupling surface → then propose architecture
  Read overlay images → confirm detection quality → then talk about metrics
```

---

## Phase 1 — Don't Assume, Verify

Turn every "I think" into "I saw".

### Actions

- [ ] Write down every premise this question relies on (do not keep them in your head)
- [ ] Pair each premise with the cheapest possible verification action
- [ ] Run the verifications. If a premise turns out false, stop and reframe the question

### Verification Tools, in Priority Order

1. `Read` files / overlay images > grep-and-guess from filenames
2. Run `--version` / `--help` / an actual invocation > read README
3. Read LICENSE > read README intro
4. Read source > trust docs
5. Test on real samples / real environment > look at metrics or marketing

### Red Flags (Stop When You See One)

- Sentences containing "should", "in theory", "probably", "looks like", "I recall"
- Comparing third-party options without having opened LICENSE
- Discussing architectural integration without having `Read` the relevant modules
- Discussing detection / quality without having opened overlay / benchmark images
- Inferring an API / flag / setting from training-data memory

### Phase 1 Done Condition

- [ ] A table exists: `premise → verification method → result`
- [ ] No conclusion below rests on an unverified premise

**Without this checklist complete, do not enter Phase 2.**

---

## Phase 2 — Evaluation with Explicit Criteria

Pick the criteria set that matches the research type. Check criteria in order; any fail eliminates the option — do not continue to the next criterion.

### Third-Party Option / Model / Library

- [ ] License permits the target use case (production / commercial / etc.)
- [ ] Compatible with the existing stack (no major rework)
- [ ] Resource cost is acceptable (weight size, memory, runtime)
- [ ] Real-sample quality is acceptable (**measured**, not metrics or marketing)
- [ ] Maintenance is acceptable (active repo, no large unresolved issue backlog)

### Architecture / Design Proposal

- [ ] Solves the real problem (not a related-sounding but unimportant one)
- [ ] Reversibility is acceptable (cost and feasibility of rolling back)
- [ ] Coupling surface is acceptable (how many modules / tests are affected)
- [ ] Consistent with existing conventions (or there is an explicit reason to diverge; consult relevant ADRs)
- [ ] Better than the current approach — and worse — both written down

### Configuration / Setup Decision

- [ ] The effect of the setting has been verified in the real environment (not inferred from docs)
- [ ] Blast radius is clear (which files / flows / users are affected)
- [ ] Default and override behaviour have both been tried
- [ ] The change is reversible

### Anti-Pattern: Averaging Away a Hard Fail

**DO NOT use "but the other criteria look great" to cover a hard fail.**

A hard-criterion fail (license, reversibility, compatibility) is a fail. It cannot be compensated by other criteria.

### Phase 2 Done Condition

- [ ] Every criterion has Phase 1 evidence attached (file path / command output / screenshot)
- [ ] No score is an "impression score"

---

## Phase 3 — Structured Report

**Default: report inside the conversation only. Do not write files, open changes, or write memory on your own initiative.**

### Report Format

```
## Conclusion
One sentence: feasible / not feasible / undecided, plus the single deciding factor.

## Verified Premises (Phase 1)
- premise → verification method → result

## Evaluation (Phase 2)
| Criterion | Result | Evidence (file path / command output) |
|-----------|--------|----------------------------------------|
| ...       | ✅/❌  | ...                                    |

## Unanswered Questions
- ...

## Recommendation
- Recommended next step, and why
```

### Anti-Pattern: Pushing the Next Step

**DO NOT end the report with "Should we start work?" / "Should we open a change?" or similar.**

After reporting, wait for the user to decide. Persistence actions (writing a research file, writing memory, opening a ticket) happen only after the user explicitly asks.

---

## Phase 4 — Exhaustive Questioning

The second-biggest failure mode in research is **stopping at the first plausible answer**.

### Questioning Checklist (Attempt Each At Least Once)

- [ ] **Are there other options?** List at least two alternatives and evaluate them with the same criteria
- [ ] **Under what conditions would this conclusion be wrong?** Imagine a scenario that overturns it; if you can't, verification is probably insufficient
- [ ] **What is the worst case?** Blast radius and rollback cost when the option fails
- [ ] **What did I skip?** Re-read the Phase 1 red-flag list and confirm no hidden premise remains
- [ ] **Will this conclusion still hold in 6 months?** Will the license change? Will the library deprecate? Will requirements shift?

### Stop Conditions

You may stop only when one of these is true:

- Every question above has a clear answer and none of them breaks the Phase 2 conclusion
- Remaining questions need information only the user has, and they are listed under "Unanswered Questions" in the report
- The user has explicitly said you may stop

"I'm tired" / "this is probably enough" are **not** stop conditions.

---

## End-of-Phase Self-Check

```
[ ] Did I skip verifying any premise in Phase 1?
[ ] Did I use an impression as evidence?
[ ] Did I write a file / open a change / write memory on my own initiative?
[ ] Did I cut Phase 4 short?
```

If any answer is "yes", return to the matching phase and redo it.
