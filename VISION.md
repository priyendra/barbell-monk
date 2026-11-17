# barbellmonk

A voice-only workout coach for one person in a home gym.

## Purpose

Remove every unnecessary decision from a workout so full attention goes to the work itself.

barbellmonk does not teach. There are no videos, no form tutorials and no explanations unless asked. It assumes competence and decides what comes next: which exercise, what weight, when the rest is over.

**The test for every feature:** does it remove a decision from the user during a session, or add one?

## Scope

- Single user, personal use, private home gym.
- iPhone first. Apple Watch later.
- Wi-Fi is always available. There is no offline mode.
- Session types, about 1 hour each: lifting, core + cardio, flexibility + cardio.
- Also tracks body weight, daily movement and nutrition (calories and protein only).

## Interaction

- **During a session, voice is the only interface.** At most one tap to start. No looking at or touching the device after that.
- The mic stays open for the whole session. No wake word.
- Natural language, not a command vocabulary. The coach should feel like a knowledgeable fitness professional who adjusts to what you tell them ("I slept badly", "my shoulder is cranky", "give me something else").
- The app speaks first when it's time: it calls the next set, says when rest is over, and says what plates to load.
- Every logged number is repeated back, so a misheard value can be corrected by voice.
- Reasons are given only on request ("why?").
- No music for now, because it makes speech harder to recognize.
- Setup (equipment, exercise roster, program) and history review use a regular on-screen UI.

### Example

> **You:** Start workout.
> **Coach:** Day A. Squats first, 3 sets of 6 to 8 at 195. Load a 45, a 25 and a 5 per side.
> **You:** Got eight.
> **Coach:** Eight at 195. Rest two and a half minutes.
> **You:** Honestly I'm pretty beat today.
> **Coach:** Then let's drop to 175 for the next two sets and skip the last accessory. Take off the 5s and swap the 25s for 20s.

## Architecture

There are two layers, with a strict split between them.

**Workout engine: plain, deterministic Swift code.** It is the source of truth for every fact and number: history, progression, plate math, rounding to available equipment, the session plan and rest timers. It can be fully tested without voice or AI.

**Coach: Claude.** It understands speech, decides how to respond and how to adapt the session (fatigue, pain, preferences, swaps), and acts only through engine tools. It never makes up a weight or a plate setup.

Rules that hold the split together:

- Every adjustment is recorded with a reason (fatigue, user override, pain). That way progression treats a planned light day as planned, not as a failed attempt.
- Code enforces the limits. The coach can lower the load freely. Raising it beyond what progression recommends requires an explicit request from the user.
- Coach notes persist across sessions (for example, "left shoulder cranky on overhead press").

**Voice pipeline:**

1. On-device speech recognition, with echo cancellation and the ability to interrupt the coach mid-sentence.
2. Claude, with responses streamed.
3. On-device text-to-speech that starts speaking on the first sentence.

The app calls Claude directly over HTTPS, with no backend. The API key is stored in the Keychain.

**Model:** start with Claude Opus 5.5 (`claude-opus-5-5`) at low effort, then tune based on measured latency. The system prompt, tools and session history are prompt-cached.

## Training model

### Calibration instead of max testing

There is no 1RM test. The first time you do an exercise, the coach calibrates during the session:

1. Start at about half of a rough estimate.
2. Work up over 2–4 sets at the target reps. After each set, ask a one-word "easy / medium / hard?"
3. Finish with "as many good reps as you can, stop when one slows down."

The engine estimates a 1RM from that set and picks a working weight that leaves about 2 reps in the tank.

After calibration, every logged set keeps updating the estimated 1RM in the background. The estimate is used to spot stalls, to suggest starting weights for related exercises, and to show progress in the history UI.

### Sets record evidence, not just reps

The coach turns what you say into structured fields. The engine's rules only read those fields. The raw words are stored too, so old sessions can be reinterpreted if the rules change.

