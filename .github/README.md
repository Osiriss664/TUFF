# TUFF fork: a built-in sandbox for web research

This is a personal fork of **[TUFF](https://github.com/rexmhall09/TUFF)** by
[rexmhall09](https://github.com/rexmhall09). TUFF runs language models locally
on Apple Silicon Macs, with a native Mac app, a Swift and Metal inference
engine, command-line tools and a local OpenAI-compatible server. All credit for
TUFF itself goes to its author and contributors. For downloads, documentation
and support, please use the [original repository](https://github.com/rexmhall09/TUFF).

TUFF's own README is unchanged and still lives at [README.md](https://github.com/Osiriss664/TUFF/blob/main/README.md).

## What this fork is for

This fork is where I build and test the code for TUFF issue
[#38](https://github.com/rexmhall09/TUFF/issues/38): **a sandbox built into
TUFF**, so that TUFF's web research (and later its file search) runs inside a
throwaway Linux VM made with [Apple container](https://github.com/apple/container),
instead of directly on the Mac.

The plan was agreed with TUFF's maintainer in the issue. In short:

- **Off by default.** A new option in TUFF's settings turns the sandbox on. It
  never switches itself on, and it is hidden on macOS versions older than 26.
- **TUFF starts and stops the VM itself.** There is no fallback: when the
  option is on and the sandbox can't run, web research doesn't run either.
- **The web stays in the VM.** Searches and page fetches happen in the VM.
  Pages and PDFs are turned into plain text there, so TUFF only gets finished
  text. A firewall in the VM allows only public internet addresses, and the VM
  runs as a non-root user with a read-only file system and no access to the
  Mac's files.
- **File search gets its own VM, with no network.** It sees only the folders
  you pick, read-only.
- **A prebuilt image.** TUFF downloads the sandbox image and checks its digest
  before using it.

## How the work is split

The feature comes as four small pull requests, each on its own branch:

| # | Branch | What it adds |
| --- | --- | --- |
| 1 | [`sandbox/01-image`](https://github.com/Osiriss664/TUFF/tree/sandbox/01-image) | The sandbox image and the small web server inside it. No change to the app yet. |
| 2 | `sandbox/02-lifecycle` | TUFF starts and stops the web VM. |
| 3 | `sandbox/03-web` | Web research goes through the sandbox, and the settings option appears. |
| 4 | `sandbox/04-files` | File search in a second VM without network access. |

Each one is tested on a Mac first and then merged into
[`sandbox/integration`](https://github.com/Osiriss664/TUFF/tree/sandbox/integration).
Only when the whole feature works there will the pull requests be offered to
TUFF upstream, one at a time.

## Status

- Pull request 1 is done and Mac-tested
  ([fork PR #2](https://github.com/Osiriss664/TUFF/pull/2)).
- Pull request 2 is in progress.
- The code is written with Claude Code (an AI coding assistant), reviewed by
  separate Claude sessions, and tested on my own Mac before it is pushed.

## Earlier research work

Before #38, this fork held a first version of web research for TUFF, on the
[`feature/web-research`](https://github.com/Osiriss664/TUFF/tree/feature/web-research)
branch ([draft pull request #1](https://github.com/Osiriss664/TUFF/pull/1)).
It is no longer developed. The sandbox pull requests above reuse its tested
parts (the sandbox server, page reading, firewall and injection tests). Its
notes are kept for reference:
[how it worked](https://github.com/Osiriss664/TUFF/blob/main/.github/web-research/how-it-works.md),
[safety](https://github.com/Osiriss664/TUFF/blob/main/.github/web-research/safety.md),
[setup](https://github.com/Osiriss664/TUFF/blob/main/.github/web-research/setup.md),
[test results](https://github.com/Osiriss664/TUFF/blob/main/.github/web-research/test-results.md) and the
[technical reference](https://github.com/Osiriss664/TUFF/blob/main/.github/web-research/technical.md).

The standalone companion app [SandSeek](https://github.com/Osiriss664/SandSeek)
grew out of the same research and works with any local model server.

## About this fork's `main`

The `main` branch follows TUFF's own releases. This page and the pages in
[.github/web-research](https://github.com/Osiriss664/TUFF/tree/main/.github/web-research)
are the only additions to it, and they are never part of a pull request.

## Credits and license

- [TUFF](https://github.com/rexmhall09/TUFF) by rexmhall09, licensed under the
  [Apache License 2.0](https://github.com/Osiriss664/TUFF/blob/main/LICENSE). This fork keeps the same license.
- [Apple container](https://github.com/apple/container) for the sandbox VMs.
