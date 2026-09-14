# SPEC — Aevum

*The Aevum Harness — a file protocol for running permanent projects with disposable agents.*

An AI coding instance is **mortal**: it is born without memory and dies when its
context window saturates. The project it works on is **immortal** — it outlives
any single instance by orders of magnitude. The bridge between the two is
**memory externalized as files**, under a protocol strict enough that a fresh
instance can sit down and pick up the line without losing anything.

The goal of the whole system is one sentence: **the project accumulates instead
of repeating.**

None of the mechanisms here are new. It is **optimistic concurrency** (a
compare-and-swap on the testimony), an **append-only log** (the coordination
board), **orphan reclaim** with a liveness signal (the dirty-death net), and
**process handoff** (the baton) — pointed at agent instances instead of threads
or servers. The contribution is recognizing that a coding agent is one of those
mortal processes, and giving the pattern a legible shape.

This SPEC is **host-agnostic**: it assumes only an agent that can read and write
files and run a shell. A reference binding to Claude Code lives in
[`adapters/claude-code/`](adapters/claude-code/); other CLIs bind by
implementing §5.

---

## 1. The model (vocabulary)

Containment hierarchy: **brand › house › seat (role × front)**.

- **Seat** — a role held *temporarily* by an instance, addressed `<role> @ <front>`.
  Instances sit, work, and pass the testimony. "The CTO of project X" is not an
  instance — it is a seat.
- **Role** — *who you are*: the function (e.g. `dev`, `arch`, `pm`). By function, not person.
- **Front** — *what you are on*: the task/worktree of the moment.
- **House** — the repo/folder of one unit of work with a life of its own, holding
  its own state, batons, MESA and lineage. A seat lives inside a house.
- **Brand** — the umbrella over several houses. A brand is not a house.
- **Generation (gen)** — the occupant counter of a seat, per house × role (§2.3).
- **Baton** — the serial testimony a dying instance leaves the next.
- **MESA** — the parallel/live board where instances working right now coordinate.
- **Lineage** — the genealogy, one node per close.

Three artifacts of continuity: **baton** (serial — backward), **MESA** (parallel
— sideways), **lineage** (genealogical — across all generations).

---

## 2. The file protocol

A **house** is any directory containing the harness files:

```
<house>/
├── _BATON_<role>.md     # serial testimony, one per role/seat
├── _MESA.md             # the live coordination board (one per house)
├── _LINAJE.md           # the genealogy (one per house)
└── …                    # the house's actual work
```

### 2.1 Baton — `_BATON_<role>.md`

The witness one instance leaves at death so the next resumes the line. One file
per **role**. Contract:

- **Written from disk, not from memory.** Before writing, re-read the raw state
  (git, tracker, MESA) and reconstruct from what is *actually there*. A baton
  that summarizes belief instead of disk is the primary failure mode.
- **It indexes; it does not re-narrate.** It points at the source of truth.
- **A role may hold several live fronts at once** (§2.2). The baton therefore
  *indexes fronts* — it carries a section per live front and points at each
  one's detail, rather than narrating a single one.
- **Self-contained and fail-safe:** if only the baton and this SPEC survive, the
  next instance can still continue.
- **Writes go through compare-and-swap** (§3.2, §4) so two instances of the same
  role closing at once cannot silently overwrite each other.

### 2.2 MESA — `_MESA.md`

The live board. **Append-only**: add at the bottom, never edit or delete a line
above. One event per line, fields separated by ` · `:

```
<timestamp> · <role> @ <front> · <EVENT> · sesión <id> · <note>
```

- **EVENT** ∈ `CLAIM` | `RELEASE` | `NOTA`. `CLAIM` opens a front, `RELEASE`
  closes it, `NOTA` records without opening or closing. Every event line carries
  a `sesión <id>` field.
- A front is **LIVE** if it has a `CLAIM` with no matching `RELEASE`, matched by
  identical `<role> @ <front>` + `<id>`. A `RELEASE` must reproduce the dead
  CLAIM's `<role> @ <front>` and `<id>` **exactly**, or it will not match.
- **timestamp** — `YYYY-MM-DD HH:MM`, zero-padded and lexicographically sortable
  (optional `:SS`). The parser rejects other shapes rather than mis-sorting them.
