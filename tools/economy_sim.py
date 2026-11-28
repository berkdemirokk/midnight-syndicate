#!/usr/bin/env python3
"""Career economy simulator for MIDNIGHT SYNDICATE.

Reads the real numbers from the GDScript sources (events, car prices, upgrade costs, reward tables) and plays
one career for a player who earns 2 stars on average: every event is played once in ladder order, the player
buys the car each level needs as soon as cash and rep allow, and when stuck replays the best-paying event so far.
Prints the before/after table used in docs/design/ECONOMY_2026-11-28.md.

  py -3.10 tools/economy_sim.py                             # the numbers in the sources
  py -3.10 tools/economy_sim.py --table 1000,600,300,100    # what-if reward table, sources unchanged

Assumptions (the owner may change them): stars 3/2/1 at 25/50/25 percent; a 2-star position finish pays the mean
of 2nd and 3rd; a 1-star position finish is 4th. A level needs a car at least LEVEL_NEED_PRICE[level] (the
starter for level 1).
"""
import argparse
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
P3, P2, P1 = 0.25, 0.50, 0.25  # share of 3-, 2- and 1-star results
LEVEL_NEED_PRICE = {1: 0, 2: 4000, 3: 15000, 4: 28000}
MAX_REPLAYS = 5000


def read(rel):
    with open(os.path.join(GAME, rel), encoding="utf-8") as f:
        return f.read()


def ints(text):
    return [int(v) for v in re.findall(r"-?\d+", text)]


def parse_events():
    out = []
    for m in re.finditer(r"^\s*\{\"id\": \"([^\"]+)\"(.*)\},\s*$", read("race/events.gd"), re.M):
        body = m.group(2)
        cls = re.search(r"\"cls\": \"(\w+)\"", body)
        out.append({
            "id": m.group(1),
            "mult": float(re.search(r"\"mult\": ([\d.]+)", body).group(1)),
            "level": int(re.search(r"\"level\": (\d+)", body).group(1)),
            "open": "\"open\": true" in body,
            "pos": "\"star_times\"" not in body and "\"star_scores\"" not in body,
            "cls": cls.group(1) if cls else "",
        })
    return out


def parse_cars():
    src = read("vehicles/car_catalog.gd")
    cars = []
    pattern = r"\{\"id\": \"([^\"]+)\", \"class\": \"([^\"]+)\", \"price\": (\d+), \"rep\": (\d+)([^}]*)\}"
    for m in re.finditer(pattern, src, re.S):
        cars.append({"id": m.group(1), "class": m.group(2), "price": int(m.group(3)), "rep": int(m.group(4)),
                     "starter": m.group(1) == "noctra_tayfun"})
    return cars


def parse_game_state():
    src = read("core/game_state.gd")
    up = re.search(r"UPGRADE_BASE_COST: Dictionary = \{([^}]*)\}", src).group(1)
    return {
        "cash": ints(re.search(r"STARTER_CASH: int = (\d+)", src).group(1))[0],
        "reward_cash": ints(re.search(r"REWARD_CASH: PackedInt32Array = \[([^\]]*)\]", src).group(1)),
        "reward_rep": ints(re.search(r"REWARD_REP: PackedInt32Array = \[([^\]]*)\]", src).group(1)),
        "upgrade_base": {k: int(v) for k, v in re.findall(r"\"(\w+)\": (\d+)", up)},
        "max_level": ints(re.search(r"MAX_UPGRADE_LEVEL: int = (\d+)", src).group(1))[0],
    }


def expected(ev, table, rep_table):
    """Mean cash and rep of one race at the 2-star average."""
    if ev["pos"]:
        cash = P3 * table[0] + P2 * (table[1] + table[2]) / 2 + P1 * table[3]
        rep = P3 * rep_table[0] + P2 * (rep_table[1] + rep_table[2]) / 2 + P1 * rep_table[3]
    else:  # time and drift events pay by star tier
        cash = P3 * table[0] + P2 * table[1] + P1 * table[2]
        rep = P3 * rep_table[0] + P2 * rep_table[1] + P1 * rep_table[2]
    return cash * ev["mult"], rep * ev["mult"]


