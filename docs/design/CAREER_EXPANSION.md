# Career expansion (isolated change)

Preserves the original eleven event IDs, ordering, star rules, prices and reward multipliers. Adds nineteen events using existing track scenes, opponents and traffic configurations. Existing saves that completed the Bosphorus Final can unlock the first new event without migration. Desktop displays at most ten rows; phone retains four. TR/EN titles are provided.

All time thresholds, new reward multipliers and rival levels are provisional tuning choices; require human playtesting. These are race variations, not new tracks, drag, police, or story missions. No graphics, physics, asset, save-schema or release workflow changes. Added regression tests for compatibility, progression and bounded list navigation. CI and visual/device review required before merge.

## Race modes (drift and elimination)

- Drift Harbour (60 s, Arden Bay, level 2) and Drift Bosphorus (75 s, Istanbul, level 3): timed solo sessions, no rivals. The score is the sum of the drift chains (`drift_ended`), including a chain still running at the time limit. Stars: 3 / 2 / 1 at 1000 / 600 / 250 (Harbour) and 1400 / 800 / 350 (Bosphorus) points. Provisional: needs a playtest.
- Wharf Elimination (4 cars, 3 laps, level 2) and Maslak Elimination (5 cars, 4 laps, level 3): laps = cars - 1. The last car across the line ends each lap and is out (the car is hidden and stops; AI and collisions stop with it). The player's elimination ends the race with the placed result. Stars come from the place, like the other position events.
- The four mode events are appended after the Istanbul Championship, so existing saves keep every unlock. Rewards use the existing tables through the star tier (drift) or the place (elimination) and the event multiplier.
- A stuck car cannot hold an elimination lap: after 60 s with the lap leader through, the last place goes (`RaceManager.ELIM_GRACE_S`).
