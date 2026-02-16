# Tree Growth Ideas: Infinite Growth System

## The Problem

The current tree uses unique words as branches (strata). Vocabulary plateaus after
~5,000-10,000 unique words, so the tree stops growing. We need a system where the
tree **always keeps growing taller and thicker** no matter how long the user talks.

**Key constraint**: Words fly from the nebula and land on the tree, so branches
need to be something words can visibly attach to.

**Current system**: `trunkLevels` is capped at 10, `baseRadius` at 0.70. Strata
map unique words to trunk levels. Once vocabulary saturates, no new structure appears.

---

## Idea 1: Time-Period Trunk Sections

Each trunk section represents a time period (e.g., every 500 words spoken).
Branches in each section show word frequency **during that period only**.
The tree always grows because new periods always arrive.

### How It Works

- Every N words (e.g., 500), a new trunk section is added on top
- Each section gets its own set of branches based on that period's vocabulary
- Repeated words make branches thicker in the current section
- Words from the nebula fly to the **topmost (current) section**
- Older sections remain static below, forming the tree's history

### Growth Stages

```
   1,000 WORDS                  10,000 WORDS                   50,000 WORDS
   (2 sections)                 (20 sections)                  (100 sections)

                                                                    /\
                                                                   /||\
                                                                  / || \
                                                                 /  ||  \
                                                               _/   ||   \_
                                                              |  Section  |
                                                              |    100    |
                                                              |  current  |
                                                                ...
                                                              |           |
                                                              | Section 80|
                                     /\                       |     :     |
                                    /||\                      |     :     |
                                   / || \                     |           |
                                 _/  ||  \_                 _/  Section 50 \_
          *                     |  Section  |              |        :        |
        * | *                   |    20     |              |        :        |
       *  |  *                  |  current  |              |                 |
      ~~~~|~~~~                 ~~~~|~~~~                  |   Section 20    |
     |  Sec 2  |               |   :    |                 |        :        |
     | current |               | Sec 10 |                __|       :        |__
     ~~~|~~~                   |   :    |               |     Section 10       |
     | Sec 1 |                _|  Sec 5 |_              |        :            |
     | done  |               |    :      |              |        :            |
     |_______|               |  Sec 2    |             _|    Section 5        |_
      \|||||/                |  Sec 1    |            |      Section 2          |
       |||||                 |___________|            |      Section 1          |
       |||||                  \|||||||||/             |________________________|
      /     \                  |||||||||               \||||||||||||||||||||||/
     / roots \                /         \               ||||||||||||||||||||
                             /   roots   \             /                    \
                                                      /       roots         \
```

### Detail: A Single Trunk Section

```
    Words from nebula fly here
            |   |   |
            v   v   v
          * * * * * * *        <-- leaves (frequency-based density)
         /  |   |   |  \
    ----/   |   |   |   \---- <-- branches (one per top word in this period)
   |  "the" |"hello"|  "code"|     thicker = more frequent in THIS period
   |        |       |        |
   +--------+-------+--------+  <-- trunk section boundary
   |     Section N-1 below    |
```

### Vocabulary Plateau Behavior

When vocabulary plateaus, each new 500-word section still appears because the
user is still talking. The branches in each section may look similar (same
common words), but the tree keeps growing taller. Over time, the lower trunk
thickens as the weight of upper sections accumulates.

```
  PLATEAU PHASE -- same words, still growing:

      Section 55:  "the" "and" "so" "like" "yeah"     <-- current, growing
      Section 54:  "the" "and" "so" "like" "yeah"     <-- recently completed
      Section 53:  "the" "and" "but" "like" "yeah"
         ...
      Section 1:   "hello" "um" "test" "okay"         <-- early vocabulary
```

The tree becomes a **timeline** -- you can see how speech patterns changed.

### Pros and Cons

```
  +---------------------------------------+----------------------------------------+
  | PROS                                  | CONS                                   |
  +---------------------------------------+----------------------------------------+
  | Always grows -- guaranteed             | Could look repetitive at top if vocab  |
  |                                       |   is truly static                      |
  | Natural "history" visible in the tree | Need to manage LOD for 100+ sections   |
  |                                       |                                        |
  | Words clearly land on current section | Very tall tree may need camera work    |
  |                                       |                                        |
  | Simple to implement -- just add       | Lower sections may be too small to     |
  |   sections on a timer/word-count      |   see at scale                         |
  +---------------------------------------+----------------------------------------+
```

