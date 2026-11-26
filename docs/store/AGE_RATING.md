# Age rating: suggested questionnaire answers

Status: SUGGESTION ONLY. The owner answers the questionnaire in App Store Connect and must confirm every answer. Question wording and tier names come from the live form and may differ from this list. The tier names used here (4+, 9+, 13+, 16+, 18+) are from memory and not verified in this repository. RELEASE_CHECKLIST.md step 29 is still open.

## Basis for the answers

- Arcade street racing with original 3D cars. Violence is limited to car collisions: cars hit each other and walls and take visible damage. No people are shown being hurt, no blood, no weapons.
- No police pursuit is in the 1.0 feature list. Do not answer for a feature that is not in the build.
- Fictional content only: fictional city (Arden Bay), fictional Istanbul-inspired circuits, invented car makes. No real brands, licensed music or real people.
- Single player, offline, no accounts, no chat, no user-generated content, no web access, no ads, no in-app purchases, no random rewards.
- Races pay cash and reputation for finishing. Cash is spent on cars in the garage. Nothing is bought with real money and nothing is random for a purchase.

## Suggested answers

| Question (wording may differ) | Suggested answer | Reason |
|---|---|---|
| Cartoon or fantasy violence | None | The collisions are not cartoon or fantasy violence in the sense of stylised creatures or slapstick. Owner may choose Infrequent or mild if the collisions read as cartoonish. |
| Realistic violence | Infrequent or mild | Car crashes look realistic in 3D. Conservative answer. Nobody is shown injured. |
| Prolonged graphic or sadistic realistic violence | None | No gore or injuries. |
| Sexual content or nudity | None | No such content. |
| Profanity or crude humour | None | No spoken dialogue or crude text is in the build as far as the design document and i18n strings show. Owner confirms once voice work is checked. |
| Horror or fear themes | None | No horror content. Night setting is atmosphere only. |
| Medical or treatment information | None | None. |
| Alcohol, tobacco or drug use or references | None | None. |
| Mature or suggestive themes | None | None. |
| Simulated gambling | None | No betting or chance-based wagers. |
| Real gambling | None | No real-money wagering. |
| Contests | None | None. |
| Unrestricted web access | No | The game makes no network calls (see PRIVACY.md section 1). |
| User-generated content | No | No sharing, uploads or community content. |
| Messaging or chat | No | None. |
| Advertising | No | No ads in the app. |
| In-app purchases or loot boxes | No | No purchases in 1.0. |
| Health or wellness topics | None | None. |
| Parental controls or age assurance questions | Answer as the form requires | Not a content question for this build. Owner decides. |

## Expected result

- If every question is answered None, the expected tier is 4+ (from memory, unverified).
- If the realistic violence question is answered "Infrequent or mild" as suggested above, the expected tier is higher, likely 13+ (from memory, unverified).
- The tier App Store Connect shows after the questionnaire is the only result that counts. Record it here after the owner answers: `TODO(owner): resulting tier and date answered`.

## Before answering

- Owner confirms there is no voice line, spoken word or user text that would change the profanity answer.
- Owner confirms there is still no network code, purchase flow or ad SDK in the exported build.
- Owner confirms the final list of features in the build, because the answers assume the 1.0 feature list only.