| You say | Recorded | Effect |
|---|---|---|
| "Ten, but I cheated the last two." | 10 reps, 8 clean | Progression and the estimated 1RM use 8 |
| "Eight, could've done three more." | 8 reps, ~3 in reserve | Bigger jump next time |
| "Six, that was a grind." | 6 reps, ~0 in reserve | Hold the weight |
| "Eight, but my lower back felt it." | 8 reps + note | Coach checks in, may lower the weight or swap the exercise; the note carries forward |

Self-reported effort is noisy, so it nudges the rules rather than overriding them.

### Muscle accounting

Every exercise is tagged with the muscles it trains (primary = 1 set, secondary = ½ set). The engine computes weekly sets and weekly frequency per muscle from the plan and from what you actually did. The coach uses that when you skip or swap something, for example to make up missed side-delt work later in the week.

### Equipment-aware progression

Each piece of equipment is modeled as the list of weights you can actually load. Progression steps through that list. Where the next step is a big relative jump (for example, dumbbells going from 30 to 40), it asks for more reps before moving up.

## Body weight, steps and nutrition

The same idea applies here: remove the effort and accept rough inputs.

- **Body weight comes from the smart scale through Apple Health**, so there is no manual logging. Saying a number ("182.4 this morning") also works.
- **The app reports the trend, never one day's reading.** Daily weight swings with water and salt, so a smoothed average is what counts. Target rate of fat loss: 0.5–1% of body weight per week.
- **Other scale measurements**, such as body fat %, are read too but shown only as trends, because scale body-fat readings are noisy.
- **Daily movement is measured in active minutes.** They come from barbellmonk's own sessions plus Apple Health, which merges Watch and iPhone data, so no Watch app is needed:
  - lifting, core and cardio sessions count in full; flexibility sessions count half, since the effort is low;
  - brisk walking outside sessions (about 100+ steps per minute), including the walking pad;
  - other workouts the Watch records, such as a hike or a ski day.
- **One daily target, plus a walking floor.** The active-minutes target is the same every day, so a lifting day needs less extra walking than a flexibility day. A separate walking minimum outside workouts, starting around 20 minutes, covers everyday movement, because an hour of training doesn't undo sitting the rest of the day. Both targets start from your recent baseline and rise slowly.
- **A 6 pm nudge** if you're short, saying how many minutes are left and that a walk on the walking pad closes the gap.
- Step counts are still shown, just not as a goal. Movement needs no separate calorie math, because the scale-based burn estimate already reflects it.
- **Food is tracked as two numbers: calories and protein.** You describe a meal in plain words, or take a photo, and the coach estimates both numbers. Repeat meals are saved and reused by name ("my usual breakfast").
- **Logging happens outside sessions**, through Siri or a simple chat screen in the app.
- **The scale corrects the food log.** The engine compares logged intake with the weight trend to estimate how much you actually burn. Consistent estimation errors cancel out, so consistency matters more than precision.
- **Each goal phase has a nutrition setting** (cut, bulk, lose fat while gaining muscle, maintain). It sets the calorie target relative to the estimated burn. The protein target is about 0.7–1 g per lb of body weight.
- **The first calorie target** comes from a standard formula using height, age, sex and weight, entered once in setup. After 2–3 weeks of data, the scale-based estimate takes over.
- **The coach uses nutrition as context during workouts.** If you've eaten little today, it holds the weights instead of pushing them up.

## Build order

Each step adds one new layer of the system:

1. **Body weight and active time.** App skeleton, Apple Health, engine trends, simple screens.
2. **Food logging and adaptive calorie targets.** The first use of Claude, with chat and voice input outside sessions.
3. **Cardio sessions.** The first live voice sessions; timers and interval cues prove out the voice loop.
4. **Lifting.** Progression, calibration, plate math and set evidence, built on a voice loop that already works.
5. **Flexibility and core.** Pose and exercise sequencing.

## Later

- Apple Watch: heart rate (rest based on recovery, cardio zones) and sleep/readiness from HealthKit.
- Meal suggestions: "I have 500 calories left and need 40 g of protein. What should I eat?"
- A more natural cloud text-to-speech voice.
- Pose sequencing for flexibility sessions: which pose next, both sides, counterposes.