---

## Idea 2: Ever-Thickening Rings

The trunk gets wider over time, like real tree rings. Each "ring period"
adds girth to the trunk. Branches on older sections grow thicker as words
from those branches are repeated. The tree is always getting fatter.

### How It Works

- The trunk has concentric rings (visible as wider radius over time)
- Every N words, a new ring is added, widening the trunk
- When a word flies from the nebula, it lands on its branch and makes it
  slightly thicker/longer
- New words still create new small branches at the canopy
- The overall trunk diameter is a function of total words spoken

### Growth Stages

```
   1,000 WORDS                  10,000 WORDS                   50,000 WORDS

        *  *                      *  *  *  *                  * * * * * * * *
       * \|/ *                   * \  |  / *                * * \  |  |  / * *
        --|--                     ---|---|---              * * ---|--|--|--- * *
         \|/                      \  | |  /              * *  \  |  |  |  /  * *
          |                        \ | | /                * ===|==|==|==|=== *
          |                         =====                  *  ||  |  |  ||  *
          |                         || ||                    ==||==|==|==||==
          |                         || ||                    ||  | |  | |  ||
          |                         || ||                    ||  | |  | |  ||
          |                         || ||                    |||||| || ||||||
         |||                        || ||                    |||||| || ||||||
         |||                       ||   ||                  ||||||  ||  ||||||
         |||                       ||   ||                  |||||| /  \ ||||||
        /   \                     /       \                /                  \
       / roots\                  /  roots   \             /      roots         \

     Trunk: thin              Trunk: medium             Trunk: massive
     Branches: wispy          Branches: substantial     Branches: enormous
     Ring count: 2            Ring count: 20            Ring count: 100
```

### Detail: Cross-Section of Trunk

```
   Early (1,000 words)         Mid (10,000 words)          Late (50,000 words)

         .---.                    .---------.              .-----------------.
        / . . \                  /  .------. \            /  .-------------. \
       |  |R1| |                |  / .----. \ |          |  / .-----------. \ |
       |  '---' |               | | / .--. \ ||          | | / .--------. \ ||
        \     /                 | | | |R1| | ||          | | | / .----. \ | ||
         '---'                  | | | '---' | ||         | | | | / .-. \ | | ||
                                | | \ '---' / ||         | | | | | |R1|| | | ||
                                | |  '-----'  ||         | | | | | '---'| | | ||
                                |  \  R10    /  |        | | | |  '----'  | | ||
                                 \  '-------'  /         | | |  '------'  | | ||
                                  '-----------'          | |  '----------'  | ||
                                                         |  '--- R50 ------'  |
                                                          '-------------------'

   Each ring = a time period. Trunk radius = sqrt(totalWords) * scale
```

### Vocabulary Plateau Behavior

Even with the same words repeated, the trunk keeps widening (more total words
= more rings). Existing branches grow thicker as their words are repeated.
The tree becomes a massive ancient oak rather than a tall pine.

```
  PLATEAU VISUALIZATION:

  Before plateau:                After 40,000 more words of the same vocabulary:

       thin branches                    MASSIVE branches
        \  |  /                      \\\\\  |||  /////
         \ | /                        \\\\\=|||=/////
          |||                          ||||||||||||
          |||                          ||||||||||||
          |||                          ||||||||||||
         /   \                        /            \

  Branches that were twigs            Same branches, now thick as logs
  are now thick because               because "the" has been said 8,000 times
  "the" has been said 2,000 times
```

### Pros and Cons

```
  +---------------------------------------+----------------------------------------+
  | PROS                                  | CONS                                   |
  +---------------------------------------+----------------------------------------+
  | Grows in width indefinitely           | Horizontal growth less dramatic than   |
  |                                       |   vertical -- harder to notice         |
  | Looks like a real ancient tree        |                                        |
  |                                       | Branch thickening could make words     |
  | Word attachment is clear -- words     |   hard to read on branches             |
  |   fatten their branch                 |                                        |
  |                                       | Tree shape stays similar -- just       |
  | Satisfying: watch your tree become    |   bigger. May feel stale.              |
  |   an ancient oak over months          |                                        |
  |                                       | Need to handle camera zoom as tree     |
  | No LOD issues -- one tree, just wider |   gets very wide                       |
  +---------------------------------------+----------------------------------------+
```

---

## Idea 3: Canopy Layers

