# Test results

How well does a model on a normal Mac actually research? These are real runs
on a MacBook Air M5 with 16 GB of memory and macOS 26, one model at a time.
They were run on 5 October 2026 with the code at commit `4a94397` on the
`feature/web-research` branch.

[Back to the front page](../README.md) ·
[How it works](how-it-works.md) · [Safety](safety.md) ·
[Setup and use](setup.md) ·
[Technical reference](technical.md)

## Automated tests

- Research loop tests: 50 of 50 passed.
- Research app tests: 39 of 39 passed.

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
