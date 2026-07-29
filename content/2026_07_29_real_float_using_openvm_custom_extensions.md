+++
title = "Real Floats Using OpenVM's Custom Extensions"
date = "2026-07-29"
+++

[Last post](/2026_07_28_a_failure_optimizing_softfloat/) talks about my failure optimizing softfloat. As we discussed, fixed-point math is not a universally agreed solution. Do we just give up and accept not having floating point numbers on chain?

I mentioned [OpenVM](https://github.com/openvm-org/openvm) at the end of [the Jolt post](/2026_07_10_cpp_ray_tracer_on_jolt_zk_vm/). I mentioned that OpenVM on 32-bit is a blocker. Boy, was I wrong. There were two things I missed:

* Even with rv32im architecture, OpenVM still runs many applications. As we shall see next, OpenVM's custom extension feature has big merits.
* [This PR](https://github.com/axiom-crypto/openvm-eth/pull/673) hints that the amazing Axiom people are working on rv64im support, we might see it as soon as OpenVM 2.1.0.

So I experimented with OpenVM, and [ported the same ray tracer demo to OpenVM](https://github.com/xxuejie/ray-tracer-on-openvm). First, here are some numbers:

```
| VM                                                    | Cycles (IPC = 1)   | Speedup |
|-------------------------------------------------------|--------------------|---------|
| Jolt (rv64im + softfloat)                             | 166,905,547 cycles | 1x      |
| Jolt (rv64im + softfloat + non-float optimizations)   | 122,043,178 cycles | 1.36x   |
| OpenVM (rv32im + softfloat)                           | 123,294,825 cycles | 1.35x   |
| OpenVM (rv32im + softfloat + non-float optimizations) | 99,083,769 cycles  | 1.68x   |
| OpenVM (rv32imf)                                      | 29,591,216 cycles  | 5.64x   |
| OpenVM (rv32im_zfinx)                                 | 29,467,504 cycles  | 5.66x   |
| OpenVM (rv32imf + non-float optimizations)            | 5,283,763 cycles   | 31.58x  |
| OpenVM (rv32im_zfinx + non-float optimizations)       | 5,147,995 cycles   | 32.42x  |
```

In a nutshell, by building a [custom extension](https://docs.openvm.dev/book/advanced-usage/creating-a-new-extension), we can have native floating point numbers (provided by RISC-V's F extension or zfinx extension) in OpenVM. In the best case, we can achieve a ~32x speedup compared to softfloat solution! It's worth mentioning that raw RISC-V instructions executed are not the full picture for performance. Proving floating point instructions might be much more expensive than proving integer instructions. But personally, I would still consider these usable results.

For comparison, here's what I get on native x86_64 environment (I'm testing on Intel Core i5 11500):

```
$ make build-native USE_FLOAT=true
$ sudo perf stat ./build/raytracer_native > image.ppm
Done.

 Performance counter stats for './build/raytracer_native':

                 0      context-switches                 #      0.0 cs/sec  cs_per_second
                 0      cpu-migrations                   #      0.0 migrations/sec  migrations_per_second
               145      page-faults                      #  87126.4 faults/sec  page_faults_per_second
              1.66 msec task-clock                       #      0.2 CPUs  CPUs_utilized
            26,577      branch-misses                    #      1.6 %  branch_miss_rate
         1,667,836      branches                         #   1002.2 M/sec  branch_frequency
         6,134,926      cpu-cycles                       #      3.7 GHz  cycles_frequency
        10,074,298      instructions                     #      1.6 instructions  insn_per_cycle
                        TopdownL1                        #     37.0 %  tma_backend_bound
                                                         #     12.9 %  tma_bad_speculation
                                                         #     16.4 %  tma_frontend_bound
                                                         #     33.7 %  tma_retiring

       0.001997706 seconds time elapsed

       0.001034000 seconds user
       0.001036000 seconds sys
```

On native the program takes ~10 million instructions as well. It's comparing apples vs oranges of course, but ~5 million RISC-V instructions are needed on RISC-V, maybe we have gotten rid of most overhead.

*Note*: for simplification, I'm only building single-precision floating numbers now. Earlier Jolt sample from [previous post](/2026_07_10_cpp_ray_tracer_on_jolt_zk_vm/) used double-precision floating numbers. I have since added [single precision support](https://github.com/xxuejie/ray-tracer-on-jolt/commit/6e052214489e58a1c13c08362a5495a3d344a890) in the Jolt demo as well. All numbers in this post are gathered running single precision support. So if you were puzzled that previous post shows ~180 million cycles for Jolt example, but here we show ~166 million cycles, it's due to the precision difference.

# OpenVM

OpenVM was developed primarily by [Axiom](https://www.axiom.xyz/). One of its key features is a [modular no-CPU architecture](https://docs.openvm.dev/book/getting-started/introduction/): it does not have a clear definition of CPU. Even the core rv32im ISA is designed as an extension. All data flow through [shared buses](https://docs.openvm.dev/specs/architecture/circuit-architecture). This makes it quite easy to extend the ISA, adding new instructions. The extension building process is actually [well designed](https://docs.openvm.dev/book/advanced-usage/creating-a-new-extension), I didn't run into any hassles during the whole experiment. Everything is quite neat.

I do have a question regarding proving side as well: will hosted proving infrastructure, like the [Axiom Proving API](https://www.axiom.xyz/proving-api), provide custom extension support as well? It will be really great if proper sandboxing can be designed so proving works with custom extensions as well. We will have to wait and see.

That said, for games, I think it might be in its particular sweet spot: chances are the gamer running games will already have a not-too-shabby GPU, so when proving is really needed, one can just use their own GPU to generate the proof. It might take longer on a single GPU but it might be fine as we are talking about a single proof. So maybe proving with custom extensions is not that critical.

# `openvm-floating`

Following the [official doc](https://docs.openvm.dev/book/advanced-usage/creating-a-new-extension), I started building a custom extension. I must admit I'm more a VM person and know less about zero knowledge proof theory. So I relied on GLM 5.2 to help me code most of the extensions. Interestingly, while I was building the extension, Kimi 3 came out. I then had the two LLMs working on the extension in rotating shifts. The final result is [here](https://github.com/xxuejie/openvm-floating), both models reported that I didn't get soundness fully right, but at least it can run enough code, and some of my proving tries do work now. So praise the agents :P I do want to get into ZK theories so I can maintain this library myself someday, but not today.

## `F` vs `zfinx` extension

I actually started out with `openvm-floating` implementing [RISC-V F extension](https://docs.riscv.org/reference/isa/v20260120/unpriv/f-st-ext.html), the single-precision floating point part. It turns out there is also `zfinx` extension, which is similar to `F`, except that `zfinx` (`z-f-in-x`) runs floating point operations in `x` registers. `F` extension runs in `f` registers, thus needing transfers between `x` and `f` registers, as well as transfers between `f` registers and memory.

They do not differ too much, so I asked agents to implement both. And the numbers showed that for ray tracer, `zfinx` actually has slightly better performance. I guess for the simpler ray tracer example, register pressure hasn't become a problem, and the extra `ABI` requirements from `F` become visible overhead. In the future I will try more complicated programs, we shall see then which extension yields better performance.

# Putting Together The Port

Now we can put together our port of ray tracer to OpenVM.

## OpenVM's RISC-V Architecture

OpenVM's [spec](https://docs.openvm.dev/specs/openvm/overview) is really good (I wish I could write documentation of this quality back when I was working on CKB-VM -_-), skimming through it gives you almost everything you need to know about OpenVM's RISC-V architecture. While I primarily build programs in C / C++ these days ([Odin](https://odin-lang.org/) I'm coming), this [Rust Frontend](https://docs.openvm.dev/specs/reference/rust-frontend) page is full of gold:

* For now OpenVM uses `riscv32im-risc0-zkvm-elf` Rust target, for me I can just instruct clang to use `rv32im`.
* OpenVM supports [512MB of guest memory](https://docs.openvm.dev/specs/reference/rust-frontend#memory-allocator). Stack grows down from `0x00200400`. I can just patch musl to be aware of those constants.
* No syscall is supported via `ecall`, OpenVM uses custom instructions exclusively.

## `musl` changes

On top of the earlier Jolt work, it didn't take [many changes](https://github.com/xxuejie/musl/commit/87043b94aa903cc88bb65e368b97a76d5fcaefe5) to add OpenVM support in musl. But there are certainly some things I ran into:

* Both CKB-VM and Jolt are using 64 bits, this is really the first 32-bit target I was playing with using my patched musl. So I had to fix `arch/riscv32` code in musl.
* In the version I was using, musl assumes that when floating point registers are available, double precision will be available. This has been [fixed](https://git.musl-libc.org/cgit/musl/commit/src/setjmp/riscv32/setjmp.S?id=0b86d60badad6a69b37fc06d18b5763fbbf47b58) in upstream musl but my version is not yet up-to-date. Since my demo does not use setjmp/longjmp I just remove the buggy code. But really I should sync my patch with upstream version of musl.

## Outputs

There is one thing I ran into: while Jolt offers a configurable memory region for bigger outputs, OpenVM limits the output values to a couple of `u32` values, configured by [num_public_values](https://docs.openvm.dev/specs/openvm/isa#constants-and-configuration-parameters). I didn't find any discussion about making this number really big, e.g, 4194304 so we can generate 16MB of output data. So I didn't risk doing it.

Since I can tweak the heap configuration, I did the following setup instead:

* In `musl`, configure heap to start from `_end` symbol till 480MB.
* We build a reserved memory region from 480MB till 512MB.
* In the guest program, we output the ray tracer generated image into the 32MB reserved memory region. Then the program runs sha256 hash (using OpenVM's [SHA2](https://docs.openvm.dev/specs/openvm/isa#sha-2-extension) extension) on the generated image, and reveal the full sha256 hash.
* In the Rust runner driving OpenVM's executor & prover, we can inspect the memory to extract the generated image, then compare it with revealed public values, ensuring they match, and save the output image.

```
+-----------------------------------+ 0x20000000 (512 MB)
| Reserved Memory for Output        |
| Ray Tracer Image (~32 MB)         |
+-----------------------------------+ 0x1E000000 (480 MB)
| ^                                 |
| | Heap Grows Upward               |
|                                   |
| Heap Region                       |
+-----------------------------------+ `_end`
| ELF Code / Data / BSS Segments    |
+-----------------------------------+ 0x00200800 (~2.002 MB)
| xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx |
+-----------------------------------+ 0x00200400 (~2.001 MB)
| Stack Region                      |
+-----------------------------------+ 0x00000000 (0 MB)
```

I remember first reading about this trick when I was diving into [SP1 code](https://github.com/succinctlabs/sp1/blob/6ddc6f4216aee10d050f30d8d2e767c763d8a0de/crates/zkvm/entrypoint/src/lib.rs#L38-L59). SP1's guest program would reserve 16GB memory region at the very end of memory address space, but for storing read input values. As we have the need, there is nothing stopping us from leveraging the same trick for output values by OpenVM.

But I'm really new to OpenVM, I'm not 100% sure if this is free of quirks. Maybe there are some other restrictions I'm not aware of.

## Running Everything

Now we can start running everything, the [README](https://github.com/xxuejie/ray-tracer-on-openvm/blob/main/README.md) file of the [repo](https://github.com/xxuejie/ray-tracer-on-openvm) already contains the steps, so I won't repeat them here.

There is only one gotcha I want to point out: for now `openvm-floating` only has single precision support, so double precision operations will still be implemented via softfloat. When you are running the demos here, `USE_FLOAT=true` is a mandatory flag.

## Profiler

As of the time I tried, there is no way to expose pc traces from OpenVM. I had to add a [patch](https://github.com/xxuejie/openvm/commit/2c97976209bdb06c994990581a3b64ab53d1e3f1), exposing a hook so I can peek into runtime environment. With it we can build a profiler supporting [inferno](https://github.com/jonhoo/inferno) based flamegraph, [pprof](https://github.com/google/pprof) and also [samply](https://github.com/mstange/samply). For example, here's a `pprof` chart of the final optimized program, after optimizations from the next section are also applied:

![Profiler Chart for OpenVM Guest Program](https://raw.githubusercontent.com/xxuejie/ray-tracer-on-openvm/refs/heads/main/docs/profiler.png)

## Optimizations

When softfloat no longer is a bottleneck, slow code from the integer portion of the ray tracer program will then be visible:

* [ostream operator<<](https://github.com/RayTracing/raytracing.github.io/blob/0ab7db4c08fe23f23c0d9d30fed166c83cefed91/src/InOneWeekend/camera.h#L36) takes much more cycles than it should. For the simpler format in the ray tracer, we can [skip the generic solution](https://github.com/xxuejie/ray-tracer-on-openvm/commit/e2cb0ee7398aad12052e25d699a5f2d2f36cacd4) for fewer cycles.
* There are also unnecessary `memset` / `memcpy` operations that [can be skipped](https://github.com/xxuejie/ray-tracer-on-openvm/commit/7b71755c0335a0cd752a442f926df9c1310a5ac9). I have seen far too many cases of this optimizing different RISC-V cycles. There is always room to squeeze out cycles when you look at `memset` / `memcpy`.

Looking at the number: using `rv32im_zfinx` before those optimizations, ray tracer takes ~29.5 million cycles to complete. When those optimizations are applied, ray tracer now only takes ~5.2 million cycles. Even when floating point operations become native, we can still obtain another 5.72x speedups by profiling the code. With softfloat dominating the stack, it's hard to pinpoint those optimizations.

# Picturing ZK Powered On-chain Games Together

Now we have usable native floating point numbers supporting on-chain games, I'm picturing the following setup:

1. Native OpenVM floating point extension is implemented to use the exact same behavior as native x86_64 / aarch64 floating point operations. As JoltPhysics [has demonstrated](https://jrouwe.github.io/JoltPhysics/#deterministic-simulation), this is actually doable.
2. In the happy case, games run on native x86_64 / aarch64 code, using native floating point instructions for maximum performance.
3. At certain intervals (e.g., 1 minute based on [Teeworlds](/2026_06_16_teeworlds_on_ckb/) / [OHOL](/2026_06_29_porting_one_hour_one_life_game_loop_to_ckb/) convention), the server updates the current world state hash on-chain, and submits player inputs for current interval either also on-chain, or to a cheaper DA solution.
4. All players can monitor on-chain values. When a mismatch is detected, a player can build a proof for the last `chunk`'s gameplay, and submit it on-chain. Since there's no point running a rigged game, the player can leverage GPU to accelerate proving. The proof effectively validates the last `chunk`'s gameplay, proving misbehavior of the server. The game can then settle or revert and continue from a previous point, depending on the game design.

Determinism is crucial here: in the optimal case floating point operations run natively on CPU; but when proving happens they run on OpenVM with floating point extensions to build proof. Both should have the exact same bit-by-bit behavior.

With this combination of optimistic-based and ZK-based design, we can afford to build games at a much larger scale, but still be able to validate the full game on-chain.

OpenVM really shines here with the custom extensions. We can build a native floating point extension into it, without forking OpenVM at all. It certainly won't be an easy task to build a fully secure floating point extension (I'm still on it), but the fact that this even works, surely looks like a miracle to me.

# A Spectrum Of Solutions, For Games

For the past few months I've been experimenting with different setups. I started with [Teeworlds](/2026_06_16_teeworlds_on_ckb/) and [OHOL](/2026_06_29_porting_one_hour_one_life_game_loop_to_ckb/) directly running on CKB-VM, to two ZK VMs running ray tracers with different floating point operation support. The reason for those efforts is that games vary a lot, different designs require different architecture and implementations. I want to have a spectrum of solutions, covering as many kinds of games as possible. If one game designer wants to build on-chain game with their own ideas, we should have a set of architectures suiting whatever design they want to go for.

While my earlier demos with [Teeworlds](/2026_06_16_teeworlds_on_ckb/) and [OHOL](/2026_06_29_porting_one_hour_one_life_game_loop_to_ckb/) show how to build simpler 2D games on-chain, I think we can do more using OpenVM ZK VM with floating point extension. You might have already noticed that I talked a lot about [JoltPhysics](https://github.com/jrouwe/JoltPhysics), this is actually my next target: with floating point extension powered OpenVM, I want to port JoltPhysics on chain and run it efficiently, and the journey does not stop there: as JoltPhysics is now [the official physics engine of Godot](https://godotengine.org/releases/4.6/), can we go one step further, and have a full Godot-powered game running on-chain via a ZK VM?

If you are interested, stay tuned. I will share what I find.
