# SWU Kyber — Design Notes (foundation pass)

Companion to `SWU_KYBER_BUILD_SPEC.md`. This file records the research behind the
foundation, how Star Wars: Unlimited (SWU) rules map onto a Hearthstone-style
digital frame, and the decisions made (with what is still open).

---

## 1. What we borrowed from other digital CCGs

| Game | Pattern | How SWU Kyber uses it |
|---|---|---|
| **Hearthstone** | Fanned hand at the bottom; drag a card upward onto the board to play it; hover/long-press enlarges a card; minions are compact tokens (stats only), full card on inspect; red targeting arrow when attacking; big glowing end-turn button; every action is a short, readable animation (lunge, hit, number pop, death burst); board art with small interactive "toys". | Same hand fan + drag-to-play (`ui/board/hand_view.gd`, `ui/cards/card_view.gd`). Units are **hex tokens** with power/HP badges (`ui/board/unit_token.gd`). Drag a unit → curved targeting arrow (`Fx.TargetArrow`). Event queue → sequential animations (`match_screen.gd::_drain`). PASS button breathes when it's your action. Themed animated boards (`board_theme.gd`). |
| **Hearthstone Dungeon Run / Monster Hunt** | Short runs, small starter decks, pick 1 of 3 after each win, rare "treasures", full reset on loss, final boss. | Chapter = run. 15-card starters, 1-of-3 card rewards, treasures after elite/objective fights, chapter reset on loss (`engine/campaign_run.gd`). |
| **Elder Scrolls: Legends** | Two lanes on one board, each with its own rules (Shadow lane = cover). Rune system: base damage thresholds trigger card draws. Readable in portrait on mobile. | Two **arenas** (ground/space) as separate bands — stacked in portrait, side by side in landscape. Units only fight within their arena, exactly like lanes. Runes are a strong candidate for a future campaign node modifier (see §6). |
| **Marvel Snap** | Matches are ~3 minutes; extremely snappy animations; small, legible board in portrait. | Node pacing target 1.5–2 min: small decks, 10–20 HP enemy bases, campaign hand of 5. Simulator estimates per-node length. |
| **MTG Arena** | Clear prompts for multi-step choices; stack/priority made visible; "auto-pass" when there is nothing to respond to. | Engine choices surface as a gold prompt bar (board targets) or a modal card picker (`choice_panel.gd`). Players who claimed the initiative auto-pass. |
| **Slay the Spire / Monster Train** | Branching node map, elites, events, rest sites, boss; map visible up front so routing is a decision. | `chapter_map.gd`: rows of nodes with dashed holo-links, pulsing available nodes, events/rest resolved in-map. |

The engine and presentation are original implementations of these *concepts*; no
Blizzard/Bethesda code, data or assets are used (spec §1).

---

## 2. SWU → Hearthstone-style mapping

SWU is **not** "dump your hand, end turn". Its identity is strict
**one-action-at-a-time alternation** with the initiative race. The UI keeps that
rule but makes it feel as immediate as Hearthstone:

| SWU rule | Engine | Presentation |
|---|---|---|
| Action phase: players alternate single actions | `Match.do_action` → `_advance` | Your action = PASS button breathes + "turn" chime; enemy actions play out with ~0.5 s pacing |
| Pass (two consecutive passes end the phase) | `consecutive_passes` | "Pass" float text over the HUD |
| Take the initiative (ends your round, you act first next round) | claimable token `initiative`, `out_of_round` | Token tray (gold buttons). Generalised for Twin Suns **Blast/Plan** and campaign tokens **Krayt Call / Alarm** (`engine/tokens.gd`) |
| Regroup: draw 2, resource 1, ready all | `_end_action_phase` frame | "REGROUP" banner, resource picker modal |
| Resources pay costs; +2 per missing aspect icon | `play_cost`, `pay` | Gold hex pips; hand cards show a red adjusted-cost badge when penalties apply |
| Units enter exhausted; exhausted = can't attack | `CardInst.exhausted` | Token tilts, dims, "EXHAUSTED" |
| Ground / space arenas, attack only within arena or the base | `attack_targets` | Arena bands; illegal targets never highlight |
| Sentinel / Saboteur / Hidden restrict targets | `attack_targets` | Pulsing Sentinel badge; only legal targets glow red |
| Shield token prevents next damage | `deal_damage` | Animated shield bubble; shatter FX |
| Combat damage is simultaneous; Overwhelm excess hits base | `resolve_combat` | Lunge → bolts/saber → impact → both numbers pop |
| Leader: action side + Epic Action deploy → leader unit | `_deploy_leader`, `CardInst.deployed` | Leader tile glows gold when an action/deploy is available; tap for menu; "deploys" banner |
| Base HP = life | base `CardInst` | Base tile with art, HP counter that ticks down, HP bar colour |
| Triggered abilities (When Played, On Attack, When Defeated…) | effect DSL frames | Card reveal for events/enemy plays; floating "+1/+1", "Shield", etc. |