- **`<front>` must not contain ` · `** (the field separator). Compose it with
  `/`, `+` or `—`. The parser locates the event as the keyword *immediately
  followed by the* `sesión` *field*, so a bare keyword inside a front no longer
  hijacks it — but keeping ` · ` out of the front is still the contract.
- **`sesión` is a protocol literal** (accented): the id is the token after
  `sesión `. An adapter in another locale keeps the literal or configures it.
- **session id** — see §5.1. It is written verbatim after `sesión `.
- **Atomic append.** Concurrent instances must append with a single atomic write
  (`printf … >> file`, O_APPEND). Interleaved partial writes corrupt a line.
- **Fail-loud.** Data lines that do not parse are reported (`⚠ N ignorada(s)`),
  never dropped silently; zero parseable events among data lines is `⚠ MESA
  ILEGIBLE`. A silent false-clean is the one outcome the system forbids.

Reference parser: [`bin/mesa.sh`](bin/mesa.sh) (§4).

### 2.3 Lineage — `_LINAJE.md` & generation counting

Append-only genealogy, one node per close. Provenance, not dogma: each
generation may prune what it inherited.

- **Generation counts occupants**, per house × role. The counter lives in the
  baton header (`gen <N>`) and gains a lineage node at each close.
- **The first instance to sit a seat with no prior baton is `gen 1`** — a
  founding, not an error.
- **`gen 0` is optional**: it denotes a *founding from outside* — a seed or
  founding brief left by someone who did not occupy the seat. With no external
  seed, the lineage simply starts at `gen 1`.

---

## 3. The rituals

Two host-invocable rituals bracket every session. The content is host-agnostic;
how it is invoked is the host's business. Reference wording:
[`rituals/`](rituals/).

### 3.1 boot — sitting down

1. **Ingest** the baton for your role in this house, and **record its sha**
   (`baton-cas.sh sha`, §4) — you will need it to close safely.
2. **Triple-check** it against the raw source (git, tracker). The baton can lie;
   read the raw datum, do not infer from a summary.
3. **Reclaim orphans** left by dirty deaths (§3.3).
4. **Read the MESA** for live fronts that collide with yours.
5. **Plan before touching anything.** Only act on approval.
6. **On starting real work, append your `CLAIM`** to the MESA. Until you do, your
   front is not LIVE and your later `close` has no anchor.

Founding: no baton for your role → you are founding that seat (`gen 1`); its
boot sha is `NONE`.

### 3.2 close — standing up

1. **Log** the session and distill durable lessons.
2. **Reconcile against disk.** Re-read git + MESA + batons.
3. **Emit the baton through compare-and-swap.** Write it with `baton-cas.sh
   write <baton> <boot-sha>` (§4). If the sha still matches your boot, the write
   lands atomically. If it changed, another same-role instance closed while you
   worked: the CAS **refuses to overwrite** and tells you to **merge** its
   testimony with yours and retry with the new sha. This is the concrete form of
   "you merge, you do not overwrite."