The tree grows upward in distinct canopy layers. Each layer represents a
time period. Words land in the **current top layer**. Old layers become
dense and leafy below, forming the tree's thick foliage history.

### How It Works

- Tree starts with a single canopy layer at the top
- Every N words, the current layer "closes" and a new layer grows on top
- When a layer closes, its branches become dense with leaves (filled in)
- Words from the nebula always target the topmost (current, sparse) layer
- The trunk extends upward through each new layer
- Lower layers are lush and opaque; the current layer is open and growing

### Growth Stages

```
   1,000 WORDS                  10,000 WORDS                   50,000 WORDS

                                                              .  current  .
                                                             . * layer 50 * .
                                                            .  *  words   *  .
                                                           --------| |--------
                                                          .:.:.:.:.|.|.:.:.:.:. layer 49
                                .  current  .             .:.:.:.:.:.:.:.:.:.:.: layer 48
                               . * layer 10 * .           .:.:.:.:.:.:.:.:.:.:.: layer 47
       .  current  .          .  *  words   *  .          .:.:.:.:.:.:.:.:.:.:.:   ...
      . *  words  * .        --------| |--------          .:.:.:.:.:.:.:.:.:.:.:
     ------| |------         .:.:.:.:.|.|.:.:.:.:  9      .:.:.:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:. 1       .:.:.:.:.:.:.:.:.:.:  8      .:.:.:.:.:.:.:.:.:.:.:
     ------| |------         .:.:.:.:.:.:.:.:.:.:  7      .:.:.:.:.:.:.:.:.:.:.:
           | |               .:.:.:.:.:.:.:.:.:.:    ..   .:.:.:.:.:.:.:.:.:.:.:
           | |               .:.:.:.:.:.:.:.:.:.:  3      .:.:.:.:.:.:.:.:.:.:.:
           | |               .:.:.:.:.:.:.:.:.:.:  2      .:.:.:.:.:.:.:.:.:.:.:
           |||               .:.:.:.:.:.:.:.:.:.:  1      .:.:.:.:.:.:.:.:.:.:.:
          |||||              ----------| |--------         -------- | | ---------
          |||||                       | |                          | |
         /     \                     /   \                        /   \
        / roots \                   / roots\                     / roots\

     1 dense layer +             9 dense layers +           49 dense layers +
     1 growing layer             1 growing layer             1 growing layer
```

### Detail: A Canopy Layer (Top View)

```
   CURRENT LAYER (open, sparse -- words landing here):

                  *           * = word sprites arriving from nebula
              *       *
          *               *
      -----.   .-----.   .-----
     |  "go" |  "the"  | "run" |    <-- branches with word labels
      -------'-------'---------
              |     |
              | trunk|
              |     |

   CLOSED LAYER (dense, leafy -- no longer receiving words):

      .:.:.:.:.:.:.:.:.:.:.:.:.:
      :.:.:.:.:.:.:.:.:.:.:.:.:.:   <-- dense leaf particles fill the space
      .:.:.:.:.:.:.:.:.:.:.:.:.:     words are hidden under foliage
      :.:.:.:.:.:.:.:.:.:.:.:.:.:
      ----------|   |-----------
```

### Vocabulary Plateau Behavior

Plateau does not matter. Each time period produces a new canopy layer regardless
of whether new unique words appear. The current layer always has space for words
to land. Repeated words create thicker branches in the current layer. When the
layer closes, it all becomes a dense green mass.

```
  OVER TIME (with vocabulary plateau):

  The tree resembles a towering redwood or sequoia -- a massive column of
  dense foliage with an active, sparse crown on top where new words land.

      .  * active *  .       <-- always sparse, always receiving words
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:      <-- all these layers look the same (plateau)
     .:.:.:.:.:.:.:.:.:          but the tree is MASSIVE and keeps growing
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:
     .:.:.:.:.:.:.:.:.:
     ---------||---------
              ||
              ||
             /  \
```

### Pros and Cons

```
  +---------------------------------------+----------------------------------------+
  | PROS                                  | CONS                                   |
  +---------------------------------------+----------------------------------------+
  | Very clear where words land (top)     | Lower layers become homogeneous green  |
  |                                       |   blobs -- history is hidden           |
  | Tree always grows taller              |                                        |
  |                                       | Looks more like a column than a tree   |
  | Dense lower layers look lush and      |   at extreme scale                     |
  |   beautiful                           |                                        |
  |                                       | Less information visible at a glance   |
  | Simple mental model for users         |   compared to Idea 1                   |
  |                                       |                                        |
  | Good LOD: render lower layers as      | Closing layers = visual "pop" that     |
  |   simple billboards at distance       |   could feel jarring                   |
  +---------------------------------------+----------------------------------------+
```

