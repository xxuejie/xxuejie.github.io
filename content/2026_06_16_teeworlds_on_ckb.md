+++
title = "Teeworlds on CKB"
date = "2026-06-16"
+++

For unexpected reasons, I recently had some free time to tinker. I started to work on a thesis I had for years: we have powerful VMs in blockchains, but they are constrained to simple logic moving funds around, what if we dig deeper to unleash the potential?

After some trial and error, I've ported [Teeworlds](https://www.teeworlds.com/), an open source multiplayer shooter game to CKB. By porting Teeworlds to CKB, I mean that the core 50Hz game tick logic of Teeworlds runs / validates fully on CKB-VM. Graphics, sound and networking still remain off-chain; the core game logic now also runs on chain, including all the movement, collision, weapons and fighting logic.

You can see a video here to get a taste of it: <https://www.youtube.com/watch?v=ChPVvTt2u9Y>

Or you can try the open source code, set up and run a game yourself following [those steps](https://github.com/xxuejie/teeworlds/blob/f77e39e5fa5bfa0b4831d8d6d7c4690183807a29/ckb/README.md).

There is no shortage of attempts to build games on blockchain. But to the best of my knowledge, you have to make a choice:

* Build a turn-based, macro-strategy game. I admire Dark Forest a lot, it pioneered what I do here. However, its architecture dictates a game of asynchronous planning by design. There are also other types of games I want to explore.
* Run the core game logic off-chain, only have the items moved on chain. Big Time / Off The Grid falls into this category.

In 2026, I believe we now have fast enough blockchain VMs that enable lower-level, deeper optimizations. Complicated, **real-time** game logic can now be implemented on chain. To showcase this, I started porting a small set of open source games to blockchain VMs (a brand new title is indeed tempting, but game design is not my strength, porting open source games gives me a chance to learn the territory first). Teeworlds is my first milestone: a 50Hz, real-time multiplayer shooter game, where each individual game session can be wrapped and validated in a single CKB transaction.

# Design: chunks that never bisect

Before diving into details, let's talk about one design principle that drives everything that follows:

On-chain games I'm working on are designed around `chunks`. A `chunk` of gameplay must be validated in a single blockchain transaction. There are no bisection games, no multi-round interactive proving, one transaction decides it or fails.

A `chunk` means a unit of gameplay, what counts varies by genre:

* Teeworlds: one game session.
* [MOBA](https://en.wikipedia.org/wiki/Multiplayer_online_battle_arena)s or [fighting games](https://en.wikipedia.org/wiki/Fighting_game): likely also one game session.
* [MMORPG](https://en.wikipedia.org/wiki/Massively_multiplayer_online_role-playing_game)s: they have no natural boundary, so one chunk might be one minute of wall-clock gameplay.

In 2026, I believe blockchain VMs are fast enough to have complex game logic implemented efficiently. By building around **chunks**, performant VMs help avoid bisection validation games, greatly simplifying blockchain infrastructure. In many cases people are fighting rough edges of blockchains, instead of designing games properly. With simplified blockchain architecture, hopefully we can see better games.

For economic reasons, there might still be an optimistic-based workflow in those **chunk**-based games, but what's great here is: validation will always be completed in one transaction. Gaming on chain is hard enough, let's not complicate it with bisecting games.

# Implementation: how do we port games on-chain?

Tweaking Teeworlds to be an on-chain game works as follows:

1. Locate the core [game loop](https://m-abdullah-ramees0916.medium.com/the-game-loop-f6f5cb68c00) of Teeworlds, modify the game loop, so for each **chunk**, a **game tape** is dumped, containing all player inputs at each game loop iteration (in many cases this is also called a tick).
2. Replicate the game loop in a different main function, stripping all the networking, graphics and sound related code. Focus on the game loop, so given a game tape, it should run the same gameplay on native host environment, resulting in the same final states. In my context, I call such a standalone program a **replayer**.
3. Given the working replayer on native environment, port the same replayer over to CKB-VM, or your performant VM of choice.
4. More likely than not, the replayer might not be optimized at this point, so profiling and optimizing work is required to make the replayer efficient in on-chain environment.
5. Finally, build the scaffolding code to submit gameplays to blockchains (optionally, you can also replay gameplays on blockchains, I added this for Teeworlds), to complete the whole workflow.

When porting Teeworlds, [this commit](https://github.com/xxuejie/teeworlds/commit/0d337b82c2af44aa580c57c07effa8edc9c82736) maps to step 1 and 2, [this commit](https://github.com/xxuejie/teeworlds/commit/ad28045c97a88596022fd1f9c49ca61290761b26) maps to step 3, [this](https://github.com/xxuejie/teeworlds/commit/dfad4682dc55f4224a0689b1301a01636962fa28) maps to step 4, and finally step 5 is [here](https://github.com/xxuejie/teeworlds/commit/050c8593eb605991c7bbe0301466fdbeb1950102).

There are some notes worth mentioning, most of which have to do with step 2:

* Technically, a replayer running on native host environment is not needed in final production setup. But I find it a good practice to start with a native replayer first, since it eases debugging of the replayer. Frequently the tape recording & replaying can be a source of bugs, and I do recommend getting a working native replayer first, before moving to blockchain VMs.
* You might have already realized this: making a game fully reproducible to build a **replayer**, can be a challenging task. Modern games use a lot of data sources to drive replay: timestamps, RNGs, player inputs, etc. all of those must be made deterministic. A game tape should thus record initial seed for RNGs, record timestamp for each game tick, record player inputs, and all other information that would affect game states. This is actually a quite troublesome task, I've been actually thinking about building [Deterministic Simulation Testing](https://antithesis.com/docs/resources/deterministic_simulation_testing/) solutions to simplify it.
* In addition to game states after running the game tape, some games also require game states before running the game tape. Teeworlds does not need this, but MMORPGs or some complicated MOBAs might require it. The game does not start from an empty state, an initial state is required. Only when running the game tape starting from the initial state, will we arrive at the same final state. So for some games, game loop must dump both the before and after state of the game.

Maybe when fully on-chain games become more popular, we can have **replayer**-aware game engines to simplify porting. For now these steps are just a guideline, actual tricks might vary from one game to another.

# Challenges

Of course there are challenges: we must make sure the game fits in an on-chain binary, both the computation costs (cycles) and memory usage must be within limit. In fact, the first version I got working cost over 1 billion cycles for 1-minute gameplay, this is way more expensive than we can afford.

A fast VM alone isn't enough to build real-time games on chain, we need rigorous optimizations in the on-chain programs as well:

## Musl, libcxx

CKB-VM used to settle on a poorly structured, half-baked [libc](https://github.com/nervosnetwork/ckb-c-stdlib/tree/master/libc) with just enough, easily implemented functions. I consider this to be one of the many mistakes I made designing CKB-VM's ecosystem. CKB-VM might be much better served if I had spent more effort porting over a proper libc and had it available since the early days.

For simpler crypto algorithm implementations, our poor libc might work, but for porting games, we need a complete libc, some games might use the C++ Standard Library (STL) as well. We will need more complete solutions.

While working on other projects, I have ported [musl libc](https://musl.libc.org/) and [libcxx](https://libcxx.llvm.org/) over, as a complete solution for C/C++ standard libraries on CKB. They also come with tricks for optimizations, please refer to [this post](https://blog.cryptape.com/optimizing-c-code-for-ckb-vm) for more details.

It's worth noting that Teeworlds, like games of its time, has limited use of STL to a few places:

* The [algorithms library](https://cppreference.com/cpp/algorithm)
* `new` / `delete` to allocate / deallocate memory

It skips `std::vector`, `std::map` and many other components in the STL. We could use a just-enough C++ library but I've learned my mistake, having a fully-working libcxx is much, much better. Not to mention there are also other games worth porting, some might use more C++ features. [Hypersomnia](https://github.com/TeamHypersomnia/Hypersomnia) is another game that can be fun to port over, but uses more C++ features.

## Fixed math

The first bottleneck we would locate, is that softfloat routines, e.g., `__addsf3`, `__mulsf3`, etc., take a lot of CKB cycles. Teeworlds by default uses a lot of float values. This has 2 problems:

* The first one of course is performance, floating point operations are designed for hardware to run, not for software to emulate. Just to give you a sense of what it takes, [here](https://gist.github.com/xxuejie/eb58dfd0f469ef2b16f57f1fa1b6519c) is the full dump of `__addsf3`, used to add 2 float values together. We are using a lot of operations just to basically add 2 floats together.
* Floating-point operations are frequently the source of indeterminism. As far as I know [this post](https://gafferongames.com/post/floating_point_determinism/) summarizes the issue best, quoting: `"It is possible to get deterministic results for floating calculations across multiple computers provided you use an executable built with the same compiler, run on machines with the same architecture, and perform some platform-specific tricks."` But that's too much for us to rely on.

To solve both issues, I'm replacing all float values in Teeworlds with [fpm](https://github.com/MikeLankamp/fpm), a decent fixed-point math library. Specifically, we use `fpm::fixed<std::int64_t, __int128_t, 16>`, meaning each float in Teeworlds is replaced by a 64-bit integer, where the upper 48 bits represent the integer part, while the lower 16 bits represent the fractional part. This way, math operations map to neat integer operations separated by byte boundaries. A whole lot of computation cycles are thus saved.

## Alpha max plus beta min approximation

More profiling reveals that the square root operation required in [Euclidean distance](https://en.wikipedia.org/wiki/Euclidean_distance), surprisingly, is one major source of slowdown. Even after we switched to fixed point math, [sqrt](https://github.com/MikeLankamp/fpm/blob/b46537fe9697e1a598ac8a26f8ae43d8b286ac3f/include/fpm/math.hpp#L461) operation still takes a lot of cycles.

Some of you might have heard about the famous [fast inverse square root](https://en.wikipedia.org/wiki/Fast_inverse_square_root) used by John Carmack in Quake III. It's funny that a legend ran into the same problem! Unfortunately, the trick is only applied to floating point numbers. After switching to fixed point numbers, we don't have the same trick available. It's also worth noting later this operation also becomes a [hardware instruction](https://www.felixcloutier.com/x86/rsqrtss) (and it has been proven to be faster than Carmack's trick), but under the `rv64imc_zba_zbb_zbc_zbs` ISA, we don't have a similar instruction available.

There is a solution if we look beyond square root. In Teeworlds, the square root operation is almost exclusively used to calculate Euclidean distance. And a high-speed approximation named [alpha max plus beta min algorithm](https://en.wikipedia.org/wiki/Alpha_max_plus_beta_min_algorithm) exists for Euclidean distance. This technique was actually used a lot in the 1990s games, where the sqrt operation was really expensive. It is also [well used](https://academic.oup.com/mnras/article/471/3/3323/3922864) in modern graphics shader development.

I have to mention that the fixed math replacement and the alpha-beta approximation likely changes original game's feel a bit. Previously Teeworlds used floating point values and real sqrt operations, in the new version we settled on fixed point values and Euclidean distance approximation. As a real amateur Teeworlds player, I hardly notice the gameplay difference after the changes, but if you are a Teeworlds veteran who disagrees, I'd love to work with you to see how we can still retain the exact same game feel, while still using fixed point math with approximated Euclidean distances.

## Other tricks

Other tricks came out of profiling real running code.

* I switched to a new [collision detection algorithm](https://github.com/xxuejie/teeworlds/commit/dfad4682dc55f4224a0689b1301a01636962fa28#diff-a0e5d95915df938ffb0e9b9b879a2e56b1459be64eda405ac51aad4b5763d9d5R133-R151). I have to give the credit to Gemini for helping me find a simple yet faster collision detection implementation.
* Some loops iterate over more players than supported, surprisingly, this also takes noticeable cycles. By restricting to fewer players, we should have less cycle consumption.

After applying all optimizations, a 2-player, 1-minute Teeworlds game takes ~150 million CKB cycles, or ~80 million RISC-V instructions to run. Teeworlds runs at 50Hz, meaning 1-minute gameplay has about 3000 game loop ticks to process, on average we now spend ~26000 RISC-V instructions for each game loop tick. There might still be room to optimize, but I'm happy with the result now.

## Optimizations can matter a lot

Before I added any optimization, I benchmarked a 2-player, 1-minute Teeworlds game using the default map. It takes over one billion CKB cycles to validate the game on chain. With above optimizations applied, a game using the same setup takes ~150 million CKB cycles to run, or ~80 million RISC-V instructions. The lesson I learned is: it's imperative for us to have performant blockchain VMs, but having optimized programs running inside VMs is equally important. New use cases on blockchains can only be unlocked, when both layers are optimized jointly.

# We are back in the 1990s again

The optimizations applied above reminds me a lot of optimizations on older machines in the 1990s. Strip libc for more space, replace floats with fixed-point math, approximate distances instead of precise computation. These aren't blockchain tricks — they're the tricks console and PC game programmers used in the 1990s to squeeze playable games out of severely constrained hardware. They echo the tricks people did on [Nintendo machines](https://fabiensanglard.net/snes_ppus_why/), or how John Carmack invented smooth side-scrolling on early PCs, which led to the [Commander Keen](https://en.wikipedia.org/wiki/Commander_Keen) series.

There is a joke that computer science is not about inventing new things, but about re-discovering techniques and tricks already invented years ago. Maybe we are doing similar things again. We drew inspiration from the 1990s on how to run decent games in resource limited environment, but then push for new ways to play games enabled by blockchains. I will expand more on this topic in the next section. For now, I want to dive into an interesting example.

## Neo Geo

Many of us grew up playing [The King of Fighters](https://en.wikipedia.org/wiki/The_King_of_Fighters) series (or KOF for short), having a lot of memories in arcades. KOF games are originally designed for [Neo Geo](https://en.wikipedia.org/wiki/Neo_Geo) system, which at its core runs on a 12MHz Motorola 68000, and a 4Mhz Zilog Z80 CPU. To dive more into Neo Geo system, here's [an amazing introduction](https://www.copetti.org/writings/consoles/neogeo/).

With a modern performant VM, and careful optimization, I'm willing to bet we can build a Neo Geo emulator running on chain, bypassing all the graphics and sound processing parts. The core CPUs used by Neo Geo could be emulated efficiently.

What's more interesting: Neo Geo's memory architecture maps surprisingly well onto CKB cells. Neo Geo carries a 2MB P ROM for program data, which many games — including the KOF series — split into two halves:

* The first 1MB is `P1 static memory`, it stores code that's always resident.
* The second 1MB is `P2 banked memory`, it serves as a window into a much larger `P2 ROM`. KOF 97's full `P2 ROM` is 4MB. At runtime, P1 code dynamically swaps slices of that 4MB into the banked window, based on selected fighters and loaded stages.

This maps properly to the dep-cell path in CKB: we load `P1 ROM` into VM memory once. The `P2 ROM` can be split into multiple dep cells, 512KB each. 2 CKB syscalls can load 1MB of `P2 ROM` into `P2 banked memory` precisely. The architecture Neo Geo developers used to squeeze more content into a constrained system is the same architecture CKB-VM gives you at minimal cost.

In fact there are many gaming systems from the 80s to the 90s using banked memory. All those emulators will likely run on CKB-VM. I do want to point out to properly build a product, we need to think about and sort out the legal implications, but the point I want to make is: modern blockchain VMs should already be powerful enough for many gaming systems we used to love and enjoy.

# On-chain pushes different games

I'm sure others are better than me at this, but I think different games can emerge from being on-chain:

* Decoupling art from logic is natural when building a `replayer`. What if a 2D game later gets a 3D view? Dwarf Fortress already has an experimental 3D visualizer alongside its default 2D view.
* Modding is a real thing. On-chain games become things you play in, live in, modify, and cherish.

Those ideas existed long before blockchains. Blockchains merely amplify them.

# State channels, ephemeral rollups

I'm sure you know me as a die-hard VM enthusiast. I love to think about, tweak and talk all things about virtual machines, and I'm less interested in blockchain research. So in this whole post about on-chain games I'm talking about virtual machine advancements and making things quick. But there is a whole chapter about trustless setup, avoiding cheaters in fully on-chain games. I have ignored this topic so far, simply because it isn't my expertise.

Luckily, people have extensively studied this area, so I don't have to do much of the research on my own. There are [state channel](https://www.ubishops.ca/wp-content/uploads/hu20250912.pdf) based solutions, or [ephemeral rollups](https://arxiv.org/pdf/2311.02650) we can leverage to build trusts among players and servers. My contribution to the topic, is just faster VMs and programs to make complicated game logic possible on chain.

## Optimistic, but not like some optimistic systems

There is one thing I want to point out: validating a game session requires a big chunk of input data, and a lot of computation cycles. From an economic point of view, large deployments of on-chain games likely won't validate every game session. There is a spectrum of security and trust tradeoffs:

* Submit the whole input data, and validate every game session on chain.
* Submit the full game tape, but only submit the final game state hash on chain.
* Submit only a hash of game tape, and a hash of the final game state on chain.

The cost decreases, security also decreases. The latter 2 solutions both require an optimistic design: servers submit the hash, posting a bond with a deadline. Within the deadline, it is expected players will check the hash, and challenge if the hash is invalid. What's different in current design, is that challenge phase is merely the execution of one transaction with all the input data (there is a caveat, I will explain in later posts), bisecting is completely removed, when VMs can deliver good enough performance.

# Beyond CKB

This setup does not stop with CKB, either. I created CKB-VM and spent almost seven years crafting programs on CKB-VM, I have the most velocity building on CKB-VM. That said, CKB is hardly the only choice now. The performance of CKB-VM is closely tied to design principles for CKB the L1 blockchain. In different environments, more performant VMs are introduced to make blockchains with different design considerations much faster. CKB's mainnet is clocked to run at roughly 350MHz - 437MHz (depending on different metrics you use), with a fixed 4MB memory space. Modern optimizing RISC-V VMs reach ~2GHz, with a bigger memory space, unlocking even more complex programs.

There's no right or wrong here, only design preferences.

And it's even possible to look beyond RISC-V. The gaming architecture only needs a performant VM, allowing lower-level optimizations. Other VMs might also be capable of running the games.

But there are definitely some requirements involved to build real-time on-chain games that go beyond VM discussions. I'll cover those in the next post.