### Interaction model (touch first, mouse equal)
- **Tap** hand card → inspect. **Drag** it above the hand line → play (illegal drops spring back with an elastic tween and a "Can't play that now" toast).
- **Drag** one of your units → targeting arrow; drop on a highlighted enemy/base → attack. Or **tap** unit, then tap target.
- **Long-press** (0.42 s), **right-click** or **double-click** anything → inspect overlay. The enlarged card zooms out of its source rect and can be dragged freely; it springs back to centre.
- Leader tile → menu (leader action / deploy / inspect). Resource pips → Smuggle menu.

### Attack styles (`ui/board/attack_style.gd`, overrides in `game/data/attack_styles.json`)
| Style | Who | Animation |
|---|---|---|
| saber | Jedi / Sith / Inquisitor traits, or known saber wielders (Luke, Vader, Ahsoka, Ben…) | hilt appears, blade **ignites** in the character's colour, unit dashes in, blade **swings** through the target with a glowing swept trail, sparks + screen shake, blade retracts |
| blaster | troopers, officials, scoundrels, droids… | unit rises, 3–6 heavy bolts with muzzle flashes, recoil per shot, impact burst per bolt |
| heavy | ground vehicles (walkers, tanks, speeders) | fewer, thicker cannon bolts + board shake |
| ship | space units | bank into a strafing run, twin lasers in pairs, peel away |
| melee | creatures, Tuskens, Ewoks, astromechs… (cards with no blaster) | card **leaps up**, hangs, **slams down** on the target: shockwave, debris, heavy shake |

Bolt colours: **Heroism fires red, Villainy fires green**, unaligned fires orange.

### Animation language (spec 8.4)
All effects are procedural `_draw` nodes or tweens (no textures, no shaders) so they
stay cheap on low-end phones and in WebGL: lightsaber arc in the character's colour
(`saber` field from the importer), blaster bolts (green for you, red for the
enemy), impact rings with sparks, shield shatter shards, damage/heal numbers, banners.
`Kyber.anim()` scales every duration (Settings → Animation speed); Performance mode
freezes backgrounds and drops sparks.

---

## 3. Architecture

```
tools/            import_cards.py (DB → normalised JSON + DSL), godot_tool/convert_art.gd (art → WebP),
                  assign_cards.py (tag cards to films/chapters)
game/engine/      PURE LOGIC, no Nodes: Match, Effects (DSL interpreter), CardInst, PlayerState,
                  RuleSet, Objective plug-ins, Tokens, AiBot, DeckBuilder, CampaignRun, CardLibrary
game/autoload/    Kyber (config/palette/settings), CardDB, Art (lazy WebP streaming + LRU), Save, Router, Sfx
game/ui/          kit (theme, buttons, vector icons, starfield), cards (CardView, InspectOverlay),
                  board (match screen, tokens, HUD, hand, FX, choices, themes), screens
game/data/        campaign JSON (IP-free ids only), custom KYB_ cards
game/ip/          GIT-IGNORED: cards.json, art/*.kart, fonts, UI art
game/tests/       run_tests.gd (rules tests + bot sims + campaign validator), compile_all, shots (screenshots)
```

**Engine contract.** Everything that happens is an op in a stack of frames.
An op that needs input sets `Match.pending` and suspends; `submit_choice()` resumes
it. This makes setup, regroup, combat and every card ability resumable, AI-drivable
and replayable (`Match.history` + seed). The UI only ever calls `legal_actions`,
`do_action`, `submit_choice`, `take_events`.

**Effect DSL** (produced by the importer, executed by `effects.gd`):
`{"op": "damage", "n": 3, "t": {"s": "choose", "kind": "unit", "side": "enemy", "max_hp": 3}, "optional": true, "if": {...}, "if_did": true}`.
Ops: damage, heal, draw, discard, shield, experience, exhaust, ready, defeat, bounce,
buff, gain_kw, lose_kw, token, summon, force_token, ready_resource, scry, search,
attack_with, base_damage. Triggers: when_played, on_attack, when_defeated,
when_deployed, attack_end, base_damage, regroup_start, action_start, action (with
cost), event, attached_kw / granted abilities for upgrades.