---

## Idea 4: Spiral Growth

Branches spiral up the trunk like a helix. New words create new branch points
along the spiral. Repeated words make existing branches grow longer and thicker.
The spiral means there is always room to grow upward even with the same words.

### How It Works

- Branches are placed along a helical path up the trunk
- Each word has a "home position" on the spiral (based on hash of the word)
- When a word flies from the nebula, it targets its home branch
- First occurrence: creates a small new branch at the next available spiral slot
- Repeated occurrences: branch grows longer and sprouts sub-branches
- The spiral pitch (spacing) increases as the tree grows, so new branch points
  keep appearing between existing ones
- Trunk height = function of total branch points

### Growth Stages

```
   1,000 WORDS                  10,000 WORDS                   50,000 WORDS

                                                                   /
                                                                --'
                                                               |
                                                                `--.
                                                                    \
                                                               .--'
                                                              /
                                       /                    -'
                                     -'                    |
                                    |                       `-.
                                     `-.                       \
          /                             \                  .--'
        -'                           .-'                  /
       |                            /                   -'
        `-.                       -'                   |
           \                     |                      `-.
        .-'                       `-.                      \
       /                             \                  .-'
     -'                           .-'                  /
    |                            /                   -'
     `-.                       -'                   |
        \                     |                      `-.
     .-'                       `-.                      \
    /                             \                  .-'
   |                            .-'                 /
    |                          /                  -'
    |                         |                  |
    |                         ||                |||
    |                         ||                |||
   /|\                       /  \              / | \
  / | \                     / roots\          / roots\
```

### Detail: The Spiral Mechanism

```
   TOP-DOWN VIEW showing spiral branch placement:

                    12 o'clock
                        |
                   7    |    1
                  .  .  |  .  .
              8 .    .  |  .    . 2       Numbers = order branches were added
             .       .  |  .       .      as the spiral goes around
         9  .        .     .        . 3
             .       .  |  .       .
              .    .    |    .    .
                  .  .  |  .  .
                  10    |    4
                        |
                   11   |   5
                        6

   SIDE VIEW showing spiral going up:

         13--               <-- newest (current growth point)
        /    12--
       11--/    \
      /    10--  \
     9--  /    \  |
    /   8--     \ |
   7-- /    \    \|
      6--    \   ||
     /   5--  \  ||
    4-- /    \ | ||
       3--    \| ||         <-- each "--" is a branch, longer = more frequent
      /   2--  | ||
     1-- /     | ||
        |      | ||
        |      | ||
        '------+-++--->    trunk
```

### Vocabulary Plateau Behavior

This is where spiral growth really shines. When vocabulary plateaus, repeated
words keep making existing branches grow longer and bushier. But the spiral
also naturally extends upward because:

1. Each repetition of a word can "promote" it to a higher spiral position
2. The spiral pitch increases logarithmically, so there is always room for
   new positions even with the same word set
3. Sub-branches grow on existing branches, adding vertical extent

```
  WORD "the" OVER TIME:

   Occurrence 1:       Occurrence 100:      Occurrence 1000:

      -.                  --===.                --==========.
       (twig)                |- -.                  |-- --===.
                             |    (sub-branches)    |   |- -.
                                                    |   |    \
                                                    |   (massive
                                                    |    sub-tree)
```

### Pros and Cons

```
  +---------------------------------------+----------------------------------------+
  | PROS                                  | CONS                                   |
  +---------------------------------------+----------------------------------------+
  | Visually unique and beautiful         | More complex to implement -- spiral    |
  |                                       |   math, collision avoidance            |
  | Each word has a "home" -- satisfying  |                                        |
  |   to watch words find their branch    | Hard to read individual branches       |
  |                                       |   when dense                           |
  | Plateau = branches get bushier, not   |                                        |
  |   just thicker. Still looks alive.    | Spiral may look chaotic at large       |
  |                                       |   scale without careful LOD            |
  | Infinite growth in both height and    |                                        |
  |   branch mass                         | Word landing animation more complex -- |
  |                                       |   need to find the right spiral slot   |
  | Beautiful organic shape               |                                        |
  +---------------------------------------+----------------------------------------+
