# SWU KYBER (working title) — Build Specification for Claude Code

> Working title only. The final name is deliberately undecided (owner will pick later). "Skirmish", "Companion" and "Wayfinder" are already used by existing SWU fan tools — avoid them. Keep the title in ONE config constant (`GAME_TITLE`) so it can be renamed trivially.

**Owner:** Dom (solo hobbyist, non-commercial passion project).
**What this is:** A Hearthstone-style, slick, fast mobile card game that runs **Star Wars: Unlimited (SWU)** rules and cards, with an offline roguelike story campaign across the nine Skywalker-saga films, plus bot play and (later) local/PvP.
**Why:** Dom owns a large physical SWU collection and loves the game, but local play is hard to find. He loved Hearthstone's mobile UX but quit because it ran slowly on his device. Goal: that UX and performance, applied to SWU.

---

## 0. How to use this document

1. Read the whole thing before writing code. Sections are ordered: constraints → rules engine → data → campaign → UI/visuals → build order.
2. Authoritative rules source is the **SWU Comprehensive Rules v9.0 (10/9/26)** PDF (`SWH_Comp_Rules_v9_0_*.pdf`) — Dom is putting it in `/docs/`. Where this spec and the PDF disagree on *base game rules*, the PDF wins. Where this spec describes a *campaign-mode deviation* (Section 3.4, 5), this spec wins.
3. Card data and reference photos will be supplied by Dom in `/data/` and `/reference/`. Do not invent card text, costs or stats. If a card's data is missing, stub it with a clearly marked placeholder and continue.
4. Items tagged **[DECIDED]** are settled. **[OPEN]** are unresolved — implement behind a config flag or leave an extension point, and do not silently choose. **[VERIFY]** means a fact came from research/screenshots and should be re-checked against the card database once loaded.
5. Build in the milestones of Section 11. Ship a playable vertical slice early (one chapter, one bot, one node type) before widening.

---

## 1. Hard constraints and legal posture

- **Original engine.** Rebuild the *concepts* of Hearthstone's systems (mana/resource curve, turn flow, zones, triggers, animated board) as an original implementation. Do **not** copy, extract or reference any Hearthstone/Blizzard code, assets or data.
- **Star Wars IP.** Card names, art, text, logos, and Aurebesh fonts are Lucasfilm/FFG property. This is a private fan project: keep it non-commercial, never ship it with a store listing, and keep all IP-bearing assets (card art, card text DB, fonts, audio) in **separate, git-ignored asset folders** loaded at runtime, not hardcoded into source. The code repo itself should be IP-free so it can be shared.
- **No licensed 3D Star Wars models are available** — and none are needed (see Section 8).
- **Performance is a feature.** Must hold 60 fps on a mid/low-range phone. Hearthstone's slowness on Dom's device is the reason this exists. Budget accordingly (Section 9).

---

## 2. Technology

**[DECIDED]**
- **Engine: Godot 4.x** (free, open source, strong 2D scene system, good responsive layout). Language: **GDScript** for UI/scene glue; the rules engine should be written so it is **engine-agnostic and headless-testable** (pure logic, no node dependencies) — either a separate GDScript module with no `Node` use, or C# / a pure library. Recommendation: pure GDScript classes under `/engine/` with a thin adapter to the scene layer, plus a headless test runner.
- **Animation: Spine** (2D skeletal/layered) for animated board art and card flourishes, via the `EsotericSoftware/spine-runtimes` Godot runtime. Licensing note: Spine Essential/Professional is ~$69 / $379 per seat; the commercial tier is only required above $500k revenue — irrelevant here. **Build the animation layer behind an interface** so Spine can be swapped for Godot's built-in `AnimationPlayer`/`Tween`/`GPUParticles2D` if Dom doesn't have a license yet. Everything must be playable with simple built-in animation first.
- **Targets:** iOS and Android primarily; desktop (Windows/Mac/Linux) builds for development. Export presets for all.
- **Orientation: [DECIDED]** Must support **portrait and landscape** with easy rotation/reflow and scale across form factors/aspect ratios. Use Godot `Control` anchors/containers, a safe-area-aware root, and test at several resolutions (e.g. 1080×1920, 1080×2400, 2048×2732 tablet, 1920×1080 landscape). The board should re-lay itself out on rotation without losing state.
- **Data format:** JSON (or Godot `Resource` `.tres` generated from JSON) for cards, bases, leaders, campaign, nodes, tokens. All content is data-driven.
- **Save data:** local only, offline-first. Versioned save schema.
- **Fonts:** Dom already has Star Wars-style English and Aurebesh fonts; he will drop them in `/assets/fonts/`. Define a theme with `font_body`, `font_title`, `font_aurebesh_decor`. Aurebesh is decorative only — never for rules text.

