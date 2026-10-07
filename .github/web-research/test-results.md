# Test results

How well does a model on a normal Mac actually research? These are real runs
on a MacBook Air M5 with 16 GB of memory and macOS 26, one model at a time.
The five-question comparison was run on 5 October 2026 with the code at commit
`4a94397`; the automated tests and the checks of the newest changes were run
on 6 and 7 October 2026 with commits `3263de4` and `ff9743e`, both on the `feature/web-research`
branch.

[Back to the front page](../README.md) ·
[How it works](how-it-works.md) · [Safety](safety.md) ·
[Setup and use](setup.md) ·
[Technical reference](technical.md)

## Automated tests

Commit `ff9743e`: research loop tests 87 of 87 passed, including the new
date checks.

Commit `3263de4`:

- Research loop tests: 80 of 80 passed.
- Research app tests: 45 of 45 passed.
- TUFF server tests: 161 of 162 passed. The one failure is a known
  connection-limit test.
- Full test suite: only the 4 known failures that were already there before.
- Sandbox: 40 Python tests and the self-test passed.

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

- In two of ten runs the rewrite turn still left one citation to a page that
  was not read (the report says so).
- In one run Qwen only searched for 8 steps and never opened a page; only
  the automatic page opening at the end gave it sources. The reminder to read
  pages only comes when the model answers without using a tool.
- Gemma 4 26B once answered on its very last step without having read a
  page (the report says so). Qwen3.6 35B-A3B is the recommended model for
  research; Gemma 4 is better kept for chat.
- The prompt cache still misses after a turn with two tool calls and at the
  final request without tools.
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
