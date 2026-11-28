# Free internet multiplayer for MIDNIGHT SYNDICATE (Godot 4.7.2, iOS first)

Date: 2026-11-28. Scope: zero-cost online races without running a server on the owner PC.
Status legend: VERIFIED (read on the source page), SECONDARY (aggregator or forum), UNVERIFIED (from memory or no source found).

## 0. Where we are today

- `docs/design/ONLINE_LAN.md`: online race is LAN or loopback only. ENet, port 24580, bound to 127.0.0.1 or a LAN address. No encryption, no auth, no NAT traversal. "Not internet multiplayer."
- `game/net/` holds the lobby, protocol v1, server race authority, client glue, rejoin logic (`net_session.gd`, `net_race_authority.gd`, `net_race_glue.gd`, `net_reconnect.gd`, `net_hello_limiter.gd`).
- The server-authoritative design is good. It stays. Internet play only changes the transport and the matchmaking layer.
- Key fact: ENet itself does not punch through NAT. Any internet option needs one of: a public relay, a hole-punch service, or a rented server.

## 1. The two problems to solve separately

1. Matchmaking and signalling: find the other player, swap connection info (SDP/ICE or IP:port), check the join code.
2. Data path: the race packets. Either direct (P2P with NAT punch), relayed by a free service, or via a server we rent.

Most free options solve only one of these. Mixing them is normal.

## 2. Options, one by one

### 2.1 Godot WebRTC (WebRTCMultiplayerPeer) with a free signalling server

What it gives: browser-grade P2P data channels, NAT traversal through ICE. Godot's High-Level Multiplayer runs over `WebRTCMultiplayerPeer`, so RPC and the scene sync code stay the same.

Facts:
- Peers must swap SDP and ICE candidates first. Godot docs say this "usually takes the form of a so-called WebRTC Signaling Server", which the developer must build or supply. After setup the peers can drop the signalling server. (VERIFIED: https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html)
- Native (non-HTML5) builds need the external GDExtension plugin `webrtc-native`. The Godot page says so. That means on iOS we need that plugin, and it is a third-party binary to vet. (VERIFIED, same page.)
- The Godot WebRTC page does not describe iOS or STUN/TURN setup. It is marked work in progress and may lag 4.7. (VERIFIED, same page.)
- Godot's demo `networking/webrtc_signaling` has a WebSocket signalling example. (VERIFIED, same page.)
- STUN is cheap and common (public Google STUN exists, UNVERIFIED terms). TURN relays all traffic when NAT blocks direct paths. TURN costs money at scale. Roughly 10 to 30 percent of mobile carrier NATs need TURN (UNVERIFIED, typical industry figure, check before relying on it).

