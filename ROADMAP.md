# Roadmap

> **North-star update (current):** the product is **the kit for writing your own
> Dart code generators**, not the fixed set of built-in generators. The built-ins
> (`defrecord`, `defunion`, `defFromJsonSchema`, …) are now positioned as a
> **standard library** — worked examples of what any user can write with the public
> `(args) → Node` API. See `doc/VISION.md`. Phases 0–9 below are the foundation that
> made this possible and are **DONE**; **Phase 10** (`specs/phase-10-macro-authoring.md`)
> is the pivot and the current headline work.

A linear path with one hard decision gate. Each phase has its own spec in `specs/`.

```
Phase 0  ─────────────  Foundation (DONE)
  core engine · reader · tokenizer · parser · typed API · builtins · CLI
  validated end-to-end (see doc/VALIDATED_LOGIC.md)
        │
        ▼
Phase 1  ─────────────  Correctness          [small]
  gensym (hygiene) · $splice (general unquote-splicing)
        │
        ▼
Phase 2  ═════════════  Async compile-time eval   [medium]  ◀── KEYSTONE
  async expander · defFromJsonSchema · schema_demo
        │
        ▼
   ┌──────────────────────────────────────────────┐
   │  DECISION GATE                                 │
   │  Is "schema → typed Dart, no build_runner"     │
   │  compelling enough to pursue as a tool?        │
   │                                                │
   │   YES → continue to Phase 3                    │
   │   NO  → stop; document as a learning artifact  │
   │         (already a complete, honest outcome)   │
   └──────────────────────────────────────────────┘
        │ (if YES)
        ▼
Phase 3  ─────────────  Parser hardening      [medium]
  named args · cascades · async/await/arrow · conformance corpus
        │
        ▼
Phase 4  ─────────────  Developer experience  [medium]
  watch mode · source-mapped errors · --check for CI
        │
        ▼
Phase 5  ─────────────  IDE integration       [large, stretch]
  VS Code: compile-on-save · highlighting · diagnostics
        │
        ▼
Phase 10 ═════════════  Macro authoring as the product   [medium]  ◀── THE PIVOT
  built-ins → standard library · loadable user Dart macros ·
  macro-author error attribution · WRITING_MACROS.md
  (Phases 6–9 — pub packaging, schema hardening, Swift-lessons
   improvements — are DONE; folded into the foundation.)
```

## The pivot (Phase 10)

The first nine phases proved the engine: code-as-data, an expander, an emitter, and
a set of built-in generators that demonstrate the model. The strategic realization
is that **the built-ins were never the product — the ability to write them is.**

Phase 10 closes the one gap between "we ship generators" and "you write generators":
user-authored Dart-function macros, loadable from a user's own project without
forking this repo. When that works, `defrecord` stops being special and becomes the
first page of a cookbook. See `specs/phase-10-macro-authoring.md`.

## Sequencing rationale

- **1 before 2** — async expansion must build on a correct expander; do hygiene and
  splicing first so async work isn't debugging two things at once.
- **2 is the gate** — it's the experiment that answers the only question that isn't
  already answered (product value). Everything after 2 is investment that only pays off if
  the gate passes.
- **3 before 4** — no point polishing DX for a parser that chokes on real Dart.
- **4 before 5** — the extension is a thin shell over the CLI; the CLI must be good first.

## Effort + risk summary

| Phase | Effort | Technical risk | Notes |
|-------|--------|----------------|-------|
| 1 | Small | Very low | ~40 lines + tests |
| 2 | Medium | Low | Architectural (async) but path is clear |
| 3 | Medium | Medium | Real-Dart coverage is open-ended; scope to 95% |
| 4 | Medium | Low | `dart:io` watch; offset→line:col |
| 5 | Large | Medium | TypeScript/VS Code API, not Dart |

## What "done" means for the whole project

The Phase 2 gate has been passed; the schema-to-types demo was compelling enough to
continue, and Phases 3–9 shipped. The terminal state has been re-chosen at the
**Phase 10 pivot**:

> **Adoptable tool, repositioned:** a zero-dependency code-generation *kit* whose
> wedge is "write your own generator in your own project, no `build_runner`, no
> package to publish." The built-in generators are the proof, not the point.

The project is "done" in this framing when the Phase 10 acceptance holds: a user
authors a Dart-function macro in their own project and compiles a source that uses
it **without editing `lib/`**. Until then, Phase 10 is the only active work.

### Earlier terminal options (for the record)

1. **Learning artifact** (stop after Phase 2): a validated exploration of why
   language-level macros defeated the Dart team and how a preprocessor sidesteps it.
   Was a complete outcome; we chose to continue past it.
