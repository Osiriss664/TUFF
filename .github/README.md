# TUFF + Web Research (fork)

This is a personal fork of **[TUFF](https://github.com/rexmhall09/TUFF)** by
[rexmhall09](https://github.com/rexmhall09). TUFF does all the hard work: it
runs language models locally on Apple Silicon Macs, with a native Mac app, a
Swift and Metal inference engine, command-line tools and a local
OpenAI-compatible server. All credit for TUFF itself goes to its author and
contributors. For TUFF downloads, documentation and support, please use the
[original repository](https://github.com/rexmhall09/TUFF).

TUFF's own README is unchanged and still lives at [README.md](https://github.com/Osiriss664/TUFF/blob/main/README.md).

## My goal

I want a model running on my own Mac to be able to **research the web**
safely: search, read pages, and write a short report with sources, without
sending my questions to a cloud service and without giving the model any
access to my computer.

The plan:

- **The model stays on the Mac.** TUFF serves it on `localhost` only.
  Ollama works too, since both speak the same OpenAI-style API.
- **The web stays in a sandbox.** Searching and fetching pages happen inside
  a throwaway Linux VM made with
  [Apple container](https://github.com/apple/container). The VM has a
  firewall that only allows the public internet, runs as a non-root user and
  has no access to my files or to other services on the Mac.
- **The model only gets web tools.** It can search and read pages, nothing
  else: no shell, no running files, no writing to the Mac except the final
  report. Everything that comes back from the web is treated as untrusted
  text.
- **Two ways to use it.** A `tuff research "your question"` command and a
  Research screen in the Mac app.

## Status

This is a work in progress that I run and test on my own Mac first.

- The feature lives on the
  [`feature/web-research`](https://github.com/Osiriss664/TUFF/tree/feature/web-research)
  branch ([draft pull request](https://github.com/Osiriss664/TUFF/pull/1)).
- How it works and how to set it up:
  [docs/WEB_RESEARCH.md](https://github.com/Osiriss664/TUFF/blob/feature/web-research/docs/WEB_RESEARCH.md).
- It has been through several rounds of independent security review and
  prompt-injection tests.
- If it works well, I may propose it to the TUFF project. Nothing has been
  proposed yet.

The `main` branch here follows TUFF's own releases. This page is the only
addition to it.

## Credits and license

- [TUFF](https://github.com/rexmhall09/TUFF) by rexmhall09, licensed under the
  [Apache License 2.0](https://github.com/Osiriss664/TUFF/blob/main/LICENSE). This fork keeps the same license.
- [Apple container](https://github.com/apple/container) for the sandbox VM.
