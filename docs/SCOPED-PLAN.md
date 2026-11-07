# IRON EDEN — Scoped Production Plan
Derived from the full GDD (31 sections, received 2026-10-23) using the game-design-doc discipline: pitch, pillars, vertical slice, honest budget, defer list, tech lock. The GDD is the vision document. This is the scope contract.

## 1. One-paragraph pitch

You are a scavenger-pilot in a modular war mech on a planet at permanent war. You explore ruins, salvage enemy machines, and build defensive ecosystems — turrets, power networks, barricades — anywhere the terrain allows, then fight *alongside* them as the mobile core of your own defense. What you save, capture, or destroy persists: facilities become bases or ruins, factions adapt to your tactics with readable counters, and every expedition unlocks new mechanical possibilities, not just bigger numbers.

If a stranger can't repeat that back, a feature doesn't ship.

## 2. Three pillars (every feature is measured against these)

1. **Build Your War Machine** — The mech, its weapons, your turrets, and your base are one modular system. A build must change *how* you play, not just stats. (GDD §4, §6, §11, §30.1)
2. **The Battlefield Is A System** — Power, terrain, salvage, heat, and enemy wrecks all connect. A crater can be a trench, a wreck can be a turret's ammo, a power line can be a weapon. Emergent solutions beat scripted ones. (GDD §2, §5, §6.2, §10)
3. **The War Remembers** — The world persists and responds. Saved settlements trade, lost ones ruin, enemies develop specific, telegraphed counters to your habits — never invisible stat resistance. (GDD §14, §15, §18, §30.3)

A feature serving none of these is cut on sight. This resolves most scope arguments without a meeting.

## 3. The vertical slice — the whole game in miniature

One playable loop, ~20-30 minutes, that proves all three pillars. If this isn't fun, no amount of content fixes it.

**Setting:** One region — the ruined industrial valley / mining facility from GDD §2 + §7 ("Defending the Last Reactor"). One arena, hand-authored, ~120×120 m, with a chokepoint corridor, a collapsible bridge, an abandoned power substation, and cover ruins.

**Player mech:** 1 chassis (medium assault) with true modular slots:
- 2 weapon mounts (autocannon + railgun to start, swappable in hangar screen)
- 1 utility (grapple OR repair pulse — pick demonstrates build identity)
- Reactor / heat / power budget that actually constrains choices — heavy armor + big guns = heat and bridge weight limits bite

**Combat (GDD §5):**
- Twin-stick top-down (WASD + mouse aim on desktop, twin virtual sticks on S25), mech has mass/momentum, dash on Space
- Directional armor + component damage on enemies (front plate resists, rear cooling exposed; destroy targeting = inaccurate, locomotion = immobile, weapon = disarmed)
- Heat: firing builds heat, venting exposes you, overheating forces shutdown — with one heat-sink build option to prove it's a system, not busywork
- Disable vs destroy matters: a disabled enemy yields intact salvage (reactor/weapon/sensor), a blown-up one yields scrap only

**Active tower defense (GDD §6-7) — the signature:**
- Build *anywhere* (not lanes, not just pads in final design; slice can start with free placement + collision check): autocannon turret, barricade/energy wall, generator
- Power network: generator powers a radius / connected structures; if it dies, its turrets go dark. One redundant-power decision is forced in wave 3.
- 3 waves escalating per §7: (1) fast scouts multi-direction, (2) heavy armor behind a shield unit — flank or focus shield gen, (3) burrowers emerge *inside* the perimeter at the power network + a siege platform out of turret range forcing a player counterattack OR forward artillery build
- Player never leaves combat to "do TD mode" — building happens in-world (F to deploy), repairs cost salvage + time under fire

**Environmental system (at least one, proves Pillar 2):**
- Repair the substation to open the maintenance tunnel (alternate route) OR redirect its power to the abandoned facility turrets — one choice, both valid, mutually exclusive in the slice

**Salvage → progression loop (GDD §9-10, §18):**
- Salvage from the fight funds: 1 mech component swap + 1 new deployable unlock (mortar OR EMP pylon)
- Mech Memory lite: the weapon that killed the siege platform gets a named wear mark + a small optional upgrade offer — identity, not random stats

**Persistent consequence (proves Pillar 3):**
- Facility saved with reactor intact → it becomes a forward base (hangar + 1 trade discount) on the world-state save
- Facility saved but reactor lost / facility lost → different world state (damaged outpost / ruin with a recovery contract)
- Enemy adaptation tease: after the slice, a scout report names ONE counter the Directorate is developing based on what you used most (e.g. heavy turret use → tunneling units next) — shown, readable, not yet punitive

**Win / fail:** Survive wave 3 and keep the core reactor alive. Fail = base damaged state, not a hard restart (per GDD §11.3).

That's it. No Underworld, no Deep Network, no second faction, no base city-building, no multiplayer in the slice.

## 4. Content budget — honest count

