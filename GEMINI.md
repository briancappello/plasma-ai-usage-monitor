# Plasma AI Usage Monitor — Gemini CLI Instructions

> **Canonical instructions**: `AGENTS.md`
> Read `AGENTS.md` first.

---

## Workflow

Use: **PLAN -> IMPLEMENT -> TEST -> VALIDATE -> DOCUMENT**

---

## Build and Test

```bash
cmake -B build && cmake --build build
cmake --build build --target test
```

---

## Conventions

- C++20 with Qt6/KF6 and QML.
- Keep CMake target-based and modern.
- Follow KDE Plasma applet lifecycle and i18n conventions.
