# Overnight master brief (owner, 2026-11-27 ~23:45 Europe/Istanbul)

Deadline: 2026-11-28 08:00 Europe/Istanbul. Lead: Claude Opus 5.5. Workers: Claude Haiku 5.5 (narrow, measurable
packages), every important change reviewed by a separate reviewer and finally by the lead.

Summary of the owner's brief (full text was given in chat):
- Preserve everything: Godot engine and architecture, eleven licensed cars, existing tests. No change to main, no
  force-push, no branch deletion, no erased user assets, no weakened tests.
- PR #8 (`integration/chatgpt-gameplay-2026-11-27`, 30 events, save safety, AI recovery, garage upgrades, time-trial
  economy, pursuit foundation, CI evidence) is verified independently and merged once into an isolated release-candidate
  branch (`release/rc-2026-11-28`). Its seven constituent PRs are never merged separately.
- Allocation: graphics 40 %, gameplay 25 %, networking 15 %, player experience 10 %, QA 10 %.
- Flagship: a real 100-300 m Ortakoy waterfront gameplay segment made exceptional before more scenery.
- Police pursuit: opt-in mode behind a disabled-by-default flag.
- Online: smallest real LAN/local-server race (lobby, ready, countdown, sync, interpolation, authoritative results,
  disconnects), experimental and disabled by default; never labelled internet multiplayer; no paid servers.
- Performance: Mobile renderer budgets; desktop numbers are never iPhone numbers.
- At most six concurrent workers, isolated worktrees, explicit file ownership, one heavy GPU job at a time.
- 06:30: stop major features, stabilise. 08:00: commit only verified work, disable broken experiments, report.
- No fake completion, agents, benchmarks, multiplayer, screenshots or device tests. No paid services. No publishing.

Status and handoff: `docs/status/OVERNIGHT_HANDOFF.md`.
