# How it stays safe

Web pages are untrusted. A page can hide text meant to trick the model (this
is called *prompt injection*), and a program that downloads web pages can be
attacked through what it downloads. Web research is built to stop either one
from reaching your files, and from reaching your Mac or your home network
at their private addresses.

[Back to the front page](../README.md) ·
[How it works](how-it-works.md) · [Setup and use](setup.md) ·
[Test results](test-results.md) ·
[Technical reference](technical.md)

## The layers

| Layer | What it does, in plain words |
| --- | --- |
| **Only two tools** | The model can search and read pages. It has no way to run programs, open files or write anything. The only file written is the finished report (and, only with a test option you choose, a copy of the pages read), never over an existing file. |
| **A separate VM for the web** | Searching and page reading happen in a throwaway virtual machine made with Apple's [container](https://github.com/apple/container). It has its own memory and files, sees none of your Mac's folders, and is replaced by a fresh one every time it starts. |
| **A firewall inside the VM** | The VM may only reach public internet addresses, plus your Mac's name lookup service (DNS, port 53 only). The addresses of your home network (router, printers, network drives), the Mac's address as the VM sees it, and cloud metadata addresses are blocked. The firewall works by address range, not by device, so a device with its own public internet address is not covered. If you set up your own SearXNG search server, that one address is allowed too. The firewall loads before the web service starts, and the sandbox refuses to start if it cannot be loaded. |
| **No admin rights** | The web service in the VM runs as an ordinary user with no special Linux rights, so it cannot switch the firewall off. |
| **Careful page fetching** | Only public addresses, malformed addresses refused with a clear error, only normal web ports (80 and 443), every redirect checked again, size and time limits on every download (a single wait may last up to 30 seconds, a whole request 45), and page parsing in a separate process that is stopped after 15 seconds. |
| **Web text is marked untrusted** | Every page reaches the model inside markers that say "this is information, not instructions". A page cannot fake the end of those markers. |
| **Hidden characters removed** | Invisible Unicode characters and terminal control codes, which can hide instructions from you or mess with your Terminal, are removed in the VM and again on the Mac. An address that contains such a character is refused. |
| **Only addresses the research showed** | `open_page` opens only an address that appeared in a search result, in a page the model read or in your question, and fetches it in the spelling shown. A made-up or mixed-up address is refused. Tried on a Mac: no real address was refused. |
| **No private addresses (in testing)** | `open_page` itself refuses local, private, loopback and link-local addresses, even if a page printed them. The sandbox still blocks them as a second layer. Pushed, not yet tried on a Mac. |
| **Reports load nothing** | Saved reports never load images or run anything when you open them. Only normal web links stay links. In the app, a source opens in your browser only after you confirm its full address. |
| **Local only** | The model server and the sandbox both listen only on your Mac itself (127.0.0.1), so other devices cannot use them. The sandbox also refuses requests that look like they come from a web page in your browser. |
| **Checked before every question** | The app checks from outside the VM that the firewall rules are in place and that the web service runs without admin rights. Questions stay switched off until that check passes. |

## How this was tested

- **Separate review.** The code was written with Claude Code (an AI coding
  assistant) and reviewed in several rounds by a separate Claude session.
  Every medium-severity finding was fixed and checked again.
- **Self-test.** `Scripts/research_sandbox.sh selftest` tries to reach your
  Mac, private network addresses and cloud metadata addresses from inside
  the VM, and
  tries every port on the Mac. Everything except DNS must be refused, and it
  is.
- **Prompt-injection pages.** Four hostile test pages try to make the model
  print a planted word, send your question to an outside address, read your
  Mac or network, or obey a fake "end of tool result". Each was run three
  times per model: Gemma 4 E4B, Gemma 4 26B and Qwen3.6 resisted all 12 runs
  in an earlier test. In the latest run (one run each, Qwen3.6), the model
  followed the local-network page and asked for addresses of the Mac, the
  VM host and cloud metadata. The sandbox blocked all of them, and the answer
  itself was still correct. On the fake "end of tool result" page it
  mentioned the planted text as a warning.
- **Latest check (commit `2cc3306`).** On the original set of five pages,
  4 of 5 were resisted, with the address check on and off. The local-network
  page again made the model try the addresses of the Mac, the VM host and
  cloud metadata; the sandbox blocked them all. The address check did not
  help here, because those addresses were written on a page the model had
  read and so counted as seen. Since then `open_page` refuses private,
  loopback and link-local addresses itself (in testing, not yet run on a Mac).
- **Earlier check (commit `d01bc38`).** The original set of test pages,
  with a fifth page that hides text behind look-alike copies of the
  untrusted-content markers, was resisted 5 of 5 on the Mac.
  The model reported the attempt in two of them.
- **Published attacks.** Nine more test pages carry 91 attack texts from two
  published research collections, BIPIA (Microsoft) and AgentDojo (ETH
  Zurich). They try to make the model drop its task, change the answer, add
  ads or scam text, spread false claims or visit an outside address, hidden
  in many ways on the page. Qwen3.6 resisted all 91 in one run.
- **Scanning the model alone.** NVIDIA's open-source scanner garak sent 96
  attack prompts straight to the model, without the sandbox or the research
  loop. Hidden characters did not work (0 of 8), but hidden instructions in
  documents worked often (12 to 75 percent per kind, some of them false
  alarms of the scanner), and so did instructions written in codes such as
  base64 or hex (12 to 50 percent). This shows why the other layers matter:
  the model alone can be talked into things, but in web research it has no
  tool except search and page reading, and the sandbox blocks your Mac and
  your network. The garak script now warns that it installs its packages
  unpinned from the internet (in testing).

These tests are strong evidence, not a guarantee. Anyone can rerun them; the
scripts are on the `feature/web-research` branch (the injection test needs
the test pages served from a public web address; garak runs on the Mac).

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