Free signalling host candidates:
- Cloudflare Workers + Durable Objects (WebSocket hub). Free plan: 100,000 requests per day, 13,000 GB-s per day, 5 GB storage, SQLite-backed Durable Objects only. Daily limits reset 00:00 UTC. Going over fails the operation. Incoming WebSocket messages are billed at a 20:1 ratio (VERIFIED on Cloudflare pricing page via fetch; the 20:1 rule is stated there). Plan: 100 incoming messages = 5 billed requests. Signalling is tiny (a few messages per match), so the free tier is ample for a small player base. (VERIFIED: https://developers.cloudflare.com/durable-objects/platform/pricing/)
  - Caveat: a community thread reports Free-tier WebSocket upgrade failures in October 2026 (SECONDARY, unresolved): https://community.cloudflare.com/t/durable-objects-free-quota-block-below-100k-after-websocket-20-1-adjustment/967650
- Deno Deploy. Secondary reports say the Free plan is 1M requests, 20 GiB egress, 10 CPU hours, 150 GiB-hours memory per month. Sources disagree (older 15 CPU hours). Deno Deploy Classic was reportedly retired on 2026-07-20; use the current console. (SECONDARY, conflicting: check https://deno.com/deploy/pricing.) WebSocket limits: not found.
- Fly.io. Free tier is gone for normal use. New accounts get $1 credit with no card, then $5 of usage per month once a card is added, max 3 machines on Free. The cheapest always-on machine is $2.19 per 30 days, so it is not free (VERIFIED on docs.fly.io/about/pricing). A $5/month allowance may cover a tiny signalling box, but it needs a card on file. That is a payment agreement the owner must accept.

Verdict for signalling: Cloudflare Durable Objects is the best zero-cost choice. Needs a Cloudflare account (free, no card for the Free plan as far as the pricing page shows; UNVERIFIED on card requirement). Owner must accept Cloudflare terms.

Security: signalling is untrusted. Validate the join code server-side in the Worker (same rule as `net_session.gd`). Never trust SDP from the wrong room. Rate-limit per IP.

iOS: WebRTC needs the native plugin plus an iOS export with the right permissions. Without it, the game cannot use this path on iPhone. Effort: medium-high. Maturity on iOS: UNVERIFIED for 4.7.

### 2.2 Godot High-Level Multiplayer over WebRTC (the glue)

Use `MultiplayerAPI` with a `WebRTCMultiplayerPeer` as the peer. Our protocol v1 (plain Dictionaries via `var_to_bytes`) would move onto it with little change, because the messages already travel as bytes. Unreliable state needs an unreliable data channel. `WebRTCDataChannel` can be set unordered and unreliable (UNVERIFIED API detail, check the 4.7 class docs before coding).

Effort: the transport swap. The authority logic stays. The rejoin and hello limiter need re-checking because the peer identity changes.

### 2.3 Nakama and Colyseus (self-hosted)

- Both need a running server process. A free host is the problem (see 2.1 host list). Nakama and Colyseus are open source (UNVERIFIED licence claims, check repos before use).
- Not a fit for "no server on the owner PC" unless we rent a box. Rent cost is above zero.
- Godot clients exist for both (UNVERIFIED maturity).

Verdict: skip for zero cost. Keep as a later paid step if the owner accepts a small monthly bill.

### 2.4 Steam

Steam is not on iOS. Steam Networking Sockets would give free relay on PC, but the iOS build cannot use it. Our target is iOS first. Skip for this phase. (Owner decision if PC release later.)

### 2.5 Apple Game Center (GameKit) real-time matches

- GKMatch is a peer-to-peer real-time connection that Game Center sets up. Players exchange data through the match object, not through our server. Send modes: reliable and unreliable. (SECONDARY: Apple GKMatch page, the body text did not load; fetched title only. Confirm limits at https://developer.apple.com/documentation/gamekit/gkmatch.)
- Requirements: Game Center capability (`com.apple.developer.game-center`), players signed in to Game Center, an App Store Connect app record. (SECONDARY, from the Apple doc summary.)
- Cost: included with the Apple Developer Program fee the owner already needs for iOS builds. No extra fee. (UNVERIFIED wording, check the membership page.)
- Godot integration: no maintained Godot 4 plugin found that exposes GKMatch. Candidates: `zt-pawer/GodotApplePlugins` (GameCenter plugin, PR #1 open about matchmaker dismissal) (SECONDARY: https://github.com/zt-pawer/GodotApplePlugins); official godot-ios-plugins Game Center plugin (article about 846 days old, build steps may be stale) (SECONDARY: https://www.peanuts-code.com/en/tutorials/gd0021_game_center_plugin/). A custom native plugin (Swift) is probably needed.
- Apple's Unity plugin docs describe the matchmaking flow (match request, data received, state change). Useful as API reference only (SECONDARY: https://github.com/apple/unityplugins/blob/main/plug-ins/Apple.GameKit/Apple.GameKit_Unity/Assets/Apple.GameKit/Documentation~/Apple.GameKit.md).
- Limits: GKMatch is a mesh between phones, so NAT and relay are Apple's job. Useful for 2 to 8 players (UNVERIFIED cap; some sources say 16).
- Security: match data is not encrypted by us beyond what the GameKit transport gives (UNVERIFIED). Server-authoritative checks in `net_race_authority.gd` still apply. A phone is not trusted.
- Leaderboards: Game Center leaderboards are free with the same account. Use them for times. Good fit.

Verdict: best iOS-native option at zero extra cost. Effort is high (native plugin, Swift, GDExtension or iOS plugin build). Needs the owner's developer account, which the owner already has for iOS.

Account the owner must accept: Apple Developer Program terms (already needed), Game Center enabled in App Store Connect.

### 2.6 Epic Online Services (EOS)

- Epic's licensing page says EOS is free for video games with no royalty or hosting fees for most services, and says anti-cheat and extra features need a paid enterprise agreement (SECONDARY: https://onlineservices.epicgames.com/licensing was not readable in this run; the free claim comes from the search summary of that page and the homepage). Recheck the live terms before relying on it.
- Features relevant to us: lobbies, sessions, P2P networking with NAT punch and relay (EOS P2P relay, SECONDARY via DeepWiki and EOSG docs), voice.
- Godot plugins:
  - EOSG by 3ddelano: MIT, lists iOS (arm64), Godot 4.2+ (asset library lists 4.3). Lobbies, sessions, P2P, RTC. (SECONDARY: https://github.com/3ddelano/epic-online-services-godot)
  - GD-EOS by Daylily-Zeleen: offers an `EOSMultiplayerPeer` for Godot multiplayer, lists iOS. (SECONDARY: https://github.com/Daylily-Zeleen/GD-EOS)
- Owner must do: create an Epic Developer account and a product on the Epic developer portal, accept the EOS terms (an agreement, so ask the owner first per CLAUDE.md), set up the iOS build with the EOS C SDK.
- Security: EOS gives an authenticated identity if we use Epic accounts or device IDs. Anti-cheat is the paid part. Our server rules still matter: a P2P host can cheat, so race truth needs a trusted host or the existing rules must run on each peer. Not solved by EOS.
- Risk: the P2P data path is in Epic's hands. Latency and relay behaviour on iOS are UNVERIFIED for our game.

Verdict: strongest all-in-one free option for lobbies plus P2P on iOS. Biggest risk is the agreement and the iOS SDK integration effort. Good candidate for the first prototype.

### 2.7 Other free relays and lobbies (quick list)

- Public ENet relays: none reliable. Skip.
- Hosted TURN free tiers (Twilio, Metered, Xirsys): free tiers exist but change often (UNVERIFIED). Check before use. A TURN backup needs a signed-up account.
- Firebase Realtime or Firestore for signalling: free Spark plan exists (UNVERIFIED limits). Works, but a Google account and terms apply. Not better than Cloudflare.

## 3. Comparison table

| Option | Cost (zero-budget fit) | Owner accepts | iOS support | Godot effort | Security notes |
|---|---|---|---|---|---|
| Cloudflare DO signalling + WebRTC | Free plan, 100k req/day, 20:1 WS billing | Cloudflare terms, maybe card | Needs webrtc-native GDExtension on iOS | Medium-high | Validate code in Worker, rate limit |
| Deno Deploy signalling + WebRTC | Free plan (figures conflict) | Deno terms | Same as above | Medium | Same; WS limits unknown |
| Fly.io small box | $5/mo usage credit with card | Card + Fly terms | Same as above | Medium | Box must be patched |
| Nakama / Colyseus | Needs a paid or rented box | Host terms | Client works | Medium | Server-side auth possible |
| Steam networking | Free | Steamworks | Not on iOS | n/a | n/a |
| Game Center GKMatch | Free with Apple dev program | Apple terms (already) | Native | High (custom plugin) | Data unencrypted by us (UNVERIFIED) |
| EOS (P2P + lobbies) | Free for games per Epic page | EOS terms, Epic dev account | Yes per EOSG | Medium (plugin) | Anti-cheat paid; P2P host trust issue |

## 4. Recipe for our game (step by step)

1. Keep `net_race_authority.gd` and protocol v1 as the truth. Do not move the race rules into the transport.
2. Add a transport interface in `game/net/` (for example `net_transport.gd`): ENet (LAN, today), and later `net_transport_eos.gd` or `net_transport_webrtc.gd`. Lead-owned contract. Test: the existing `test_net_protocol.gd` and `test_net_race.gd` still pass on ENet.
3. Prototype EOS first on a desktop build (headless smoke: `py -3.10 tools/net_smoke.py`). Target: 2 processes join by lobby code through EOS, no LAN IP. Verify: log lines show the same `wrong_code_refused` and `start` checks as today.
4. Prototype GKMatch on a real iPhone only after the owner has the developer account. Target: 2 phones, match, reliable lobby message, unreliable state at 20 Hz. Verify with a real device (no desktop substitute). Measure RTT on a real network. Log it under `evidence/`.
5. Only if EOS and GameKit fail: Cloudflare DO signalling + webrtc-native. Verify with `tools/net_impair_proxy.py` and `tools/net_impair_run.py` (the 80 ms and 5 percent loss cases from ONLINE_LAN.md) plus a real two-network test.
6. Keep the join code rule on every path. The code is checked on the host only; EOS and GameKit do not replace it.
7. Put the leaderboard on Game Center (free, same account) once online times are trusted.
8. Ask the owner before any agreement, account, or download: EOS terms, Cloudflare account, Apple Game Center setup, any plugin download (CLAUDE.md rule). Record each plugin in `ASSET_MANIFEST.json` or `THIRD_PARTY_LICENSES.md` if it ships.

Update `ONLINE_LAN.md` after each step with the measured numbers and the device names. Never report desktop numbers as iPhone numbers.

## 5. Risks and what not to do

- Do not expose the owner PC to the internet. No port forwarding. ENet bound to a public IP is refused by design and must stay refused.
- Do not ship ENet on the internet as is: no encryption, no auth. Each option above adds some of that; check what it really adds before claiming it.
- Do not claim "internet multiplayer works" from loopback or LAN tests. Only real two-network tests count.
- Do not trust any phone. A P2P host can lie about progress. The authority rules must run on a host the cheater does not control, or the game must accept that cheating exists and say so.
- EOS free claim and Fly/Deno/Cloudflare free limits change. Re-check the live pages on the day of use.
- GameKit has no public Godot 4 GKMatch binding; a native plugin is real work and needs iOS testing.
- TURN is not free at scale. If direct P2P fails for many players, the game breaks for them. Plan for a fallback.
- Do not use leaked or decompiled code from other games' netcode (clean-room rule).

## 6. Sources

- Godot WebRTC docs: https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html (VERIFIED)
- Godot High-Level Multiplayer: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html (listed, not fetched)
- Godot WebRTC community signalling thread: https://slapjam.ai/news/godot-web-multiplayer-websocket-webrtc/ (SECONDARY)
- Cloudflare Durable Objects pricing: https://developers.cloudflare.com/durable-objects/platform/pricing/ (VERIFIED)
- Cloudflare community thread on Free WebSocket quota: https://community.cloudflare.com/t/durable-objects-free-quota-block-below-100k-after-websocket-20-1-adjustment/967650 (SECONDARY, unresolved)
- Deno Deploy pricing: https://deno.com/deploy/pricing (not fetched, conflicting secondary figures)
- Fly.io pricing: https://docs.fly.io/about/pricing (VERIFIED)
- Apple GKMatch: https://developer.apple.com/documentation/gamekit/gkmatch (title only; body not read)
- GodotApplePlugins: https://github.com/zt-pawer/GodotApplePlugins (SECONDARY)
- Peanuts Code Game Center plugin: https://www.peanuts-code.com/en/tutorials/gd0021_game_center_plugin/ (SECONDARY, old)
- Apple GameKit Unity docs (API reference): https://github.com/apple/unityplugins/blob/main/plug-ins/Apple.GameKit/Apple.GameKit_Unity/Assets/Apple.GameKit/Documentation~/Apple.GameKit.md (SECONDARY)
- Epic Online Services licensing: https://onlineservices.epicgames.com/licensing (SECONDARY, not readable in this run)
- EOSG Godot plugin: https://github.com/3ddelano/epic-online-services-godot (SECONDARY)
- GD-EOS Godot plugin: https://github.com/Daylily-Zeleen/GD-EOS (SECONDARY)
- Project files: `docs/design/ONLINE_LAN.md`, `game/net/net_session.gd`, `game/net/net_config.gd`, `game/net/net_race_authority.gd`, `tools/net_impair_proxy.py`
