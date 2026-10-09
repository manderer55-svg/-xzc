# Independent visual and runtime audit

Scope: native Godot 4.6.3 scenes, generated cartoon dark-fantasy world art, mobile readability, construction and party animation, grounded placement, input and save/performance behavior. This is an evidence-based review, not a claim of commercial AAA quality or a rating awarded without device testing.

## Findings fixed

| Severity | Defect and evidence | Change | Verification |
| --- | --- | --- | --- |
| Medium | Four party sprites overlapped into a single unreadable cluster in the earlier expedition capture. Fixed lateral formation offsets also allowed followers to stand in neighboring blocked forest cells despite a valid leader route. | Followers now sample the actual traversed route at 52 px intervals, or 62 px for horses. Work positions use reachable unoccupied neighboring cells, not arbitrary decorative offsets. | 1,396 member-position checks across all 12 generated deposit routes passed. Native walking captures show separate silhouettes. |
| Medium | The actions atlas does not divide into exact thirds: cavalry begins around y=238, builders around y=517. Equal 256 px rows cropped horses and leaked neighboring heads/hammer pixels. | Measured alpha-bound AtlasTexture regions and transparent logical padding, without editing the generated originals. | Viewed original RGBA art and actual native scenes. All 24 action frames use individual measured regions. |
| Medium | Archers and cavalry extracted resources using stationary walking frame zero. Mounted riders also appeared to mine while sitting on horses. | Generated new eight-frame archer and dismounted cavalry pickaxe cycles plus riderless idle horses. Cavalry parks three horses on separate valid ground cells with independent depth sorting. Parking positions are cached for the mining phase. | Four distinct native frames per class; actual pickaxe poses change. Horses do not cover the miners. |
| Medium | A first attempt at horse parking used a sprite overlay beside each worker and obscured workers. | Separate ground nodes and occupied-cell exclusion. | Second native capture shows workers and parked horses separately; superseded overlay implementation removed. |
| Medium | Instant completion gave no visible construction process. | Persistent real-time work queue, generated foundation, animated hammering builder, visible countdown; existing building remains during upgrades. | Native construction capture and four hammer phases. First construction displays 00:02:00; completion is controlled by the model timestamp. |
| Medium | Full progress data was copied every frame and saved every two seconds even with no expedition activity. | Parent agent implemented transaction prediction, no idle checkpoint writes, event-based long offline advancement. | Economy regression/profile output: 3,000 idle ticks produce zero writes; finite multi-day catch-up completes in milliseconds. Final economy regression: 161 checks; 3,000 idle ticks around 55 ms total, zero writes; three-day finite catch-up around 145 ms. Timings are desktop diagnostics, not phone FPS. |
| Low | Catalog still advertised four building levels after the progression grew to 20. | Catalog reads the current 20-level progression. | Source review and model/UI regression. |
| Medium | Old 0.25-second cell travel appeared to slide quickly across the map. | New jobs use 1.5 seconds per cell, with snapshotted logistics bonuses. Old saved jobs retain their legacy duration for compatibility. | 72 px isometric steps now take 1.5 seconds at baseline, about 48 px/s. |
| High | Renderer used plural `archers`, while actual HeroModel dispatch uses canonical `archer`. Earlier synthetic fixture IDs masked the integration failure and actual archers rendered as infantry. | Renderer now uses canonical IDs; fixture enumerates HeroModel.TROOPS and performs actual training, selection and dispatch. | Three actual canonical dispatches; atlas-source assertions and native archer walk/extraction captures passed. The obsolete plural-ID images were removed. |
| Medium | Mining workers collapsed onto the leader at the start of a return, with instant remounting. A free neighboring work cell could be unreachable, causing a teleport fallback. | Short reachable work/parking routes, individual movement toward work and parked horses, continuous return regrouping, no empty-route teleport. | Mine-departure position-continuity assertions; 48 complete-party arrival checks across 12 deposits passed. |
| Medium | A return leader reached the gate before followers, so the model removed followers outside the castle. | Saved gate arrival hold, formation closes along its actual route, and each actor enters the castle at the gate. | Actual model advancement verifies all four members within 12 px of the gate before each job disappears. |
| Low | Hero-to-worker size ratio approached 1.7 because padding reduced visible mining bodies; ore numbers crossed worker silhouettes. | Hero canvas 56 px, workers 52 px walking / 64 px working with measured padding, ore figures moved above the deposit. | Native screenshots show readable distinct grounded silhouettes and clear counters. |
| Medium | Map-edge cameras exposed a large black void near the castle. | Generated forest ground/canopy scenery is batched outside the playable grid; no additional entities or playable cells. | Reviewed integrated city/region captures at both resolutions; actual 900-cell camera and navigation bounds unchanged. |
| Low | Hero upgrade looked available with zero owned cards despite requiring two. | Parent agent disables and tints upgrade when the selected hero has insufficient cards or is at maximum level. | Latest panel separately captured at 720×1280 and 450×800; native management tests passed 238 each. |

