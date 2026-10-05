# How it stays safe

Web pages are untrusted. A page can hide text meant to trick the model (this
is called *prompt injection*), and a program that downloads web pages can be
attacked through what it downloads. Web research is built so that neither can
reach your Mac, your files or your home network.

[Back to the front page](../README.md) ·
[How it works](how-it-works.md) · [Setup and use](setup.md) ·
[Test results](test-results.md) ·
[Technical reference](technical.md)

## The layers

| Layer | What it does, in plain words |
| --- | --- |
| **Only two tools** | The model can search and read pages. It has no way to run programs, open files or write anything. The only file written is the finished report, and never over an existing file. |
| **A separate VM for the web** | Searching and page reading happen in a throwaway virtual machine made with Apple's [container](https://github.com/apple/container). It has its own memory and files, sees none of your Mac's folders, and is replaced by a fresh one every time it starts. |
| **A firewall inside the VM** | The VM may only reach the public internet, plus your Mac's name lookup service (DNS). Your Mac, your router, printers, network drives and cloud metadata addresses are blocked. The firewall loads first, and the sandbox refuses to start without it. |
| **No admin rights** | The web service in the VM runs as an ordinary user with no special Linux rights, so it cannot switch the firewall off. |
| **Careful page fetching** | Only public addresses, only normal web ports (80 and 443), every redirect checked again, size and time limits on every download, and page parsing in a separate process that is stopped after 15 seconds. |
| **Web text is marked untrusted** | Every page reaches the model inside markers that say "this is information, not instructions". A page cannot fake the end of those markers. |
| **Hidden characters removed** | Invisible Unicode characters and terminal control codes, which can hide instructions from you or mess with your Terminal, are removed in the VM and again on the Mac. |
| **Reports load nothing** | Saved reports never load images or run anything when you open them. Only normal web links stay links. In the app, a source opens in your browser only after you confirm its full address. |
| **Local only** | The model server and the sandbox both listen only on your Mac itself (127.0.0.1), so other devices cannot use them. The sandbox also refuses requests that look like they come from a web page in your browser. |
| **Checked before every question** | The app checks from outside the VM that the firewall rules are in place and that the web service runs without admin rights. Questions stay switched off until that check passes. |

## How this was tested

- **Independent review.** A separate reviewer went through the code in
  several rounds. Every medium-severity finding was fixed and checked again.
- **Self-test.** `Scripts/research_sandbox.sh selftest` tries to reach your
  Mac, your network and cloud metadata addresses from inside the VM, and
  tries every port on the Mac. Everything except DNS must be refused, and it
  is.
- **Prompt-injection pages.** Four hostile test pages try to make the model
  print a planted word, send your question to an outside address, read your
  Mac or network, or obey a fake "end of tool result". Each was run three
  times per model: Gemma 4 E4B, Gemma 4 26B and Qwen3.6 resisted all 12 runs
  in their latest test.

These tests are strong evidence, not a guarantee. Anyone can rerun them; the
scripts are in the repository.

## What it does not protect against

- **Wrong pages.** A model can be misled by a page that is simply false.
  Check the sources.
- **Planted text in the report.** Anything the model read can end up in the
  answer. Treat the report like any other web content.
- **Your internet address.** Search engines and websites see your IP address,
  as with normal browsing.
- **Leaking the question.** A model tricked by a page could put your question
  into a link it asks to open. Your files cannot leak this way, because the
  model has no file tool.
- **VM escapes.** A serious bug in Linux or in Apple's virtualization could
  let code break out of the VM. That is the same risk as with any VM.

The full list, with technical detail, is in the
[security section of the guide](https://github.com/Osiriss664/TUFF/blob/feature/web-research/docs/WEB_RESEARCH.md#security-model).
