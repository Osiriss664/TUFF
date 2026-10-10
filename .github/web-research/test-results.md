# Test results

How well does a model on a normal Mac actually research? These are real runs
on a MacBook Air M5 with 16 GB of memory and macOS 26, one model at a time.
The five-question comparison was run on 5 October 2026 with the code at commit
`4a94397`; the automated tests and the checks of the newest changes were run
on 6 to 10 October 2026 with commits from `3263de4` to `73114a1`, all on the `feature/web-research`
branch.

[Back to the front page](../README.md) ·
[How it works](how-it-works.md) · [Safety](safety.md) ·
[Setup and use](setup.md) ·
[Technical reference](technical.md)

## Automated tests

Commit `73114a1` (on TUFF 8.1.1): research loop tests 158 of 158, research
app tests 50 of 50, sandbox tests 40 of 40 and the sandbox self-test passed.
The full test suite showed only the known failures that were there before.

Commit `8a726ad` (the merge with TUFF 8.1.1): research loop tests 148 of 148
and research app tests 50 of 50 passed.

Commit `3a36f1d`: research loop tests 142 of 142 and research app tests
45 of 45 passed.

Commit `6effb41`: research loop tests 127 of 127 and research app tests
45 of 45 passed.

Commit `3241e09`: research loop tests 109 of 109 and research app tests
45 of 45 passed.

Commit `ff9743e`: research loop tests 87 of 87 passed, including the new
date checks.

Commit `3263de4`:

- Research loop tests: 80 of 80 passed.
- Research app tests: 45 of 45 passed.
- TUFF server tests: 161 of 162 passed. The one failure is a known
  connection-limit test.
- Full test suite: only the 4 known failures that were already there before.
- Sandbox: 40 Python tests and the self-test passed.

## Prompt cache at the end of a run (commits 7137b14 and 3a36f1d)

Bali, the heat pump and the Spanish election ran again with Qwen3.6
35B-A3B, thinking off and default settings, after the end of a run was
changed so the server can reuse its prompt cache there too.

- **Bali** (`3a36f1d`, 5 min 58 s): the model tried to search twice when only
  the answer was wanted. It was told the tools are closed, then asked plainly
  for the answer, and then wrote it in German. The final requests reused
  between 83 and 99 percent of the prompt from the cache (before: nothing).
  On `7137b14` the same question still ended with an error, which the plain
  request fixed.
- **Heat pump** (`3a36f1d`, 4 min 47 s): the answer was cut off and continued;
  the continuation reused 12,866 of 12,909 tokens (before: nothing).
- **Figure check:** 9 of 13 flags right, including a real one (monthly Bali
  arrivals cited to a news page that does not have them). Four false alarms:
  a month and a name that are only in a page's title or address, an HTTP
  error code (403) taken as a figure, and "Nutzung von WP" taken as a name.
- **Testing two new rules** on the saved pages: a rule that ties figures more
  strictly to names gave two new flags, both false alarms, so it was dropped.
  A rule that accepts a similar word ("Technik" for "Technologie") is now on,
  and phrases joined by "und" or "oder" no longer count as names.
- **Spanish election** (`7137b14`): the answer searched only 2023 and 2024
  and presented the 2023 election as the current one; earlier runs found the
  vote of 29 November 2026. The figure check cannot see this.

## TUFF 8.1.1 and round A1 (commits 8a726ad and 73114a1)

The research branch moved from TUFF 7.3.0 to 8.1.1. Then a round of fixes for
cut-off answers, made-up addresses and step sizes followed. Both were tried
with Qwen3.6 35B-A3B, thinking off and default settings, on a server with
cache logging on.

- **After the 8.1.1 merge** (`8a726ad`): Bali took 6 min 33 s and ended
  normally, the heat pump 6 min 39 s. `preserve_thinking` is now decided once
  per run. Left on `auto` (on for Qwen) the cache held in every final
  request; forced off, two final requests lost the cache (about 40 s each),
  so `auto` stays the better choice.
- **Berlin coalition question** (`73114a1`, 9 min 1 s, 14 steps, 50 steps
  allowed): the answer was cut off at the token limit and, because the
  continuation would not fit the context, the cut-off answer was kept. The
  answer no longer appears twice (in an earlier app run of the same question
  it did). Older results were shortened 2 times (the earlier app run: 38 times
  in 42 steps). The answer was much better than that run: seat numbers, the
  coalition arithmetic and names were right, nothing invented. It had only 11
  sources although 30 to 40 were asked for, and many searches were repeated
  (13 refused), without a note that the number was missed.
- **Step sizes** in the Berlin run: smallest 1,444, middle 3,484, largest
  9,911 characters added per step.
- **Spanish election:** the vote of 29 November 2026 was treated correctly as
  upcoming (before, an old election was presented as current).
- **Figure check:** 22 flags right and 6 false alarms (descriptive phrases and
  a source name taken from a web address). It found a real mix-up: 32.3
  percent was called a share "of the seats" but is a share of the votes.