4. **`RELEASE`** your front on the MESA (reproducing your CLAIM's key exactly).
5. **Append** a node to the lineage (`gen <N>`).

### 3.3 The dirty death (reclaim)

The safety net (baton, RELEASE, lineage) is **voluntary** — woven only if the
instance reaches `close`. Crashes, kills and context-saturation kill it *before*
it can weave, leaving resources dangling with no owner. Invariant: **the one who
cleans the corpse is the next instance, not the dying one.**

Reclaim classifies each live front's session as **alive / doubtful / orphaned**
using the host's liveness signal (§5.2), and **reports — it never auto-mutates**.
A human confirms before a `RELEASE` is appended on a dead session's behalf; the
reference tool prints that RELEASE line ready to copy, with the dead front's key
already filled. A false positive destroys real coordination, so an ambiguous
signal is reported as doubtful, not resolved.

Reference: [`adapters/claude-code/reclaim.sh`](adapters/claude-code/reclaim.sh).

---

## 4. Tools (portable)

**[`bin/mesa.sh`](bin/mesa.sh)** — the MESA parser. `bash` + `awk`, env-parameterized.
```
mesa.sh live      <MESA_FILE> [--tsv]                  # live fronts (CLAIM without RELEASE)
mesa.sh check-409 <MESA_FILE> <ROLE> <SESSION> [SINCE] # other same-role instances since your CLAIM
```

**[`bin/baton-cas.sh`](bin/baton-cas.sh)** — compare-and-swap for the baton.
```
baton-cas.sh sha   <BATON_FILE>                  # current sha, or NONE — boot records it
baton-cas.sh write <BATON_FILE> <EXPECTED_SHA>   # writes stdin IFF current sha == EXPECTED_SHA, else CONFLICT
```

Both are scripts, not inlined into the ritual text: an inlined `awk`'s `$1,$2…`
collide with a host command's positional-argument substitution and go silently
mute. Do not re-inline them.

---

## 5. What a host adapter must provide

### 5.1 A session-id scheme
An id that (a) is **unique among concurrently-living instances**, (b) is
**resolvable to a liveness signal** (§5.2), (c) is stable for the instance's
life, and (d) is **long enough that a prefix does not collide** with another id.
The reference adapter uses the first 6 hex of the transcript UUID, which *can*
collide (see Known Limitations) — prefer the full id.

### 5.2 A liveness signal
Given a session id, return the epoch seconds it was **last known alive**, or
`unknown`. Aevum classifies: `< LIVE_SEC` → ALIVE, `≥ DEAD_SEC` → ORPHAN,
between → DOUBTFUL, `unknown` → ORPHAN (defaults 600 / 3600, configurable). The
reference adapter reads the session transcript's mtime (appended every turn). A
per-invocation host returns its own last-recorded heartbeat.

### 5.3 Ritual invocation
A way to invoke `boot` and `close` (optionally `log`).

### 5.4 (optional) Guards
Hooks that enforce the invariants — append-only MESA, plan-before-touch. Without
them, append-only is honor-based (see Known Limitations). The reference adapter
ships a MESA append-guard.

Everything else — the file protocol, the parsers, the templates, the tests — is
shared and host-agnostic.

---

## 6. A full cycle (worked)

```
# gen 3 boots. It reads the baton and records its sha:
$ baton-cas.sh sha _BATON_dev.md            → 7f3a…  (the gen-2 testimony)

# it triple-checks, reclaims, then CLAIMs and works:
_MESA.md ← 2026-09-14 10:00 · dev @ deploy prod · CLAIM · sesión 91af2c · roll v2

# it closes. Nobody else touched the baton, so the CAS lands:
$ baton-cas.sh write _BATON_dev.md 7f3a… < new_baton     → ✓ (CAS ok)
_MESA.md   ← 2026-09-14 12:30 · dev @ deploy prod · RELEASE · sesión 91af2c · shipped
_LINAJE.md ← gen 3 · 2026-09-14 · shipped deploy v2

# had a parallel dev closed first, the CAS would have refused gen 3's write and
# told it to merge — the lost generation the old advisory "409" could not stop.
```

---

## 7. Known limitations

Honest edges, not hidden:

- **CAS residual window.** `baton-cas.sh` checks the sha then `mv`s atomically,
  but the gap between check and `mv` is not zero (no portable `flock` on macOS).
  It turns a *guaranteed, silent* clobber into a vanishingly rare TOCTOU; it does
  not make it impossible.
- **Session-id prefix collision.** A 6-char id can share a prefix with another
  (birthday-bound). Reclaim detects the multi-match case and reports it as
  ambiguous rather than guessing; a *single* wrong match still can't be caught at
  this layer. Longer ids (§5.1) are the real fix.
- **Append-only is hook-enforced, not cryptographic.** A careless rewrite of the
  MESA (a merge conflict, an agent "tidying") can still delete a line. The guard
  (§5.4) is best-effort; there is no hash chain.
- **No mutex.** A `CLAIM` records *who is sitting*, it is not a lock. Two
  instances can claim the same front; the collision surfaces on the next boot's
  MESA read and is resolved by judgment, not by mechanism.
- **One baton per role vs. many live fronts.** The baton indexes several fronts
  (§2.1), but partitioning one file cleanly across many *simultaneous* same-role
  fronts is a sharp edge, not a solved problem.

---

*— Designed by Humans · Built by Intelligence*