### Vertical slice (build first)
| Item | Count | Notes |
|---|---|---|
| Regions / arenas | 1 | Hand-authored valley |
| Chassis | 1 (modular) | Systems built so chassis 2-6 are data, not rewrite |
| Weapons | 3 | Autocannon, railgun, close-range scatter/energy blade — each mechanically distinct |
| Deployables | 3 + generator | Turret, barricade, mortar/EMP as unlock |
| Enemy types | 3 + 1 siege platform | Scout (fast), heavy (directional armor showcase), burrower (perimeter breaker) |
| Allied units | 1 | Engineering drone (repair/salvage) — proves command-lite |
| Factions | 1 | Directorate only |
| Story beats | 1 operation | Intro → defense → discovery (prototype reactor pickup as hook) |

### Phase 2 — Early Access core (only after slice proves fun)
3 chassis (scout / assault / support), 10-12 deployables, 2 factions (Directorate + Bloom — most visually/tactically distinct), 3 regions (surface only), base as physical forward base with 5-6 modules, contracts system, full salvage/crafting, adaptation system v1.

### Full GDD vision (Phase 3+, multi-year solo scope — stated plainly)
6-8 chassis, 20-30 structures, 4 factions + Deep Network, 6-10 regions across 3 layers (Surface / Underworld / Deep Network), 15-25 story ops, mobile fortress, scenario editor, co-op. The GDD's own §28 targets describe a substantial release, not a first build. Phasing is how it survives.

## 5. Defer list — sequenced, not discarded (in defer order)

Nothing here is removed from the game. These are built later, in this order, so the slice can be built and tested first. Per the user's method (2026-10-22): sediment is the foundation — deferred material gets a build path, not disposal.

1. **Multiplayer / co-op / async warfare** (§20) — post-launch only. Single-player must be complete alone.
2. **Scenario editor + custom enemy builder + community blueprints** (§22) — post-launch. Blueprints *inside* the game (save your own layouts, §6.3) stay; sharing/editor goes.
3. **Mobile fortress** (§27.2) — endgame expansion.
4. **Deep Network as a full layer + machine diplomacy** (§3.3, §19) — slice/Phase 2 only *tease* it (one reactor, one strange structure). Full layer is expansion scope.
5. **Underworld as a full layer** (§3.2) — one underground section in Phase 2 at most.
6. **Roguelike expedition mode as separate mode** (§21) — its risk/reward extraction can be a contract type first.
7. **4 factions at launch** — start with 2 done properly. Choir + Remnants join when their *tactics* (not just skins) can be built.
8. **Full city-sim base building** (§11) — forward-base modules first; freeform city layout later.
9. **7+ experimental weapons** (§4.3) — 1-2 rule-changers per phase (e.g. Gravitational Harpoon), not all at once.
10. **Doctrine system full custom AI scripting** (§12.3) — start with 3 preset doctrines (Iron Wall / Hunting Pack / Ghost Protocol).

**Never cut:** modular mech, active TD (player in the fight), persistent consequences, salvage-disable-vs-destroy, power networks. Those are the game (§30).

## 6. Tech lock

- **Engine:** Godot 4.8 + GDScript — your call on 2026-10-23 for the next 3D game (lighting/shadows/physics built in beats Three.js for this weight). Verified live 2026-10-23 20:04 PDT: binary `4.8.beta1.official.4d10419ca`, export templates present incl. Android, build-tools 36.1.0 + platform android-36 present.
- **Presentation:** Top-down 3D, angled orthographic camera (optional isometric tilt per §1.1), follow + look-ahead.
- **Targets:** Galaxy S25 — Mobile renderer, ≤150 draw calls, 30 fps floor; Laptop/desktop — Forward+, higher tier, 60 fps target. Adaptive tiers, not one ceiling (your standing rule 2026-10-14).
- **Input:** WASD + mouse twin-stick first, gamepad twin-stick second, touch twin-stick for S25 build. Fully remappable per §1.1/§23.4.
- **Simulation tiers (§28):** detailed near player, simplified nearby battles, periodic strategic ticks for distant regions. Slice needs only tier 1.
- **Save:** persistent world-state (facility states, faction adaptation flags, mech loadouts, blueprints) in a versioned save — crash recovery + multiple campaigns per §28.
- **Art direction (slice):** procedural low-poly + emissive accents, no external assets required to prove fun — same discipline as DUSKFALL. Style pass comes after the slice teaches us what's fun.

## 7. Biggest risks (named, not hidden)

1. **Scope is the risk, not tech.** Every system in the GDD is buildable; all of them together in v1 is not. The slice + defer list is the mitigation.
2. **Power network + free placement** can become a complexity swamp. Slice constraint: radius-based power first, wired networks in Phase 2 if radius proves too simple.
3. **Enemy adaptation** (§14) done wrong feels like punishment / rubber-banding. Rule from the GDD itself: limited, contextual, *telegraphed* — scout reports before counters appear.
4. **Heat as busywork.** Must create decisions (vent timing, heat-builds) or it gets simplified in slice playtest.
5. **TD + shooter control collision** on touch. Desktop-first slice, S25 touch is a deliberate second pass with the joystick work already proven in the Godot proto lane.

## 8. Recommendation

Build the vertical slice exactly as §3 above in Godot. One valley, one mech, three waves, one consequence that persists. Play it, revise this plan *once* from what it teaches, then freeze and decide Phase 2. Do not author regions 2-10, factions 2-5, or the Underworld before the slice is fun.