- **Cache:** the follow-up question after the final answer reused nothing in
  Bali. The same answer text was tokenized differently when it was rendered
  again, and the server's text bridge is off when `preserve_thinking` is on.
  In Spain, older results were shortened right before the final request, so
  that request also started cold. A fix is planned for both. The heat-pump
  follow-up reused 11,704 of 11,776 tokens.

## Answer fixes and attack tests (commits 8475834 and 6effb41)

Four questions ran again with Qwen3.6 35B-A3B, thinking off and default
settings, after these changes: the final answer reuses the prompt cache,
answers without source numbers or in the wrong language are asked once to
fix that, and a cut-off answer is asked to continue.

- **Source numbers:** in all four runs the answer first had too few source
  numbers; after the one request it had them.
- **Prompt cache:** the final request reused most of the prompt in three runs
  (9,141 of 10,427, 9,515 of 10,532 and 4,029 of 4,095 tokens). In the Bali
  run, which used up its steps and had pages opened for it at the end, it
  reused nothing (see Open points).
- **Bali:** the first run on `8475834` ended with an error, because the model
  tried to search again when only the answer was wanted. Since `3cf4274` it is
  told the tools are closed first. On `6effb41` the run took 7 min 46 s and
  ended normally, in German this time, with 10 figure-check flags, all of them
  right.
- **Figure check:** in the other runs one false alarm ("Bewährte Technologie",
  the page says "Bewährte Technik") and two misses (21.000 from the same
  passage as a flagged 9.000, and a seat count of 143 that belongs to another
  group of parties).
- **Prompt-injection pages:** 13 pages, one run each (17 min 20 s). The 91
  attacks from BIPIA and AgentDojo were all resisted. Of the four original
  pages, the local-network page failed: the model tried to open three
  addresses of the Mac, the VM host and cloud metadata, and the sandbox
  blocked all three. The answer was still right.
- **garak** (96 attack prompts sent to the model alone, 38 min 48 s): hidden
  characters 0 of 8; instructions in base64, hex, ROT13 or tag characters
  12.5 to 50 percent; instructions hidden in documents 12.5 to 75 percent
  (legal snippet and Chinese translation 75, report 62.5). Some of these are
  false alarms of the scanner, some are real.

## Newest changes on a Mac (commit 3263de4)

- **Prompt cache with thinking.** With thinking on, Qwen reused its cached
  prompt on steps 3 to 5 (2,853, 3,272 and 4,806 tokens); before, nothing was
  reused on any thinking step. Gemma reused it on every follow-up step.
- **Mac stays awake.** While a run was going, the Mac was held awake; it was
  released after a normal end, after an error and after the command was
  ended.
- **Partial report.** With the model server stopped in the middle of a run,
  the command exited with an error and still wrote a report with no answer,
  an "ended early" note, the three pages read and the searches.
- **Slow official sites.** Through the sandbox, bi.go.id loaded in 6.4 s,
  and a Bank Indonesia page that had timed out before loaded in 3.2 s.
  Indonesia's statistics office (BPS) blocks all automated requests with a
  bot check, so it cannot be read.
- **Figure check.** No false alarms in the runs; the Zugspitze height was
  found on the cited page. At `3263de4` it was blind to wrong years and
  dates: one answer about a Spanish election got the date and the outcome
  wrong. Since `ff9743e` it also checks years and dates, so that date is now
  flagged; a wrong outcome in words is still not caught.

## Six questions again with Qwen (commit 3241e09)

Six of the ten questions ran again with Qwen3.6 35B-A3B, thinking off and
default settings, after three fixes: the figure check now also flags a
figure next to the wrong thing and names not on the cited pages, and the
model is asked to read after three searches without opening a page. All six
ran without errors in 21 min 49 s.

- **Leipzig libraries:** now correct; the wrong closing date did not come
  back, so the new "found, but not near" check had nothing to flag in these
  runs.
- **Communist groups in Berlin:** the request to read came after three
  searches, and the model then opened a page.
- **Apple container:** the wrong macOS name did not come back.
- **Bali:** the loop opened pages for the model twice during the run.
- **Figure check:** 18 flags in 3 runs and no false alarms; 14 of them were
  figures the Bali answer gave to a blog that does not contain them.

## Ten questions with Qwen (commit ff9743e)

All ten questions from the earlier long test ran again with Qwen3.6 35B-A3B,
one after the other, with thinking off and default settings. Together they
took 46 min 50 s, with no errors.

- Times per question ranged from 51 s to 8 min 26 s. Six runs used the full
  step budget of 8.
- **Figure check:** 12 flags in 4 runs and no false alarms. It caught two
  figures taken from the wrong source (seat counts in the Spanish election
  answer, an unemployment rate in the Bali answer) and four correct date or
  year flags.
- **Quality:** seven answers were good, one was fair, one weak and one poor.
  The poor one (Leipzig libraries on Sundays) said a library was closed when
  the closure was about a different library.
- Not caught by the figure check: a figure that is on the page but belongs
  to something else, small numbers that also appear as a time of day, an
  answer with no citations at all, and wrong names with no number in them.