---

## 3. Rules engine — Star Wars: Unlimited

Implement SWU faithfully per the Comprehensive Rules PDF. This section is a map of what must exist; the PDF is the source for exact timing/edge cases.

### 3.1 Zones (PDF §4)
Base zone, Ground arena, Space arena, Resource zone, Deck, Hand, Discard pile, plus In-play/Out-of-play and "set aside / no zone". Each player has their own base, resources, deck, hand, discard; the two arenas (ground, space) are shared battlefields.

### 3.2 Card types (PDF §3)
Base, Leader, Unit (ground or space), Upgrade, Event, Token (e.g. Shield, Experience, plus created unit tokens). Cards have: name, subtitle, arena type, cost, aspects (Vigilance/Command/Aggression/Cunning/Heroism/Villainy), power, HP, traits, text box (abilities), set/number.

### 3.3 Game structure (PDF §5) — **strict alternating actions**
- A game is a series of **rounds**. Each round = **Action phase** then **Regroup phase**.
- **Action phase:** players take turns **one action at a time, strictly alternating**: play a card, attack with a unit, use an Action ability, **take the initiative** (claim the Initiative token, which ends your actions for the round), or pass. Once a player has passed/claimed, the other keeps acting until they also stop. This is *not* a Hearthstone "dump your hand then end turn" structure.
- **Regroup phase:** draw 2 cards, optionally resource 1 card from hand, ready all exhausted cards, resolve end-of-round effects; initiative token resets/passes per rules.
- Resources: each resource is a face-down card in the resource zone; paying cost exhausts resources. Cost, damage, power/HP modification, counters, drawing, discarding, Exhaust/Ready, "defeated", captured units, etc. all per PDF §1.
- Setup: leader + base chosen, deck shuffled, opening hand with mulligan, resources start per rules (see PDF §5.2). Base HP, win condition = **reduce opposing base HP to 0**.

### 3.4 Keywords (PDF §7.5) — all must be implemented in the engine
Sentinel, Shielded, Grit, Saboteur, Ambush, Overwhelm, Raid X, Restore X, Coordinate, Exploit X, Smuggle, Piloting, Hidden. (Also check the PDF index for any newer keywords not in this list — the list above came from research and may be incomplete **[VERIFY]**.)
Quick semantics (confirm against PDF): Sentinel = enemy ground attackers must target it; Shielded = prevents the next damage once; Grit = +power per damage on it; Saboteur = ignores Sentinel and removes Shield before damage; Ambush = may attack immediately on play; Overwhelm = excess damage goes to base; Raid X = +X power while attacking; Restore X = heal base X when attacking; Smuggle = play from resource zone at an alternate cost; Piloting = attach to a Vehicle as an upgrade; Hidden = can't be attacked by units that were played/entered before it in certain windows.

### 3.5 Leaders (PDF §3.4)
- Two-sided: Leader side (an **Action ability**, usually exhausts the leader and may cost resources; "Epic Action" deploys it once the player controls enough resources) → flips to **Leader Unit** side with Deployed abilities.
- Epic Action thresholds vary per leader (e.g. 4+, 6+, 7+ resources — see data).

### 3.6 Triggered/Constant/Action/Event abilities (PDF §7)
Implement a **general ability resolver**, not per-card hacks. Required: trigger windows ("When Played", "On Attack", "When Defeated"), timing/priority queue, targeting and "choose", "may" optionals, "if you do", "then", replacement/prevention effects, Last Known Information, "up to X", random, look-at/reveal/search, take control, capture, indirect damage, move, "The Force" and "Disclose" (PDF §8.36–38). Implement an **effect DSL/IR** (a small JSON/structured effect language) that card data compiles to; cards the DSL can't yet express are flagged and fall back to a manual script file under `/engine/cards/custom/`.

