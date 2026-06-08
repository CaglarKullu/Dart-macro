# Roadmap

A linear path with one hard decision gate. Each phase has its own spec in `specs/`.

```
Phase 0  ─────────────  Foundation (DONE)
  core engine · reader · tokenizer · parser · typed API · builtins · CLI
  validated end-to-end (see docs/VALIDATED_LOGIC.md)
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
```

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

There are two acceptable terminal states, decided at the Phase 2 gate:

1. **Learning artifact** (stop after 2): a working, validated, novel exploration with a
   clear write-up of why language-level macros defeated the Dart team and how a
   preprocessor sidesteps that. Complete and worthwhile on its own.

2. **Adoptable tool** (through 4, ideally 5): a zero-dependency compile-time code generator
   whose wedge is "types from your source of truth, no build_runner". Requires the DX and,
   ultimately, the IDE integration to overcome ecosystem inertia.

Pick deliberately at the gate. Do not drift past it on momentum alone.