## Native evidence

All screenshots below are rendered game nodes using the generated art; they are not mockups.

- [Earlier crowded expedition](../art/preview/audit/before-expedition.png)
- [Corrected archers walking](../art/preview/audit/archer-outbound-0.png)
- [Archers extracting, phase 0](../art/preview/audit/archer-mining-0.png) and [phase 2](../art/preview/audit/archer-mining-2.png)
- [Dismounted cavalry extracting, with parked horses](../art/preview/audit/cavalry-mining-2.png)
- [Builder hammer phase](../art/preview/audit/builder-2.png) and [upgrade retaining the existing town hall](../art/preview/audit/upgrade-2.png)
- [Cavalry regrouping and remounting](../art/preview/audit/cavalry-return-3.png)
- [Integrated field on phone](../art/preview/expedition-phone.png), [construction on phone](../art/preview/construction-phone.png), [latest hero panel on phone](../art/preview/heroes-phone.png).
- Sampled four-phase native previews (not full frame-rate recordings): [builder](../art/preview/audit/builder.webp), [archer extraction](../art/preview/audit/archer-mining.webp), [cavalry extraction](../art/preview/audit/cavalry-mining.webp).

`tests/visual_capture.gd` reproduces 44 native frames with a process-specific isolated save and validates follower positions. It enumerates canonical `HeroModel.TROOPS`, trains and selects each type through HeroModel, then dispatches actual model jobs. Only phase/time/position fixtures are changed to inspect each visual state; troop IDs are not invented or patched. Texture source checks confirm that real `archer` jobs use the archer art. Separately, 12 cavalry returns are simulated through actual model advancement and checked for arrival before disappearance. It does not claim to be a full autonomous gameplay session. Run on a working X display:

```sh
DISPLAY=:97 bash tools/run_game.sh --audio-driver Dummy --resolution 720x720 --script res://tests/visual_capture.gd
```

Latest fixture output: `VISUAL_CAPTURE_OK actual_native_frames=44 canonical_dispatches=3 collision_checks=1396 arrival_checks=48 isolated_save=true`.

## Art direction assessment

The city and region share chunky silhouettes, teal roofs/fabric, bronze details, warm lights, and large readable stone/tree shapes. Buildings sit on the ground and participate in depth sorting; the 30×30 terrain and individual buildings are separate map objects. Tree trunks and buildings correctly obscure actors behind them. The cinematic title illustration is deliberately more detailed than small world sprites; its teal/gold palette connects it to the interface. It is not used as a substitute for the explorable map.

Important limits: four-phase hero walking is less fluid than the eight-phase troop/work cycles; it is acceptable at present sprite scale but should be compared on real hardware. The worker skill system is not a resource-field combat system. Alliance buildings currently provide local bonuses, not online alliance networking.

## Acceptance boundaries

Accepted within the implemented scope after corrections: native 720×1280 and 450×800 integrated scenes passed the complete UI smoke and 89 frame-corner checks, then were viewed directly. The last hero upgrade-button change was separately recaptured and passed 238 native management checks at each resolution, without repeating unrelated scenes. Current screenshots retain both resolutions. Independent final code re-review found no remaining concrete high or medium defect in the reviewed navigation, transitions and persistence fixes. This is not a blanket claim that every possible device or future game system is complete. No APK was exported for this audit. No physical Android handset has been used: touch feel, sustained frame pacing, heat, memory pressure, battery cost and interruption behavior on actual hardware remain unverified. Desktop timing cannot substitute for those measurements.
