+++
title = "A Failure Optimizing Softfloat"
date = "2026-07-28"
+++

This documents my quest trying to optimize softfloat for on-chain games. It is a failure, but it's still an interesting story.

# Floating Point Matters To Some

Floating point numbers have always been a controversial issue. It's mostly [prohibited](https://docs.kernel.org/core-api/floating-point.html) in Linux kernel, and fintech software skips it entirely.

Even in games, it's frequently only restricted to graphics code: StarCraft and StarCraft II rely on fixed-point integer math for the game logic. Many other games follow this design, such as Age of Empires series, Street Fighter online games, Clash Royale, etc. There has long been debate about deterministic floating point operations for multiplayer games. Gaffer has it [summarized well](https://gafferongames.com/post/floating_point_determinism/), though I'd say this is an issue worth debating, there are [cases](https://jrouwe.github.io/JoltPhysics/#deterministic-simulation) we can have cross platform determinism in some sense.

That said, there are games using native floating point math, relying on server calculated states as absolute authority, and do state synchronization so everyone agrees on the final state. This way indeterminism in floating point is irrelevant to the question. Rocket League, Counter-Strike 2 and Overwatch fall into this category. In fact this seems to be the case for most Unreal or Unity based games.

So both fixed-point math and floating point math are used widely in games. We cannot just ask everyone to use fixed-point math, some love to do it, but some do not want the trouble. Floating point still matters.

Yet we have seen the recurring theme from previous posts: of all the programs we ported (Teeworlds, One Hour One Life, ray tracer), the number 1 bottleneck we found after first success run, will always be softfloat. It takes a lot of operations to calculate floating point number on a RISC-V CPU without native floating point support. Now the question naturally is: can we do something about it?

# Design: Tradeoffs For Performance

I'm not arrogant enough to say I can make softfloat much faster in its current design. Many smart people have put their work into this space, making softfloat as fast as it can be. What I'm thinking is: if we accept some tradeoffs, how much faster can our floating point operation be? Some initial ideas include:

* What if we use 64 bits (8 bytes) for 1 single-precision, 32-bit floating number (`float` on C, `f32` on Rust)?
* What if we just support round-to-nearest-even (RNE) mode only?
* What if there is a canonical NaN?
* Thinking further: I'm building it for games, typical floating point operations in games come in batch, such as vec3 or vec4. What if we build `fused ops` that pack multiple floating point operations together? How fast can it be?

Depending on the workload, on modern systems softfloat can range from 10x to 100x slower than native floating point operations. In my test, softfloat is about 50x - 70x slower than native floating operations. We will never make softfloat as fast as native floating point operations, but when I started, I listed the following goal:

* My optimized `fast softfloat` solution should be 5x faster than current softfloat library.
* For basic operations (add, sub, mul, div, etc.), I want most of them to complete in less than 20 integer operations. For some we might not reach this number, but most should fit in this range.

While making those optimizations, we should keep the behavior bit-by-bit exact with [IEEE 754](https://en.wikipedia.org/wiki/IEEE_754) semantics. There cannot be a single bit of divergence.

With those, let's dive into different ideas I tried.

# Idea 1: 64 Bits For `f32`

A `f32` has the following encoding:

```
31      30                               23 22                                     0
+-------+----------------------------------+---------------------------------------+
| Sign  | Exponent (E)                     | Mantissa (M)                          |
| 1 bit | 8 bits                           | 23 bits                               |
| [31]  | [30:23]                          | [22:0]                                |
|       | Stored: 0 to 255                 | Value: 0 to < 1.0                     |
|       | Actual: -126 to +127             | (Implicit leading 1)                  |
+-------+----------------------------------+---------------------------------------+

Formula: (-1)^S * 2^(E - 127) * (1.M)
```

All 3 components (`sign` bit, `exponent`, `mantissa`) fit in a 32-bit value.

For a normal softfloat operation, 5 steps are needed.

1. Unpacking: unpack 3 components in a 32-bit value, typically into 3 registers.
2. Alignment: align the exponents of 2 operands, so we can perform arithmetic operations on the 2 `mantissa` fields.
3. Arithmetic: do the actual arithmetic operations on aligned `mantissa` fields.
4. Normalization: based on IEEE 754 precision rules, truncate `mantissa` (if needed), then re-scale `exponent` and `mantissa` fields.
5. Packing: pack 3 components back into a single 32-bit value.

For more details, [Fabien Sanglard](https://fabiensanglard.net/floating_point_visually_explained/) explained it much much better than me.

Of the 5 steps, only 3 (and maybe a bit of 4) are the true workload, everything else is the overhead we want to minimize.

So the first idea is: modern CPU instructions only work at byte boundaries. What if we introduce a different layout, so a `f32` uses more bits, but each component is properly laid out for ease of access? One idea could be the following:

```
63       47                              32 31                                     0
+-------+----------------------------------+---------------------------------------+
| Sign  | Exponent (E)                     | Mantissa (M)                          |
+-------+----------------------------------+---------------------------------------+
```

`Mantissa` now takes the full 32 bits at lower address. Most CPUs have instructions to read the lower 32 bits from a 64 bit register directly. `Exponent` still needs shifting + masking operations so we can get its value. `Sign` is kept at the highest bit since it's easier to convert sign at this location to flags. We now use full 64 bits to represent a `f32` value. The benefit is: component extraction is much easier.

As more bits are available, we can also fit in flags, for example, bit 48 - 62 can be repurposed to represent `NaN` value, `infinity` value or other subnormal values. Maybe it will help avoiding more overhead. We shall see later this is even more useful combined with the `fast path` design.

## Memory Changes

Some might raise the question that memory layout might change: now a `f32` value requires 64 bits, memory bandwidth requirement increases, some pointer math might not work anymore. I've thought on this question:

First, it's definitely true that more memory is needed. This is a compromise we will have to take. We are effectively trading off memory space for performance. In fact, in the [Teeworlds](https://xuejie.space/2026_06_16_teeworlds_on_ckb/) post, the `fpm::fixed<std::int64_t, __int128_t, 16>` fixed math type I used to replace `f32` in Teeworlds is exactly 64 bits. We have traded memory space for performance before.

And the pointer math situation might not actually be that bad:

* Many well-written lower level math heavy libraries pay attention to value sizes. [JoltPhysics](https://github.com/jrouwe/JoltPhysics) has optional double precision support, so while it still uses `f32` exclusively in some places, it pays attention to different value sizes. I'm sure many other libraries do the same.
* Many games are not written in native programming languages actually. There are [GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) and C#, people even use [Blueprints](https://www.reddit.com/r/unrealengine/comments/x7eco2/what_successful_games_have_been_made_in_unreal/) to make Unreal games. When those higher level languages are used, the actual value size of `f32` is just a minor detail hidden in the VM layer. Similarly, it could also benefit WASM programs: the underlying WASM engine maps `f32` to a 64 bit value, while the WASM program has no knowledge of it.

So it's definitely true there will be tradeoffs representing `f32` as a 64-bit value. But I'm willing to bet that many cases are transparent with this change, and the native part can mostly be fine when some attention is paid.

# Idea 2: Defer Normalization

We can think further: for 64 bit values, there are more bits for `mantissa`, there are also more bits for `exponent`. So maybe we can skip `normalization`. When step 3 (`arithmetic`) is done, we can do step 5 (`packing`). When the next operation is performed, it can unpack the value, then do the `normalization & alignment` altogether. Effectively, this is the new workflow:

1. Unpacking: unpack 3 components in a 32-bit value, typically into 3 registers.
2. Normalization & Alignment: truncate first if needed per IEEE 754 precision rules, then align the exponents of 2 operands, so we can perform arithmetic operations on the 2 `mantissa` fields.
3. Arithmetic: do the actual arithmetic operations on aligned `mantissa` fields.
4. Packing: pack 3 components back into a single 32-bit value.

We are still doing normalization so the behavior is identical to IEEE 754 semantics. But the idea is: by combining `normalization` and `alignment`, maybe some common work can be skipped, reducing the overhead around softfloat arithmetic operations.

# Idea 3: Fused Ops

We can go even further than the previous idea: for continuous floating point operations, softfloat is repeatedly doing the `unpacking`, `alignment`, `arithmetic`, `normalization`, `packing` loop. Next operation has to unpack values packed by previous operation.

On the other hand, floating point operations follow predictable patterns. Games frequently use vectors of 3 or 4 float values, and do operations on them. Examples are [Vec::Dot](https://github.com/jrouwe/JoltPhysics/blob/cbb3260249fc25afe12b2e0f2ce17f77503859ba/Jolt/Math/Vec3.inl#L931-L934) and [Mat44::Multiply3x3](https://github.com/jrouwe/JoltPhysics/blob/cbb3260249fc25afe12b2e0f2ce17f77503859ba/Jolt/Math/Mat44.inl#L384-L421). They are used a lot in JoltPhysics.

Note `Mat44::Multiply3x3` already has specializations using [SSE](https://en.wikipedia.org/wiki/Streaming_SIMD_Extensions), [NEON](https://support.arm.com/architectures/neon) or [RVV](https://docs.riscv.org/reference/isa/extensions/vector/_attachments/riscv-v-spec.pdf) for speedups. What if we write our own specialized implementation in softfloat, where we keep the intermediate, unpacked values, and do the subsequent floating point operations, and only pack the final result, when the whole calculation completes?

This is a lot like RISC-V's [Macro-Op Fusion](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2016/Archive/EECS-2016-130.pdf), I call it `fused ops` for short.

I used the following structure:

```
typedef struct {
    uint64_t mantissa;
    int      exponent;
    uint8_t  sign;
} fsf_fat;
```

It's a struct but modern compilers should have no issues hoisting hot fields into registers. In a fused op, all floating point values will be expanded into this format, perform all the arithmetic operations needed, eventually, values in the fat format are packed back into 32-bit `f32` values.

One quirk worth mentioning, is that fused ops introduce register pressures: `Vec::Dot` has 6 `f32` inputs, `Mat44::Multiply3x3` has 12. More intermediate values are created internally. Some of those values will spill to memory, adding memory loads & stores. Those are also overhead, by going into x86_64 / RISC-V assembly we can mitigate some, but we won't eliminate all register spills.

Arguably, `fused ops` still provide the biggest speedups of all the ideas tried.

# Idea 4: Fast Path

IEEE 754 defines 5 classes for floating point values:

* Normal values
* Zeros, including +0.0 and -0.0
* Plus and minus infinities
* NaN
* Subnormal values, or tiny numbers between `min` in normal values and zero

A proper softfloat library should handle all of them, meaning every operation should pay attention to special rules required by non-normal values. But in game physics, most values are just normal values.

[Here's](https://gist.github.com/xxuejie/eb58dfd0f469ef2b16f57f1fa1b6519c) a dump of `__addsf3` function in rv64im. As it's part of [compiler builtins](https://www.chiark.greenend.org.uk/doc/gcc-4.9-doc/gccint.html#Soft-float-library-routines), it's offered as a symbol and won't be inlined. As it handles all softfloat value types, it's rather bloated, having both [a prologue and an epilogue](https://en.wikipedia.org/wiki/Function_prologue_and_epilogue). Even though normal values can be processed simpler, the full overhead is still paid for every operation.

We can divide a softfloat operation into 3 parts:

* A quick way (ideally one or two instructions) to check if an input is a normal value.
* A fast path without prologue / epilogue on normal values alone.
* A slow path handling all value classes.

This way, 90% of the operations fall into fast path, and can work much faster, while slow path covers the small number of outliers with correct semantics.

## Pure Assembly

C / C++ can be vague or imprecise sometimes. To really get rid of prologue / epilogue, we need to get into pure assembly implementation. In addition, register allocations for long functions in C / C++ can be less than ideal. While we can deduce a variable will not be needed, and can be overridden, compilers don't always know this. To handle fused ops more efficiently, pure assembly is also needed here. C compilers are helpful but they are only helpful in common cases, if we really want to squeeze the last drop of performance, pure assembly is needed in hot loops.

# Out Of Ideas For Softfloat -_-

I don't know what you think, but when I first came up with those ideas, I thought there was a chance I could make it work. Unfortunately, I've dug hard on this, and even when I combine all those ideas together, the best I could do was 2x the performance of current softfloat implementation. We are still 30x - 50x slower than native. In that sense, it might not be worth the effort patching everything to build a demo which is only 2x faster. I tried, and my conclusion is: I think softfloat is fast enough if we want bit-by-bit match with [IEEE 754](https://en.wikipedia.org/wiki/IEEE_754) semantics. Like the title suggests, this is a post marking my failure.

Luckily, there is a way out, we can have much faster floating point solutions in ZK VMs, and [I can make it work](https://github.com/xxuejie/ray-tracer-on-openvm) (hint: we can use real float). I will elaborate more in my next post.