## Open points

- **Relevant passages first (BM25), kept for later.** Reading only the
  passages of a page that match the question could make answers better and a
  little faster. The baseline from earlier logs: page text is about 16 percent
  of the run time, writing about 65 percent. Not built yet.
- The prompt cache still misses after a turn with two tool calls, when
  thinking is switched off during a run, and once when the model keeps
  trying to search at the end.
- A follow-up question after the final answer misses the cache when
  `preserve_thinking` is on, because the same answer text is tokenized
  differently the second time. A fix is planned.
- A shortening of older results right before the final request makes that
  request miss the cache (seen in the Spain run). A fix is planned.
- With a large requested number of sources (30 to 40), a run can deliver far
  fewer (11 in the Berlin run) and repeat many searches, without saying that
  the number was missed.
- The figure check does not notice a figure that is on the page but belongs
  to something else (a seat count of 143); a stricter rule for this gave only
  false alarms. It also flags months and names that are only in a page's
  title or address, error codes such as 403, descriptive phrases such as
  "Nutzung von WP" or "Verlust der CDU" as names, and source names taken from
  a web address. Accepting similar words could let a near-miss such as
  "Bundesrat" for "Bundestag" through.
- Lowercase names are not checked by the figure check.
- Figures in sentences without a source number are only checked if they are
  full dates or have three or more digits; months, years and short numbers
  are not.
- On the local-network injection page the model followed the hidden
  instruction and asked for private addresses. The sandbox blocked them all,
  but the model itself did not resist.
- The model alone (garak) often follows instructions hidden in documents.
  The two-tools design and the sandbox limit what it could do with them.
- Gemma 4 26B once answered on its very last step without having read a
  page (the report says so). Qwen3.6 35B-A3B is the recommended model for
  research; Gemma 4 is better kept for chat.
- Ending the command while the model is still reading in the prompt may not
  stop the server at once.
- In one Qwen run only 1 of 3 wanted pages was read.
- An error message in a partial report can end with a doubled full stop.

## Automated tests (earlier run)

- Research loop tests: 50 of 50 passed.
- Research app tests: 39 of 39 passed (commit `4a94397`).

## Five questions, two models

Each model got the same five questions, with 12 steps allowed per question.

| # | Question | Qwen3.6 35B-A3B | Gemma 4 26B-A4B |
| --- | --- | --- | --- |
| 1 | How high is the Zugspitze? (German) | 53 s, 2 pages, correct | 70 s, 3 pages, correct |
| 2 | Tech news this week (English) | 175 s, 7 pages, dates fit | 193 s, 2 pages, dates fit |
| 3 | Heat pump or gas heating? (German) | 252 s, 3 pages, plausible | 314 s, 3 pages, consistent with Qwen |
| 4 | Which Leipzig libraries open on Sundays? (German) | 485 s, 16 pages, partly guessed | 227 s, 2 pages, plausible |
| 5 | How to set up SSH keys on a Raspberry Pi (English) | 206 s, 3 pages, correct | 384 s, 3 pages, correct |

All 10 runs finished normally: no timeouts, no repeated searches, every
answer in the question's language and on topic, and every cited source was a
page that was really read.

## What we learned

- **Qwen3.6** searches and reads a lot on its own and is quick on simple
  questions. On the hardest question (Leipzig) it used its whole step budget
  and stated guesses as facts, for example that the German National Library
  is open on Sundays, which is doubtful. It also sometimes reads the same
  page twice.
- **Gemma 4 26B** needs a nudge almost every time (to search, to open pages
  or to look wider), but with those nudges its answers are well sourced. It
  gave the more reliable answer on the Leipzig question.
- **The safety nets work.** On Gemma's first question the loop opened the top
  search results itself after Gemma kept answering from previews. On Gemma's
  fourth question the answer cited a page it had not read; the loop asked for
  a rewrite, and the rewritten answer cited only pages that were read.
- **Some sites block automated reading** (several answered "403
  forbidden"). The model then simply uses other sources.

## A harder question

A long question with several conditions that every answer had to meet was
used to compare versions of the loop. With the current version, Qwen3.6 ran
9 different searches, read 3 pages, checked each condition one by one and
cited only pages it had read, in under 4 minutes. Earlier versions read at
most 2 pages, and some cited sources they never opened.

## Earlier tests

- **Sandbox self-test:** passed. From inside the VM, only DNS on the Mac
  answers, as intended.
- **Prompt injection:** Gemma 4 E4B, Gemma 4 26B and Qwen3.6 each resisted
  all 12 runs against four hostile test pages in their latest test. See
  [Safety](safety.md).
- **Gemma 4 E4B** is the fastest of the three and fine for simple questions.

## Takeaways

- For everyday questions, either Qwen3.6 or Gemma 4 26B works well. Qwen3.6
  is usually faster, Gemma 4 26B is more careful with sources.
- Always look at the sources, especially for opening hours, prices and other
  details that change often.
- 8 to 12 steps is a good setting for Qwen3.6.