def simulate(table_override=None):
    events = parse_events()
    cars = parse_cars()
    gs = parse_game_state()
    table = table_override or gs["reward_cash"]
    rep_table = gs["reward_rep"]
    upgrade_per_car = sum(gs["upgrade_base"].values()) * sum(range(1, gs["max_level"] + 1))
    cars_total = sum(c["price"] for c in cars)
    upgrades_all = upgrade_per_car * len(cars)
    three_star = sum(ev["mult"] * table[0] for ev in events)  # 1st or top star tier on every event
    two_star = sum(expected(ev, table, rep_table)[0] for ev in events)

    cash, rep = float(gs["cash"]), 0.0
    owned = {c["id"] for c in cars if c["starter"]}
    races, replays, log = 0, 0, []
    best = (0.0, 0.0, "")  # best expected cash per race among the events played so far

    for ev in events:
        ec, er = expected(ev, table, rep_table)
        need = LEVEL_NEED_PRICE.get(ev["level"], 0)
        if need > 0 and not any(c["id"] in owned and c["price"] >= need for c in cars):
            target = min((c for c in cars if not c["starter"] and c["price"] >= need and c["id"] not in owned),
                         key=lambda c: c["price"])
            replayed = 0
            while cash < target["price"] or rep < target["rep"]:
                if replayed >= MAX_REPLAYS:
                    raise RuntimeError("stuck before %s: no cash after %d replays" % (ev["id"], replayed))
                cash, rep = cash + best[0], rep + best[1]
                races += 1
                replays += 1
                replayed += 1
            cash -= target["price"]
            owned.add(target["id"])
            log.append("%-22s L%d buy %-16s after %3d replays" % (ev["id"], ev["level"], target["id"], replayed))
        races += 1
        cash, rep = cash + ec, rep + er
        if ec > best[0]:
            best = (ec, er, ev["id"])

    # after the ladder: buy the rest of the cars and every upgrade, replaying the best event for the deficit
    rest = sum(c["price"] for c in cars if c["id"] not in owned) + upgrades_all
    deficit = rest - cash
    extra = math.ceil(deficit / best[0]) if deficit > 0 else 0
    replays_ladder = replays
    replays += extra
    races += extra
    return {
        "events": len(events), "reward_cash": table, "three_star": three_star, "two_star": two_star,
        "cars_total": cars_total, "upgrades_all": upgrades_all, "cost_all": cars_total + upgrades_all,
        "ratio_3star": (cars_total + upgrades_all) / three_star,
        "ratio_2star": (cars_total + upgrades_all) / two_star,
        "races_ladder": races - extra, "races_total": races, "career_units": races / len(events),
        "replays_ladder": replays_ladder, "replays_total": replays, "best_event": best[2],
        "best_cash_per_race": best[0], "log": log, "starting_cash": gs["cash"],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", help="reward cash table to test, e.g. 1000,600,300,100")
    args = ap.parse_args()
    override = [int(v) for v in args.table.split(",")] if args.table else None
    r = simulate(override)
    print("reward cash table (1st..4th): %s" % r["reward_cash"])
    print("events: %d   starting cash: %d" % (r["events"], r["starting_cash"]))
    print("cars (10 buyable): %d   upgrades (11 cars, full): %d   cost of everything: %d" %
          (r["cars_total"], r["upgrades_all"], r["cost_all"]))
    print("full 3-star career cash: %d   cost / 3-star career = %.2f" % (r["three_star"], r["ratio_3star"]))
    print("2-star average career cash: %d   cost / 2-star career = %.2f" % (r["two_star"], r["ratio_2star"]))
    print("races: ladder %d, everything %d (%.2f career units of %d races)" %
          (r["races_ladder"], r["races_total"], r["career_units"], r["events"]))
    print("replays: ladder %d, total %d   best paying event: %s (%.0f cash a race)" %
          (r["replays_ladder"], r["replays_total"], r["best_event"], r["best_cash_per_race"]))
    for line in r["log"]:
        print("  " + line)


if __name__ == "__main__":
    main()