```

---

## Idea 5: Seasonal Shedding + Regrowth

The tree periodically "sheds" old word-branches, absorbing them into the trunk
(making it thicker and adding a visible ring). Then new branches grow for the
current period's words. The tree cycles between full and bare, but always gets
bigger after each cycle.

### How It Works

- Tree grows branches for current words (like now)
- After N words, a "season change" triggers:
  1. Leaves fall off (particle animation)
  2. Branches shrink and merge into the trunk
  3. Trunk diameter increases (absorbed branch mass)
  4. A visible ring/scar appears where branches were
  5. New, small branches begin growing for the next period
- Words from the nebula always target current branches
- After shedding, old words' branches are gone -- but the trunk remembers
  them as added girth

### Growth Stages

```
   1,000 WORDS                  10,000 WORDS                   50,000 WORDS
   (2nd growth cycle)           (10th growth cycle)            (50th growth cycle)

       SUMMER PHASE              SUMMER PHASE                  SUMMER PHASE
       (branches out)            (branches out)                (branches out)

          * * *                   *  * * *  *                * * * * * * * * * *
         * | | *                *  \ | | /  *              * *  \\ | | | //  * *
        *  | |  *              * ---|===|--- *            * * ---|=======|--- * *
         --|=|--                ---|=====|---              * =|=========|= *
           |=|                   |=======|                  |=============|
           |=|                   |=======|                  |=============|
           |=|                   |===.===|  <-- ring        |=====...=====| ring
           | |                   |=======|    (shed 5)      |=============|  x30
           | |                   |===.===|  <-- ring        |=====...=====|
           | |                   |=======|    (shed 1)      |=============|
          /   \                  |=======|                  |=============|
         / roots\               /         \                /               \
                                /  roots   \              /     roots       \
```

```
   SHEDDING ANIMATION (4 frames):

   Frame 1: Full           Frame 2: Leaves fall    Frame 3: Bare         Frame 4: Regrowth
   (end of cycle)          (transition)            (trunk absorbs)       (new cycle begins)

      * * * * *              .  . .  .                                        .   .
     * \|/ \|/ *            . \|/.\|/.              ---|---|---              . | . | .
      --|---|--              --|---|--               |=========|            .--|---|--.
      |=======|              |=======|              |=========|             |=======|
      |=======|              |=======|              |=========|             |=======|
      |=======|              |=======|              |====.====|  new ring   |===.===|
      |=======|              |=======|              |=========|             |=======|
     /         \            /         \            /           \           /         \

                              * . *                    girth
                             * . . *                   increased
                              . . .
                            (falling leaves
                             particle effect)
```

### Detail: Trunk Ring Scars

```
   CROSS-SECTION showing ring scars from each shedding:

   After 5 cycles:                    After 50 cycles:

        .---.---.                        .----.----.----.----.
       / .---.--.\                      / .----.----.----.--. \
      | / .---. \ |                    | / .----.----.----. \ |
      | | / . \ | |                    | | /  ...many...  \ | |
      | | | R1| | |                    | | |     rings     | | |
      | | \ . / | |                    | | \   ...many... / | |
      | \ .---. / |                    | \ .----.----.---. / |
       \ .---.--./                      \ .----.----.----. /
        .---.---.                        .----.----.----.----.

   Each ring represents one full growth+shed cycle.
   Visible as subtle color bands on the trunk surface.
```

### Vocabulary Plateau Behavior

Plateau is irrelevant because the cycle is time/word-count driven, not
vocabulary driven. Same words just mean the same branches regrow each cycle,
but the trunk keeps getting wider. The shedding animation gives a sense of
"seasons passing" even when content is repetitive.

```
  VISUAL TIMELINE:

  Cycle 1:   sprout branches --> grow --> shed --> trunk ring 1
  Cycle 2:   sprout branches --> grow --> shed --> trunk ring 2  (wider)
  Cycle 3:   sprout branches --> grow --> shed --> trunk ring 3  (wider)
     ...
  Cycle 50:  sprout branches --> grow --> shed --> trunk ring 50 (massive)

  Even with identical vocabulary every cycle, the trunk is noticeably wider
  and the rings tell the story of longevity.
