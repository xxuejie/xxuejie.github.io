+++
title = "Impulse: JoltPhysics on OpenVM"
date = "2026-11-01"
+++

Following my last post, I've built [impulse](https://github.com/xxuejie/impulse), which ports off-the-shelf [JoltPhysics](https://github.com/jrouwe/JoltPhysics) to OpenVM. Now we can have AAA grade game physics and collision detection library running right in a VM.

The [README](https://github.com/xxuejie/impulse/blob/master/README.md) file has detailed introduction and usage. I won't go into everything here. This time I want to talk about something else.

# GLM To The Rescue

I wanted to start porting JoltPhysics in August when I was done playing ray tracer on OpenVM, but kept running into other errands. Then one day this struck me: what if I taught the LLM to do it? We all know that modern LLMs are good enough for many tasks, can they help with tweaking toolchains here?

I then threw all my existing repos on [Teeworlds](/2026_06_16_teeworlds_on_ckb/), [One Hour One Life](/2026_06_29_porting_one_hour_one_life_game_loop_to_ckb/) and the [ray tracer](/2026_07_29_real_float_using_openvm_custom_extensions/) to GLM 5.3, asking it to study the patterns, then start porting. There were indeed a few times it went into dead ends or weird directions, and I had to steer the ship back, but after some time, it was able to reach a decent state, and we have the impulse repository now. Having LLMs digging saves so much time: I can just have it running on a dig and it helps me test libcxx from every LLVM version, cherry-picking the patch we have, making sure our port works on them.

There are many LLMs out there, each with people who like it or hate it. I personally like GLM 5.3, and keep a subscription to it, cuz to me GLM feels like a junior engineer. It keeps digging and digging, typically it can fix lower level quirks for me. I also used it a lot when I was tweaking One Hour One Life. It's really lifesaving that I don't have to deal with a 10-year-old codebase, learning all the tech debt, abandoned code branches or weird bugs. I can just focus on the important architecture, and have the LLM digging into the details. For this, I have yet to find anything better than GLM.

I'm sure there are others who think LLMs reason better and can derive better designs, but I'm just a stubborn old one in this industry, with my own likes and preferences. I'd prefer LLMs can build software in a structure that I feel comfortable in :P To me it's really those intricacies telling projects done entirely by LLMs apart: I'm more comfortable when I set the tone, and LLM completes the execution. We humans debate software structures all the time, I doubt if LLMs, even as they continue to improve, can converge on one pattern for software.

# Integrating A Real Game Engine

Modern AAA games are complicated beasts, typically made by hundreds, if not more, brilliant designers and engineers. A physics library is merely one component in it. It's like asking for a formula one car where you only have a gearbox. I don't have the bandwidth or power to invent everything on my own. The only solution is to rely on existing work, embracing the game development community ecosystem.

The most natural first choice is [Godot game engine](https://godotengine.org/). As the most famous open source game engine, Godot embraces JoltPhysics as the default physics engine starting from [version 4.6](https://godotengine.org/releases/4.6/). This might end up being the lowest friction solution: I can build a plugin in Godot, which can then record gameplay as a script, and later be able to prove it in ZK engines. There might be some indeterminism fixes needed in Godot, but since the full source is available, it might still be a seamless approach.

There is one caveat: Godot is a niche solution, a ZK based game is another niche solution. I've spent almost my entire career in [niche](https://soveran.github.io/cuba/) [solutions](https://docs.nervos.org/docs/ckb-fundamentals/cell-model). I know how hard it is to sell a niche solution to developers. Having one niche is already hard enough, building Godot on ZK based game will be two niche solutions combined together, the difficulty might just skyrocket. So while ZK game will remain a niche solution, I want to find a different game engine solution, attracting more developers. Hoping that, with a much bigger developer base, I can run into people curious about the ZK based game idea.

Luckily, for the (arguably) most widely used game engine [Unity](https://unity.com/), despite the core being non-deterministic, people have [developed](https://doc.photonengine.com/quantum/v3/quantum-intro) [enough](https://andrea-jens.medium.com/footsies-fighting-games-distilled-d813e6bacff4) [techniques](https://www.halilcosgun.com/deterministic-pathfinding-meets-rollback-netcode/) to [build](https://github.com/Unity-Technologies/ECSGalaxySample/blob/main/_Documentation/determinism.md) deterministic cores in Unity. While existing solutions solve multiplayer synchronization as a problem, the same techniques could be used in ZK proving.

Now I have a better plan:

1. [impulse](https://github.com/xxuejie/impulse) wraps off-the-shelf [JoltPhysics](https://github.com/jrouwe/JoltPhysics) in a RISC-V runtime, runnable on a modern ZK engine. For the moment [OpenVM](https://github.com/openvm-org/openvm) shines as it natively allows floating point extension, but I'm curious if anyone else will catch up.
2. Via the beautiful separation of rendering code and core simulation in Unity, we can build a Unity plugin, where we offload all simulation to the plugin core running JoltPhysics, and continue to embrace all the goodies provided by Unity in game development.
3. JoltPhysics is one of the pioneers in building a [deterministic simulation](https://jrouwe.github.io/JoltPhysics/#deterministic-simulation) across multiple platforms. At least, to the best of my knowledge, it's the first open source, mature solution pushing this. Now we just need to make the ZK runtime environment adhere to cross platform determinism enforced by JoltPhysics.
4. Under production load, we still run native code at the optimal speed for game simulation. Only exception is that periodically (e.g., every minute), a world state hash with a game input script will be recorded for public verification. When one disagrees with the canonical state, the game input script with the world state hash will suffice to build a ZK proof, slashing the server posting a malicious state.

With those, we have covered simpler games like Teeworlds or One Hour One Life: full game simulation runs directly on chain. For more complicated AAA games, ZK will still enable full proving. I'm just a lower level system engineer who knows almost nothing about game design, I still want to push One Hour One Life the on-chain version to production, but anything beyond that will be beyond my capabilities. So if you are keen to do something like this as well, feel free to reach out :)
