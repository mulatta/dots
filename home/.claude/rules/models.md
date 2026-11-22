# hstack model configuration. One line per role: the model its subagents run on, then the effort. `/hstack-setup` writes this file.
# `inherit-parent` in place of a model is the parent model: omit the model and pass the effort. A role with no line runs on the parent model.
# Several entries on one line is a panel, one seat per entry, and its point is that the seats come from different vendors. A seat this harness cannot run starts in a managed terminal on the harness that can. It is never swapped for the parent model, which would leave the panel with one vendor. A panel seat stays at high whatever the budget: the other vendor's seat is the judge, and at low effort it is the weakest one.
# `swarm workers` names a cheap model, not a vendor. Where this harness cannot run it, the workers run on the parent model at low effort.
# budget: medium (high)
feature, refactoring: inherit-parent high
bug-fix: inherit-parent high
perf-issue: inherit-parent high
hillclimb: inherit-parent high
judgment and prose: inherit-parent high
arena runners: opus high, gpt-6.2-astra high
arena cross-judge pool: opus high, gpt-6.2-astra high
interrogate reviewers: opus high, gpt-6.2-astra high
swarm workers: sonnet medium