### 3.7 Aspect penalties and deck rules
- **Base game:** per PDF §8.1 aspect penalties (+2 cost per missing aspect icon). Deck constraints (50-card min constructed, 3-of cap, etc.) per PDF §9–10. Draft/Sealed min 30. Twin Suns min 80 (PDF §12; was 50 pre-4th set). **Trilogy format** also exists (PDF §9.3) — read it; it may be a useful template for the campaign's multi-leader structure **[VERIFY]**.
- **Campaign mode deviation [DECIDED]:** **aspect penalties are IGNORED in the roguelike campaign.** Only the **Heroism / Villainy** split remains a hard gate (a Heroism campaign can't pull Villainy cards and vice versa — but see 5.9 for enemy decks). Vigilance/Command/Aggression/Cunning matching is dropped. Reason: a fixed leader+base per chapter would otherwise force both sides into one rigid 3-color identity (e.g. Ch.3 locking Luke to red-white-green and Vader to black-red-green), blocking thematic card unlocks and making a shared neutral battlefield base impossible. This also lets the enemy have no true "leader" in the deckbuilding sense and lets one shared base serve as flavor/HP.
- Implement as a rules flag: `RuleSet { aspect_penalties: bool, deck_min: int, base_hp: int, ... }`. Standard mode uses full rules; campaign uses the relaxed set.

### 3.8 Formats the engine must be able to run
1. **Campaign nodes** (custom, small decks, custom objectives — Section 5).
2. **Standard 1v1** vs bot (Premier-style, 50-card).
3. **Twin Suns (two leaders)** — used for climactic boss fights (Section 5.7) and optionally as a vault mode. Needs the two additional Twin Suns counters (3.9).
4. **Local PvP** (hotseat/pass-and-play first; networked later — **[OPEN]**).

### 3.9 Claimable tokens — design hook **[DECIDED as a feature, specifics OPEN]**
In real SWU you may spend an action to claim the **Initiative token** (ends your actions this round). Twin Suns adds two more claimable counters with the same cost (ending your actions for the round):
- **Blast:** deal 1 damage to every *other* base on the board.
- **Plan:** draw a card, then put a card from hand on the bottom of your deck.
(Dom first misremembered "Plan" as "Intel".)
**Campaign extension:** make the claimable-token system **data-driven** so each chapter/node can define custom tokens with a one-time effect and the "ends your round" cost. Examples to ship as test content: **"Krayt Call"** (Tatooine — scare off/remove a Tusken unit), **"Alarm"** (Death Star — the enemy side claims it to call reinforcements). Schema in Section 7.4. Tokens are a way to give nodes mechanical identity beyond stats/objectives.

---

## 4. Card data pipeline

- **Source:** Dom will supply the card database (likely from the community **SWU-DB API** — he offered a bulk-download script for data + art; **not yet written**). Build an **importer** that ingests the raw JSON and writes the game's normalized card schema (Section 7.1) into `/data/cards/`.
- **Scale (for planning):** roughly 1,800 unique numbered cards across 7 main sets as of Homeworlds (Oct 2026), ~250–270/set; collector databases list >6,000 indexed variants/promos. Card pool is mostly the nine films plus some Mandalorian/Clone Wars/Rebels content. Import **unique cards**, not variants; keep a `variants[]` list for art alternatives.
- **Art:** card art stored locally per card id; load lazily; build **three crops** from the source art: (a) full card, (b) **hex token crop** for on-board units, (c) small thumbnail for lists. Pre-generate at import time and cache on disk. Texture-atlas/compress for mobile (Section 9).
- **Compile abilities:** parse each card's text into the effect DSL where possible. Produce a **coverage report** (cards fully implemented / partially / manual) so Dom can prioritize. Campaign-pool cards (Section 6) are implemented first.
- **Verification rule:** earlier research had several wrong leader/aspect details. **Never trust remembered card data — always use the imported DB.** Known corrections below are for *sanity-checking the import* (Section 6.1).

---

## 5. Campaign design (the roguelike)

### 5.1 Structure **[DECIDED]**
- All **nine mainline Skywalker-saga films** are "episodes" in chronological order (I–IX). Each **episode is split into 3 chapters**. **The roguelike run unit is the CHAPTER**, not the episode — each chapter is a self-contained run with its own small starting deck, its own branching node map, a rest stop, and a boss. Completing a chapter advances to the next chapter, carrying forward applicable cards/leader. Dying restarts **that chapter** (not the episode).
- **Heroism campaign first** (full playthrough). A mirrored **Villainy campaign** comes later. Rebels/Mandalorian/other media = possible future expansion, out of initial scope.
- Inspirations: Slay the Spire (branching path, rest sites, bosses), Hearthstone **Dungeon Run / Monster Hunt** (each node is a full normal match vs a scripted AI deck/hero; reward picks after wins — card choices or unique overpowered "treasures"; full run-reset on loss; Monster Hunt's small unique starter decks/hero powers building to one final boss), Warcraft Rumble (split between story-mode roster and PvP roster).

### 5.2 Run flow (per chapter)
1. **Chapter intro** (short narrative cards/text, optional VO later), shows leader, base, starting deck.
2. **Node map:** branching path, ~**5–6 node fights** per chapter, plus a **rest stop** (cantina/repair/etc.) and a **boss** at the end. Player chooses route.
3. Nodes: standard fight, elite/hard fight, objective fight, event (non-combat choice), rest, shop/trade (optional), boss.
4. **Rewards** after wins: choose-1-of-3 cards, or a rarer "treasure" (unique powerful effect). **Harder/randomized objectives give better rewards.**
5. **Persistence within a chapter:** player's **base HP and leader state persist across nodes** (attrition tension); resets only on chapter restart/death.
6. **Pacing target [DECIDED]: ~10 minutes per chapter.** Each node fight should be short (about 1.5–2 minutes). Small decks and low base HP are how this is achieved.

### 5.3 Deck and base sizing **[DECIDED, numbers tunable]**
- Starting campaign deck ≈ **15 cards** (range 15–30), far below the 50-card standard — a campaign-mode rule override (`deck_min` lowered).
- **Base HP reduced** below standard 30 in campaign nodes (exact value tunable via config; start at ~15–20), with run-based upgrades able to **increase base HP**.
- Base is **fixed per chapter** (reflects the story location, not a player choice); it can change mid-chapter (e.g. Tatooine bases → Mos Eisley at the boss).
- Replayability comes from **replaying a chapter with a different leader unlocked later** in the campaign (e.g. replay Tatooine as Obi-Wan or Chewbacca).

### 5.4 Two card pools **[DECIDED]**
1. **Campaign deck:** a curated, **story-gated** pool used only in roguelike chapters. Cards are found as pickups (e.g. finding Obi-Wan adds his card).
2. **Collection vault:** wider pool of everything unlocked (e.g. Cal Kestis) usable only in **offline-bot or PvP/local multiplayer** modes — **not** usable in the campaign. Cards discovered in the campaign still count toward the vault unlock progress.

### 5.5 Node objective types **[DECIDED as a system; list is a starting set]**
Every node is a full match with a **randomized objective** from a pool, not always "reduce base HP to 0". Rationale: SWU's natural pacing (units trade damage, HP grind) is slow, so faster win conditions keep short nodes snappy. Implement objectives as plug-in classes (Section 7.3):
- **Standard:** reduce enemy base HP to 0.
- **Survive N rounds.**
- **Hunt:** defeat a specific enemy leader/card that is buried in their deck when it is drawn/played.
- **Attrition/deck-out pressure:** damage scales with the opponent's remaining deck size.
- **Defend a unit:** a specific friendly unit (e.g. an unplayable, already-in-play, "unconscious Luke") must not die for N rounds, protected by C-3PO as leader and an already-in-play Obi-Wan using **Sentinel** units. Directly mirrors the real ANH beat of Luke knocked out by Tuskens and rescued by Obi-Wan.
- Later: escort/transport, destroy a structure, capture, race-the-clock, etc. (Hoth escort and trench-run set pieces below).
Each objective defines: setup state, win condition, lose condition, UI tracker widget, reward multiplier, and any bespoke starting-board units.

### 5.6 Turn structure **[DECIDED]**
**Preserve SWU's strict one-action-at-a-time alternation as the default** — it's core to SWU's tactical, reactive identity and compresses fine with small decks/HP. **[OPEN/optional]**: implement an alternate **"Hearthstone-style" turn mode** (a player takes many actions in one go, then passes) as an *option on a specific node type only* (e.g. a "reckless ambush" node). Do not make it global. Engine must support `TurnMode.ALTERNATING` (default) and `TurnMode.BURST`.

### 5.7 Set pieces, arenas, and finales **[DECIDED]**
- Normal small beats use a **single arena** (e.g. Luke/Obi-Wan on Tatooine = ground).
- **Major set pieces use both ground and space arenas** (SWU's real structure; real games skew ~2/3 ground, 1/3 space, which Dom wants to break from with scenario-tailored fights). Elder Scrolls Legends cited as precedent for two lanes in a Hearthstone-style frame.
- Examples: **Battle of Hoth** (combined arms — Han/Leia/Luke defend Echo Base vs Vader, General Veers, AT-ATs, with transport-escort objectives across ground and space); **Death Star trench run** (**space-only**, Vader as enemy, the Death Star as the "base"); **Mos Eisley hangar/Falcon escape** (full dual-arena fight).
- **Climactic fights may use Twin Suns (two leaders)**: e.g. end of an ANH-based campaign = double-space battle vs Vader **and** Tarkin; end of a Revenge of the Sith campaign = two simultaneous fights (Obi-Wan vs fallen Anakin on Mustafar + Yoda vs Order-66 clones/Palpatine) using all thematically tied cards rather than strict 1v1 canon.
- **Custom thematic cards** (e.g. **turbolasers**, ion cannon, shield generators) beyond the standard pool are wanted for these scenarios — support a `custom_cards/` namespace that coexists with real cards and is never exposed in the vault/PvP.
- **Boss-as-mechanic template:** Grand Moff Tarkin (Homeworlds) flips into a "Death Star" leader unit via Fortify — use this as a precedent for bosses that escalate into a battlefield mechanic.

### 5.8 Episode IV (A New Hope) — fully specified reference chapter set **[DECIDED]**
Use this as the **template** for authoring the other eight episodes.

**Chapter 1 — Tatooine**
- Leader: **ONLY C-3PO** is available (paired with R2-D2), mirroring the film's opening. Leader: *C-3PO, "Human-Cyborg Relations"* (SEC #15) — see 6.1.
- Starting ~15-card deck: **R2-D2**, **Luke Skywalker unit cards**, plus basics. **Jawas** and an **Obi-Wan unit card** are mid-chapter pickups.
- Enemies: **Tuskens and their hounds**.
- Base: **Dune Sea** and/or **Jundland Wastes**, rotating along the path; **changes to Mos Eisley** at the final boss.
- Rest stop: Mos Eisley cantina. Mid-chapter node: the Luke-is-knocked-out **defend-a-unit** objective (5.5).
- Boss: Mos Eisley — **Greedo / stormtroopers / scum**; **Han Solo and Chewbacca get added to the hand/pool** here.
- Custom claimable token candidate: **"Krayt Call."**

**Chapter 2 — Death Star rescue**
- Leader choice opens between **Han Solo** or **Chewbacca** (both selectable — see 12 for the open question on which is canonical); **Luke, C-3PO, Leia, R2** carry from Ch.1. Obi-Wan as a unit card.
- Base: Death Star-themed base. Enemies: stormtroopers; trash-compactor monster node; rest stop = detention block / command room.
- Climax: **Vader boss fight** (Obi-Wan vs Vader while Luke's objective is simply to **survive**).
- Custom claimable token candidate: **"Alarm"** (enemy side).

**Chapter 3 — Battle of Yavin**
- Opens with **Luke Skywalker, "Hero of Yavin"** (JTL #12) as **pilot leader**; **all-space chapter**. Deck shifts to Rebel starfighters (X-wing, Y-wing, A-wing, Millennium Falcon). **Han appears as an upgrade card** (Falcon assist for the trench run).
- Enemies: **TIE fighters, Death Star turbolasers; Vader (TIE Advanced)** final boss, possibly a double-space-arena Twin Suns final. Chapter and episode end with the Death Star's destruction.
- Rest stop: Echo Base / Yavin 4 — **note:** there is *no* standalone Yavin 4 base card in SWU; Echo Base (Command) is Hoth-specific. Use a **custom-designed Yavin base** or accept thematic looseness.

### 5.9 Enemy side design **[DECIDED where noted]**
- Enemies don't need a real leader in the deckbuilding sense (aspect penalties off). A node defines an **enemy deck list + scripted AI profile + optional pre-placed units + hero/leader skin and HP**.
- Both sides may fight over a **single shared battlefield base** treated as flavor + HP, not a deckbuilding constraint. **[OPEN]** whether a shared base is one HP pool or each side keeps its own (leaning: each keeps own HP, art is shared).
- Enemy AI: see Section 8.

### 5.10 Other episodes
Mapped only at concept level so far (build the same 3-chapter template; **do not invent specifics — Dom will provide them chapter by chapter**):
- **Episode I:** Anakin as child (Tatooine) → Naboo. Verification of Qui-Gon, Maul, Nute Gunray, and the Obi-Wan Padawan leader is still **pending** **[OPEN]**.
- **Episode II:** Many "Child Anakin" unit cards for an early chapter; **"Anakin Skywalker, What It Takes to Win"** for a chapter-2 Anakin; **"Anakin Skywalker, Protect Her at All Costs"** (Sentinel-flavored leader) for an end-of-arc chapter.
- **Episode III:** a pure Heroism Anakin and a pure Villainy Anakin both exist — for the "Tempted by the Dark Side" arc. Climax = the dual-fight Twin Suns finale in 5.7.
- **Episodes V, VI:** Hoth set piece (5.7) is the V centerpiece. VI climax = Vader helmet-removal-death scene card ("Anakin Skywalker's You Were Right About Me"/Darth Vader card).
- **Episodes VII–IX:** not yet discussed.
- **Process Dom wants:** comb the card database set-by-set / era-by-era to assign cards to films/arcs and decide what unlocks when. Build tooling for this (Section 10).

---

## 6. Card/leader reference (corrected from physical-card photos — use to sanity-check the import)

### 6.1 Bases
Bases carry **ONE aspect icon** each (not two).
- **Dune Sea** — Homeworlds HMW 19 — Vigilance (blue).
- **Jundland Wastes** — Homeworlds HMW 28 — Aggression (red). Lore: rocky canyon badlands on Tatooine bordering the Dune Sea, home to Tusken Raiders; site of Luke's ambush and Obi-Wan's Krayt-dragon call; near Obi-Wan's hermit hideout.
- A **green (Command)** and **yellow (Cunning)** Tatooine base also exist in Homeworlds — names **not yet identified [OPEN]**; pull from DB.

### 6.2 Leaders
- **Luke Skywalker, "Hero of Yavin"** (JTL #12): **Aggression-Heroism** (red-white). Leader-unit: Fighter synergy; can't be defeated by enemy abilities; attached Fighter gains "On Attack: may deal 3 damage to a unit." Leader side: Action [pass]: if you attacked with a Fighter this phase, deal 1 damage to a unit. Epic Action at 6+ resources: deploy as leader or as an upgrade on a friendly pilotless Vehicle.
- **C-3PO, "Human-Cyborg Relations"** (SEC #15): **Cunning-Heroism** (yellow-white). Leader-unit: "On Attack: if you control another exhausted unit, you may exhaust a unit." Leader: Action [1, pass]: same if you control an exhausted unit. Epic Action at 4+ resources. Cost 4 / Power 1 / HP 6. (Ability is about *exhausting*, not returning to hand.)
- **Han Solo, "Audacious Smuggler"** (SOR #017): **Cunning-Heroism**, Underworld. Leader-unit: "On Attack: put top card of deck into play as a resource, ready it; at the start of next action phase, defeat a resource you control." Leader: same effect but discarding from hand. Epic Action at 6+ resources. Cost 6 / Power 4 / HP 6.
- **Chewbacca, "Walking Carpet"** (SOR #003): **Vigilance-Heroism**, Underworld/Wookiee, Sentinel + Grit. Leader: Action [pass]: play a unit costing ≤3 from hand; it gains Sentinel for the phase. Epic Action at 7+ resources. Cost 7 / Power 2 / HP 9.
- Rejected: *Luke Skywalker, "Faithful Friend"* for Tatooine (Bespin-era theme). Prefer a Luke **unit** themed on beginnings (e.g. "A Hero's Beginning," pure Heroism).
> [VERIFY] all of the above against the imported DB; earlier verbal guesses were wrong several times.

### 6.3 Keyword badge list
Sentinel, Shielded, Grit, Saboteur, Ambush, Overwhelm, Raid, Restore, Coordinate, Exploit, Smuggle, Piloting, Hidden → each needs an on-board badge icon (Section 8.3).

---

## 7. Data schemas (proposed; adjust as needed but keep data-driven)

### 7.1 Card
```json
{
  "id": "SOR_017", "set": "SOR", "number": 17, "name": "Han Solo", "subtitle": "Audacious Smuggler",
  "type": "leader|unit|upgrade|event|base|token", "arena": "ground|space|null",
  "cost": 6, "power": 4, "hp": 6, "aspects": ["cunning","heroism"], "traits": ["underworld"],
  "keywords": [{"k":"sentinel"}], "text_raw": "…", "effects": [ /* compiled DSL */ ],
  "leader": { "epic_threshold": 6, "action": {...}, "unit_side": {...} },
  "art": { "full": "...", "hex": "...", "thumb": "..." }, "implemented": "full|partial|manual"
}
```

### 7.2 Chapter
```json
{ "id": "ep4_ch1_tatooine", "episode": 4, "title": "Tatooine", "alignment": "heroism",
  "leader_options": ["SEC_015"], "starting_deck": ["..."], "base_sequence": ["HMW_019","HMW_028","MOS_EISLEY"],
  "base_hp_override": 18, "ruleset": "campaign", "map": "ep4_ch1_map",
  "pickups": [{"card":"...","node":"..."}], "unlocks_on_clear": ["..."], "next_chapter": "ep4_ch2_deathstar" }
```

### 7.3 Node & objective
```json
{ "id": "...", "type": "fight|elite|objective|event|rest|shop|boss", "objective": "survive_n|hunt|defend_unit|attrition|standard|escort",
  "params": {"rounds": 4, "protect_unit": "luke_unconscious"},
  "enemy": {"deck": [...], "ai_profile": "aggressive", "hero_skin": "tusken_raider", "preplaced": [...], "hp": 12},
  "turn_mode": "alternating", "arenas": ["ground"], "claimable_tokens": ["initiative","krayt_call"],
  "reward_tier": 2, "board_theme": "tatooine_dunes" }
```

### 7.4 Claimable token
```json
{ "id": "krayt_call", "name": "Krayt Call", "side_claimable": "player|enemy|both",
  "cost": "ends_round_actions", "effect": [ {"op":"remove_unit","filter":{"trait":"tusken"},"count":1} ],
  "once_per": "round|node", "icon": "..." }
```

---

## 8. UI, visuals, audio

### 8.1 Board **[DECIDED]**
- **2D, flat illustrated** (not 3D), Hearthstone-style board frame. Layered background art per location with Spine/tween animation: rotating vaporator fans, blinking lights, **twin-suns parallax** (Tatooine), **falling snow + ion cannon + shield generator on Rebel corner + AT-AT head in Imperial corner** (Hoth), **TIE fighter shadows and passing sound effects** (space/Death Star). Art can be AI-generated, commissioned, or stand-in sci-fi packs initially; build with swappable `BoardTheme` resources (background layers, ambient emitters, corner props, music/SFX bank).
- Two **arenas** laid out per orientation: in landscape, side-by-side lanes or stacked rows; in portrait, stacked ground over space with a clear divider. Each player's **base** shown with HP, resources, hand, deck count, leader portrait/unit.
- Hand fan, resource pips, initiative/token tray (shows Initiative + any node-specific claimable tokens), objective tracker widget, and a log/history drawer.

### 8.2 In-play unit representation **[DECIDED]**
Following Hearthstone's convention, units on board show **only a cropped token with power/HP and keyword badges — not the full card**. Use a **HEXAGON** token (not oval/circle) for a sci-fi feel and tileable layouts. Full card appears on hover/long-press (inspect view). Damage/heal numbers, shield glow, exhausted state (rotated/dimmed), upgrade pips, captured-unit indicator.

### 8.3 Keyword badges
One small readable icon per keyword (list in 6.3), consistent silhouette language, legible at ~24px. Shield = distinct overlay for the Shielded state. Provide a legend screen.

### 8.4 Combat animation **[DECIDED, wanted]**
- **Lightsaber swipe** animations on hero/leader attacks, **colored by lightsaber color** (per-character color field in data).
- **Blaster bolts** and impact flashes for ranged/ship attacks; turbolaser beams for big guns.
- Attack-lunge, damage numbers, defeat dissolve. Keep effects GPU-cheap (Section 9).

### 8.5 Audio
SFX for card play/attack/defeat/token claims, ambient loops per board theme, TIE-flyby stingers; music per chapter/boss. Placeholders until Dom supplies/licenses audio. Do not embed copyrighted film audio in the repo.

### 8.6 Screens
Title/home; campaign map (episode → chapter select, with locked/unlocked states); chapter intro; node map; match board; reward screen; deck viewer; **collection vault** (browse unlocked cards); bot-match setup; settings (audio, language-neutral text size, orientation lock, performance mode); tutorial/onboarding. All must work in both orientations.

---

## 9. Performance (explicit budget)
- 60 fps target on mid-range phones; test on a deliberately **low-end** device profile. Provide a **Performance Mode** toggle (fewer particles, static background, no parallax).
- Texture atlasing, compressed textures (ASTC/ETC2), lazy-load card art, object pooling for tokens/particles, avoid per-frame allocations in the engine, cap simultaneous Spine skeletons, prefer `GPUParticles2D`/shaders over per-sprite scripts.
- Engine/AI must be fast enough that bot turns resolve in well under a second; run AI search on a thread if needed.
- Cold start < 3 s on target; keep the base APK small by streaming/optional-downloading art packs per episode.

---

## 10. Bots / AI and tooling

### 10.1 Bot AI
- Required for: campaign enemies (scripted profiles per node), standard bot matches, tutorials.
- Start with a **heuristic/rule-based AI** (evaluate play-card / attack / claim-initiative options by scored heuristics: trade value, base pressure, sentinel/shield awareness, objective awareness). Provide **profiles** (aggressive, defensive, tempo, scripted-boss). Boss AI can follow authored scripts (phase changes, token claims). **Later [OPEN]:** Monte-Carlo tree search or simulation-based AI for the vault/standard bot mode.
- Make AI deterministic under a seed for testing and replays.

### 10.2 Developer tooling (high value, build early)
- **Headless match simulator** (bot vs bot, thousands of games) for balance and for catching rules-engine crashes.
- **Card coverage report** (what % of the campaign pool is implemented).
- **Campaign editor/validator:** a script or Godot tool to author chapters/nodes/objectives from JSON and validate (all card ids exist, aspect/heroism gate respected, decks legal for the campaign ruleset, ~10-minute budget estimate via simulation).
- **Card-assignment helper** to comb the DB and tag cards to films/chapters (Dom's stated next step).
- Replay/log format (deterministic seed + action list) for debugging.

---

## 11. Build order (milestones)

1. **M0 — Repo & scaffolding:** Godot project, folder layout (`/engine`, `/data`, `/assets` [git-ignored IP], `/docs`, `/tools`, `/tests`), CI-style headless test runner, config constants, theme with fonts.
2. **M1 — Rules engine core:** zones, resources, play/attack/initiative/pass, round loop, base/leader/unit/upgrade/event, damage, Shield/Experience tokens, win condition. Unit-test against the PDF's examples.
3. **M2 — Keywords + ability resolver + DSL:** all keywords; trigger windows; targeting; implement enough card text to run the Tatooine ch.1 pool end-to-end.
4. **M3 — Card import pipeline:** ingest DB, art crops (full/hex/thumb), coverage report.
5. **M4 — Playable board UI (one theme, both orientations):** hex tokens, hand, targeting UX, animations placeholder. Bot plays a full match.
6. **M5 — Campaign vertical slice:** **A New Hope Ch.1 (Tatooine)** — leader C-3PO, ~15-card deck, node map with 5–6 nodes, one defend-a-unit objective, rest stop, rewards, Mos Eisley boss, save/load. Hit the ~10-minute target.
7. **M6 — Node system breadth:** objective plug-ins (survive, hunt, attrition, escort), claimable-token system (Krayt Call, Alarm), `TurnMode.BURST` option.
8. **M7 — Ch.2 and Ch.3:** Death Star rescue (Han/Chewbacca leader choice, Vader boss) and Yavin space chapter (dual-arena/Twin Suns finale support, custom Yavin base, custom turbolaser cards).
9. **M8 — Presentation pass:** Spine/animated boards, lightsaber/blaster FX, audio, keyword badge set, polish, performance profiling on low-end device.
10. **M9 — Vault, bot mode, Twin Suns mode, local PvP.**
11. **M10 — Remaining episodes** following the template, driven by Dom's per-chapter specs; then the Villainy campaign mirror.

---

## 12. Open questions (do not decide silently)

1. **Game name** — pinned for later by Dom.
2. **Chapter 2 leader:** both Han and Chewbacca selectable as currently planned, or is one canonical? (Currently: both selectable.)
3. **Missing Tatooine bases** (green Command + yellow Cunning) — names unknown; pull from DB.
4. **Shared-base HP model** in nodes (one pool vs each side's own).
5. **Yavin base** — custom card vs loose reuse.
6. **Episode I leaders** (Qui-Gon, Maul, Nute Gunray, Obi-Wan Padawan) — unverified.
7. **Burst turn mode** — which node(s), if any, ship with it.
8. **Networked PvP** — in or out of scope.
9. **Art sourcing strategy** — AI-generated vs commissioned vs stand-in packs (stand-in suggestions: Unity Asset Store, Unreal Marketplace, Sketchfab, Quixel Fab, Kitbash3D desert/sci-fi packs as 2D reference only).
10. **Spine license** — Dom to confirm whether he'll buy it; until then use the built-in animation fallback.
11. **Exact tuning:** base HP, starting deck size, reward tables, difficulty curve.
12. **Exact DB source and licensing posture** for card text/art in distribution (private use only for now).

---

## 13. Files Dom is providing
- `/docs/SWH_Comp_Rules_v9_0_*.pdf` — official Comprehensive Rules v9.0 (10/9/26). **Read it before M1.** Note section 9.3 *Trilogy format*, section 11 multiplayer, and section 12 Twin Suns.
- `/data/` — card database dump (SWU-DB API or equivalent) + art.
- `/reference/` — reference photos (board themes, card photos incl. the Tatooine bases and the five leader/base photos already analyzed in 6.1–6.2).
- `/assets/fonts/` — Star Wars-style English + Aurebesh fonts.
