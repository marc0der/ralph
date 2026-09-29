# Review is one pass; cycles do the iterating

Review used to repeat passes until one changed nothing, as plan does. Pass 2 was the same reviewer with the same tree and instructions, so it mostly confirmed pass 1, and keeping it stable took rules that made review defensive: never re-file, stop when the queue is full, treat an unchanged plan as a finished audit. Real defects ended up in final messages nobody read. Review now runs exactly one thorough pass per phase. Repetition belongs to build→review cycles, where a later review has something new to check: build's fixes.

## Considered Options

- **Multi-pass review with a sharper finding standard.** Rejected: it keeps the stabilising machinery that caused the bias.
- **Keep convergence for plan's sake.** Plan still converges. Its passes refine a document, so later passes add real value, which a repeated review pass does not.