**Coverage today** (`docs/coverage_report.md`): 879 cards fully compiled, 601 partial,
1,108 need hand scripts. Campaign pools prefer `full` cards; the inspect view shows
each card's support level and lists any lines that are not yet automated.

---

## 4. Performance budget (spec 9)
- Bot decision + rules: **~0.7 ms per action** (headless benchmark, 300 games).
- Card art: 2,760 renders converted to lossy WebP (~45 KB each, 126 MB total), decoded
  lazily (3 per frame, no threads → works on single-threaded Web) into a 220-entry LRU.
- GL Compatibility renderer for Android/iOS/Web parity. No per-frame allocations in the engine loop beyond event dictionaries.
- Next steps: per-episode art packs, ASTC/ETC2 atlases for board themes, object pooling for FX if profiling shows churn.

---

## 5. Rules notes to verify against Comprehensive Rules v9.0
The PDF named in the spec (`SWH_Comp_Rules_v9_0_*.pdf`) was **not in the folder**, so
the engine follows the published SWU rules as generally understood. Items marked
[VERIFY] should be checked once the PDF is added to `docs/`:

1. Deployed leaders keep their exhausted state (deploying doesn't exhaust them). [VERIFY]
2. Overwhelm deals no excess when the defender's Shield prevented the damage. [VERIFY]
3. Hidden = can't be attacked during the phase it was played. [VERIFY]
4. Smuggle replacement resource enters exhausted. [VERIFY]
5. Unique rule: when a second copy enters, the **older** copy is defeated automatically (real rule: controller chooses). [VERIFY / UX]
6. Deck-out: 3 damage to your own base per undrawable card (campaign: 2). [VERIFY]
7. Not yet automated: Exploit, Piloting (as upgrade), Bounty, Coordinate, Plot, Support, Fortify, capture, take control, indirect damage, The Force beyond the token flag, Disclose. Their reminder text is shown; the engine ignores the effect.

---

## 6. Decisions taken in this pass (and why)

| Topic | Decision | Notes |
|---|---|---|
| Spec open Q3: missing Tatooine bases | **Tusken Camp (HMW 026, Command)** and **Mos Eisley (HMW 032, Cunning)** found in the DB | Also JTL 030 Mos Eisley (Cunning), SHD 026 Jabba's Palace, ASH 026 Freetown |
| Spec open Q4: shared base HP | Each side keeps its own base & HP; enemy bases can be custom (`KYB_004 Tusken Hunting Party`) | Matches the spec's leaning |
| Spec open Q5: Yavin base | Custom `KYB_001 Great Temple, Yavin 4` (campaign-only) | |
| Card DB name quirk | DB spells **"C-3P0"** with a zero; importer normalises to C-3PO | |
| DB keyword list incomplete | Importer also reads bare keyword lines from text (e.g. Krayt Dragon's Overwhelm) | |
| Art files | Many `.png` files in `swu_data/art` are actually JPEGs; converter sniffs magic bytes | |
| Luke, Hero of Yavin in the all-space chapter | Leader deploys into the node's arena as a stand-in until Piloting is automated | Flagged in code |
| "Hounds" for Tatooine | No Massiff card in the DB; Womp Rats / Feisty Blurrg stand in | |
| Campaign starting hand | 5 (standard 6) to keep nodes short | `RuleSet.campaign()` |
| Still OPEN (not decided) | Game name, Ch.2 canonical leader (both selectable), Burst turn mode placement (engine supports it, no node uses it), networked PvP, Spine licence, art sourcing, final tuning | Per spec §12 |

### Balance snapshot (bot plays hero side, 20 games/node)
Ch.1 Tatooine: 75–100% on normal nodes, boss ~55%. Ch.2: hangar/detention ~20–30%
(too hard), others 85–95%. Ch.3: boss (Trench Run) ~15% (too hard). Bots are weaker
than humans at the initiative race, so treat these as relative difficulty; run
`tests/run_tests.gd` after every content change.

### Ideas for later
- TESL-style **runes** as a node modifier: every 5 damage to a base draws its owner a card (comeback mechanic).
- Hearthstone-style board **toys**: tap Tatooine's vaporator to make it spin; tap the Death Star wall to trigger a TIE flyby.
- Ghost "replay last action" button using `Match.history`.