```

### Pros and Cons

```
  +---------------------------------------+----------------------------------------+
  | PROS                                  | CONS                                   |
  +---------------------------------------+----------------------------------------+
  | Dramatic visual events (shedding)     | Tree periodically looks bare -- user   |
  |   keep things interesting             |   might feel like they "lost" progress |
  |                                       |                                        |
  | Clean: never gets cluttered because   | Shedding animation needs to feel       |
  |   old branches are absorbed           |   rewarding, not punishing             |
  |                                       |                                        |
  | Trunk rings are a beautiful record    | Branches are temporary -- words don't  |
  |   of history                          |   have a permanent "home"              |
  |                                       |                                        |
  | Solves plateau completely             | Implementation is complex: need        |
  |                                       |   shedding animation, ring texture,    |
  | Leaf-falling particle effect can be   |   branch absorption math               |
  |   gorgeous                            |                                        |
  |                                       | Less "cumulative" feeling -- progress  |
  | Cycles give natural pacing            |   is in trunk width, not branch count  |
  +---------------------------------------+----------------------------------------+
```

---

## Comparison Matrix

```
  +---------------------+----------+----------+---------+----------+----------+
  |                     | Idea 1   | Idea 2   | Idea 3  | Idea 4   | Idea 5   |
  |                     | Time     | Rings    | Canopy  | Spiral   | Seasonal |
  |                     | Sections |          | Layers  |          | Shedding |
  +---------------------+----------+----------+---------+----------+----------+
  | Always grows taller |   YES    |    no    |  YES    |  YES     |    no    |
  | Always grows wider  |   some   |   YES    |  some   |  some    |   YES    |
  | Visual drama        |   low    |   low    |  med    |  med     |  HIGH    |
  | Word attachment      |  clear   |  clear   | clear   | complex  |  clear   |
  |   clarity           |          |          |         |          |          |
  | Impl. complexity    |   LOW    |   med    |  med    |  HIGH    |   HIGH   |
  | Info density        |  HIGH    |   med    |  low    |  HIGH    |   med    |
  | Plateau resilience  |  strong  |  strong  | strong  | strong   |  strong  |
  | Looks like a tree   |   yes    |   YES    |  kinda  |  unique  |   YES    |
  | Performance at      |   med    |   good   |  good   |  poor    |   good   |
  |   scale (50k words) |          |          |         |          |          |
  +---------------------+----------+----------+---------+----------+----------+
```

---

## Recommended Hybrid: Time Sections + Thickening

Combine **Idea 1** (time-period trunk sections for guaranteed vertical growth)
with **Idea 2** (trunk thickening for horizontal growth). This gives:

```
  HYBRID: The tree grows UP and OUT simultaneously

         Early                        Mid                          Late

                                                                * * * *
                                                               *  \|/  *
                                                              * --|===|-- *
                                                                |=======|
                                                                |=======|
                                       * * *                    |=======|
                                      * \|/ *                   |=======|
           * *                       * --|=|-- *                |=========|
          * | *                        |===|                    |=========|
          --|--                        |===|                    |=========|
           |||                         |===|                    |=========|
           |||                        |=====|                  |===========|
           |||                        |=====|                  |===========|
          /   \                      /       \                /             \
         / roots\                   /  roots  \              /    roots      \


  Height driven by: section count (total words / period size)
  Width driven by:  ring count (total words, logarithmic scale)
  Branches driven by: word frequency within each section's time period

  Words from nebula --> always fly to the TOP section (current period)
  Repeated words --> thicken existing branches in current section
  New periods --> new section on top, trunk gets slightly wider too
```

This hybrid is **Idea 1** for the tree's overall growth engine, with **Idea 2's**
thickening applied to the trunk so the tree looks more substantial and ancient
over time rather than just being a tall thin pole.

### Implementation Sketch (relative to current code)

```
  Current:  trunkLevels = f(uniqueWords)      capped at 10
  Hybrid:   trunkLevels = totalWords / 500    unbounded

  Current:  baseRadius = f(uniqueWords)        capped at 0.70
  Hybrid:   baseRadius = log(totalWords) * k   always growing

  Current:  strata[lvl].totalFreq              all-time frequency
  Hybrid:   strata[lvl].totalFreq              frequency in THAT period only

  Current:  generateTree() rebuilds everything
  Hybrid:   addSection() appends one section on top (incremental)
```

The key change in `tree.js` would be:
- `trunkLevels` becomes `sections.length` (unbounded)
- Each section stores its own word frequency data for that time window
- `baseRadius` grows with `Math.log(totalWords) * scaleFactor`
- Old sections are frozen; only the top section receives new words
- Camera auto-adjusts to frame the growing tree
