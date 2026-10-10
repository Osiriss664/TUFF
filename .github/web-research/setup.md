# Setup and use

Web research is still on its own branch, so you build it yourself from the
source code. That takes a few commands in Terminal. You only need to do the
setup once.

[Back to the front page](../README.md) ·
[How it works](how-it-works.md) · [Safety](safety.md) ·
[Test results](test-results.md) ·
[Technical reference](technical.md)

## What you need

- A Mac with Apple Silicon (M1 or newer) and **macOS 26**. Apple's container
  tool needs macOS 26 for its network features.
- **Apple container**, installed from its
  [releases page](https://github.com/apple/container/releases) (download the
  installer package and open it).
- **Xcode** (the full app from the App Store, with Swift 6.2 or newer), to
  build TUFF. The command line tools alone are not enough.
- A model installed in TUFF (on its Models screen). Good choices:
  - **Gemma 4 E4B**: fast, a good start.
  - **Qwen3.6 35B-A3B**: better answers, about 1 to 8 minutes per question
    on a 16 GB Mac.
  - **Gemma 4 26B-A4B**: careful and well sourced, about 1 to 7 minutes per
    question.

## Build it (once)

Copy each line into Terminal and press Return. Wait until one finishes before
you start the next.

```sh
git clone https://github.com/Osiriss664/TUFF.git TUFF-research
```

```sh
cd TUFF-research
```

```sh
git checkout feature/web-research
```

```sh
swift build -c release
```

The first build can take a while. Then start the app you just built:

```sh
.build/release/TUFF
```

Leave this Terminal window open while you use the app. For the other
commands on this page, open a new Terminal window and go to the folder
again with `cd TUFF-research`.

## Use it in the app

1. Open the **Research** screen (Command-2).
2. Click **Start Both**. This starts the model server and a fresh sandbox VM.
   The first time, it also builds the sandbox, which takes a few minutes.
3. Wait until the safety check passes. Questions stay switched off until it
   does.
4. Type your question and start it. You see each search and page read as it
   happens. Turn on **Show thinking** to also see the model's reasoning.
   Your Mac stays awake while the question runs.
5. The finished report appears in the sidebar. Reports are saved as Markdown
   and JSON in `~/Library/Application Support/TUFF/Research Reports`. If a
   question fails or you press Stop after it searched or read something, a
   report without an answer is saved too, listing what was found.

Useful controls:

- **Steps** sets how many search and read rounds the model gets (default 8,
  up to 100). 8 to 12 works well for Qwen3.6; more steps allow longer
  searches.
- **More Options** shows every other setting: thinking, token limit, page
  size, prompt budget, results per search, tool calls per step, pages to
  read, step time limit, thinking time limit (how long the model may think
  on one step, 3 minutes by default), and switches for the safety nets. The app keeps
  your choices; **Restore Defaults** resets them.
- **Stop Research** cancels the current question, and the model stops
  working on it right away, so the next question can start at once.
- **Stop Both** stops the model server and removes the sandbox VM. The
  switch next to each one turns just that one on or off.
- **Run Safety Check** runs the full sandbox self-test.

Run only one model at a time on a 16 GB Mac. Quit other model work first.

## Use it in Terminal

In the `TUFF-research` folder, build and start the sandbox:

```sh
Scripts/research_sandbox.sh build
```

```sh
Scripts/research_sandbox.sh start
```

Start the model server: either turn on **Background API** on the TUFF app's
Server screen, or run this in a second Terminal window. It serves the model
selected in the app, so select a model there first, or add
`--default-model <name>` to pick one.

```sh
.build/release/TUFFCommand serve
```

Then ask a question:

```sh
.build/release/TUFFCommand research "How does Apple container isolate each container?"
```

The answer is printed with numbered sources. The Mac stays awake while it
runs. If the run fails after it searched or read a page, the report without
an answer is still printed (and written to `--output`), and the command ends
with an error status. Useful options:

| Option | What it does |
| --- | --- |
| `--output notes.md` | Also saves the report to a new file. |
| `--max-steps 12` | Gives the model more search and read rounds (1 to 100, default 8). |
| `--min-pages 4` | How many pages it should read (1 to 6, default 3). |
| `--search-results 8` | Results per search (1 to 10, default 5). |
| `--show-thinking` | Turns on the model's reasoning and prints it. |
| `--passages on\|off` | Read the best matching passages of a page first (default off: it read more sources but made some answers worse). |
| `--help` | Lists every option, including the safety-net switches. |

When you are done, stop and remove the sandbox VM:

```sh
Scripts/research_sandbox.sh stop
```

## Updating later

In the `TUFF-research` folder:

```sh
git pull
```

```sh
swift build -c release
```

The app rebuilds the sandbox by itself when it changed. In Terminal, run
`Scripts/research_sandbox.sh build` again.

## Optional settings

- **Your own search engine.** Set `SEARXNG_URL` before starting the sandbox
  to use your own [SearXNG](https://docs.searxng.org) instead of DuckDuckGo.
- **Public DNS.** By default the sandbox looks up names through your Mac.
  To keep it away from your Mac completely, start it with
  `TUFF_RESEARCH_DNS="1.1.1.1 9.9.9.9" Scripts/research_sandbox.sh start`.

More detail is in the full guide,
[docs/WEB_RESEARCH.md](https://github.com/Osiriss664/TUFF/blob/feature/web-research/docs/WEB_RESEARCH.md).
