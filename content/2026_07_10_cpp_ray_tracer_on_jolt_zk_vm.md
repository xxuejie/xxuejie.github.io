+++
title = "C++ Ray Tracer on Jolt ZK VM"
date = "2026-07-10"
+++

I've spent [quite](https://github.com/succinctlabs/sp1/pull/2594) [some](https://github.com/succinctlabs/sp1/pull/2658) [time](https://github.com/OffchainLabs/nitro/pull/4170) with Succinct's SP1 zkVM. I believe as of now, SP1 is the most mature zero knowledge engine on the market. SP1 is not limited to simple toy programs, it can scale to really sophisticated programs for production usage.

That said, there are other equally interesting ZK engines. Most are in earlier stages compared to SP1, but they do possess fascinating, different designs that enable different tradeoffs compared to SP1. The theory behind zero knowledge proofs is quickly advancing, different research & engineering directions are explored by different minds, including my friends at Succinct [experimenting with different designs](https://x.com/SuccinctLabs/article/2070217264398225839).

For the past week or so I'm trying [Jolt](https://github.com/a16z/jolt), which is designed solely around [Lasso lookup tables](https://people.cs.georgetown.edu/jthaler/Lasso-paper.pdf) (or **J**ust **O**ne **L**ookup **T**able, if you caught the coincidence). This interests me a lot since memory accesses can potentially be much cheaper. After [30 years of the memory wall](https://scispace.com/pdf/hitting-the-memory-wall-implications-of-the-obvious-s25mrxiprp.pdf), ZK VMs built on lookup arguments might give us slightly cheaper random access. Cache-line aware data structures might no longer haunt our dreams so badly.

As a rapidly evolving experimental project, Jolt only has support for writing Rust programs, using its [nicely wrapped macros](https://jolt.a16zcrypto.com/usage/guests_hosts/guests.html). But to really dig into the fundamentals, I really need to test code architected differently, down to the precise RISC-V instructions used. So I started a quest: can I put together a C++ program using clang / lld alone, and run it in Jolt?

After some experiments I got it to work: I ported a C++ [Ray Tracer](https://raytracing.github.io/books/RayTracingInOneWeekend.html) to Jolt, managing to execute / prove it in Jolt's ZK engine, I've also built a guest-level profiler that is compatible with both C++ programs and Rust guest programs following Jolt's tutorials. If you just want to try it out first, use the following steps:

```
$ git clone --recursive https://github.com/xxuejie/ray-tracer-on-jolt
$ cd ray-tracer-on-jolt


$ # This will build and execute the ray tracer program using Jolt's VM
$ make run-jolt
(build step omitted..)
./runner/target/release/jolt-vm-runner
Done.
execution:   39.01s (180081356 cycles)
Output size: 42392 bytes
Saved image_jolt.ppm (42387 bytes)
$ # Now you can find `image_jolt.ppm` file in current folder, it is generated
$ # by the ray tracer program, executed in Jolt's VM.


$ # This builds and runs the same ray tracer program in native environment:
$ make run-native
(build step omitted..)
./build/raytracer_native > image.ppm
Done.
wrote image.ppm (42490 bytes)
$ # Generated image can be found in `image.ppm`.


$ # You can also try proving mode in Jolt. Since proving takes more resource,
$ # we will try it on a tiny image.
$ make prove-jolt IMAGE=tiny
(build step omitted..)
./runner/target/release/jolt-vm-runner prove
Done.
execution:   3.67s (16920650 cycles)
Output size: 4080 bytes
Saved image_jolt.ppm (4073 bytes)


== Prove + verify (max_trace_length = 33554432, ~3072.0 MiB trace) ==
preprocess:  44.60s
Done.
Done.
prove:       214.03s
proof size:  91.3 KiB (93529 bytes)
verify:      0.19s
✓ proof verified


$ # Finally, I've built a guest program profiler you can try:
$ PROFILE_FILE=profile.txt make run-jolt
$ # Refer to the profiler section below for details.
```

If you are interested in the internals, follow me along.

# Ray Tracer

I need a program that is big enough to use C / C++ features, but also small enough to fit experiments. I settled on a [ray tracer](https://en.wikipedia.org/wiki/Ray_tracing_(graphics)) program, for several reasons:

* I've been digging into game coding lately, and I have further plans in this direction. A ray tracer is related to the topic.
* A lot of floating point operations are used in ray tracing, which is even more related to my future experiments.
* Ray tracer is fun. After running the program, you can have an image to check out immediately. You don't just stare at cold debug output, you get an image.
* There are wonderful [resources & programs](https://raytracing.github.io/books/RayTracingInOneWeekend.html) on ray tracer we can leverage.

[Ray Tracing in One Weekend](https://raytracing.github.io/books/RayTracingInOneWeekend.html) provides a wonderful starting point for us. I also strongly recommend you follow along in the course, try to build a ray tracer by yourself.

To be honest I considered [Mandelbrot](https://en.wikipedia.org/wiki/Mandelbrot_set) as well but ray tracing is a more fun choice.

# Jolt's RISC-V Architecture

With a program chosen, we will have to see how Jolt's ZK VM works.

For completeness, I'm using Jolt as of [this commit](https://github.com/a16z/jolt/commit/c36a2eacab14c2e42462b8aba91edf5c09814ef1). Future versions might or might not have different behaviors.

First, some brief information that can be explained in one-liners:

* Jolt uses `RV64IMAC`. It has a bare metal path where CSR instructions are not available, and a `ZeroOS` mode where it behaves more like traditional Linux OS. For simplicity, I will stick to the bare metal path, but it's worth knowing a different path exists.
* Usable memory starts at `0x80000000`, all the ELF sections, stack and heap will need to start after `0x80000000`. Lower addresses are reserved (we will get to this later). This also means `-mcmodel=medany` is pretty much required for long addressing.
* When proving, Jolt does not use sparse memory. This means if you write a value to the address `0x1080000000`, Jolt will resize a `Vec` to use ~64GB memory. I assume this is more like a current limitation, and might be optimized away in later versions. Still it's worth noting it.
* Jolt does not use `argc` / `argv`, it does not have a return code, either. All communications have to be implemented as host-guest IO, we will get to the IO part below. There is a panic mode, though. A program either terminates, or panics.
* The official Jolt repo is mostly focused on proving infrastructure. A separate [repo](https://github.com/LayerZero-Labs/ZeroOS) by [LayerZero](https://layerzero.network/) contains the runtime part. Refer [here](https://github.com/LayerZero-Labs/ZeroOS/blob/main/crates/zeroos-arch-riscv/src/boot.rs) for the boot process of a Jolt guest program.

Let's now get into the slightly more complicated details:

## Memory-mapped IO

Jolt utilizes [memory-mapped IO](https://en.wikipedia.org/wiki/Memory-mapped_I/O_and_port-mapped_I/O) a lot. Fixed (though tweakable) memory regions are allocated below `0x80000000` for guest programs to read inputs, write outputs, mark program terminations, etc. A [MemoryConfig](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/common/src/jolt_device.rs#L49) structure defines everything. When initializing a Jolt VM, one defines the `MemoryConfig` structure, specifying parameters such as input region size, output region size, etc. When not needed one can use the default settings, which allocates 4096 bytes for input & output regions. Jolt then does the calculation backwards from `0x80000000`, determining the starting address for input region, output region, termination address, panic address, etc. You can also refer [here](https://github.com/xxuejie/musl/blob/6b5289e8b6d20a39cd932b7a7057e3e2559b3b3c/ckb/jolt_vm.h#L22-L85) for the exact calculation logic in simple C. In the default case, the initialized memory-mapped region will look like following:

```
*-----------------------------------------------------------------------*
|                     I/O REGION  (below RAM_START)                     |
|                                                                       |
|  Address       Region              Size    Direction                  |
|  ----------    ----------------    ------  -------------------------- |
|  0x7FFF8000    trusted_advice      4096 B  <- guest READS (prover)    |
|  0x7FFF9000    untrusted_advice    4096 B  <- guest READS (prover)    |
|  0x7FFFA000    input               4096 B  <- guest READS (host)      |
|  0x7FFFB000    output              4096 B  <- guest WRITES (host)     |
|  0x7FFFC000    panic               8 B     <- guest WRITES 1 on panic |
|  0x7FFFC008    termination         8 B     <- guest WRITES 1, then j .|
|                                                                       |
|  (padding to power-of-two word boundary -- witness alignment)         |
*-----------------------------------------------------------------------*
                            :
*-----------------------------------------------------------------------*
|  0x80000000    RAM_START                                              |
|                                                                       |
|  Program image    .text / .rodata / .data / .bss                      |
|  Stack canary     128 B                                               |
|  Stack            grows DOWN   <- sp starts at __stack_top            |
|  Heap             grows UP     -> bounded by __heap_end (brk)         |
*-----------------------------------------------------------------------*
```

I'm not using devices, I haven't explored the device interface yet. We will get to stack & heap later when we talk about symbols.

In this setup, a guest program reads from memory to get inputs, writes to memory to set outputs. It also terminates by writing `1` to the termination address, and panics by writing `1` to the panic address. No syscalls are used.

This does mean that conventional `exit` method in libc for RISC-V won't work for Jolt, a special one is [needed](https://github.com/xxuejie/musl/blob/6b5289e8b6d20a39cd932b7a7057e3e2559b3b3c/ckb/jolt_vm.h#L180).

**PS**: there is a caveat: the doc mentions [termination address](https://jolt.a16zcrypto.com/how/architecture/ram.html#output-check), `MemoryConfig` also has it, but the actual implementation elides it:

* Writing to termination address is a [no-op](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/common/src/jolt_device.rs#L110-L115).
* Execution simply [stops](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/tracer/src/lib.rs#L218-L223) when infinite loop is reached.

So technically, `j .` in RISC-V could stop a Jolt program, regardless, I implemented `exit` properly in case this will be fixed later (I think it should).

## Custom Opcodes

Different from CKB-VM or SP1, Jolt implements the runtime related function as [custom instructions](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/tracer/src/instruction/mod.rs#L3-L10). For example, [VirtualHostIO](https://github.com/a16z/jolt/blob/main/tracer/src/instruction/virtual_host_io.rs#L21) instruction is implemented, one usage of which prints debug messages.

Similarly, precompiles on Jolt are also implemented as [inline instructions](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/crates/jolt-riscv/src/profile.rs#L34-L43), avoiding syscall usage.

There is a way we can [encode the custom / inline instructions](https://github.com/xxuejie/musl/blob/6b5289e8b6d20a39cd932b7a7057e3e2559b3b3c/ckb/jolt_vm.h#L160), it's just worth mentioning that Jolt picks a different path.

Jolt VM itself only provides a `trap` mechanism. When `ecall` happens, it sets up `mcause`, `mepc`, jumps to `mtvec` per RISC-V specification. In the bare metal case, no trap handler is installed, trapping essentially won't work. In other words, host & guest only communicate via memory-mapped IO and VirtualHostIO. With a set of [features](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/jolt-sdk/Cargo.toml#L45-L52), Jolt enables ZeroOS, sets up trap handler, which will handle more [OS level syscalls](https://github.com/LayerZero-Labs/ZeroOS/blob/c4087a825bf3e8157dbb2da01ee196d2a9841e4c/crates/zeroos-os-linux/src/syscall.rs#L138).

## Linking & Special Symbols

```
*----------------------------------------------------------------------*
|  ELF LAYOUT (jolt.ld, default values)                                |
|                                                                      |
|  0x80000000  RAM_START  (RAM: rwx, __ram_length = 64M)               |
|                                                                      |
|  PROGRAM IMAGE (variable size)                                       |
|    .text           R-X  _start (.text.boot/.text.init), code         |
|    .rodata         R--  string literals, const data, .srodata        |
|    .eh_frame_hdr   R--  exception handling header (C++)              |
|    .eh_frame       R--  exception frames (LONG(0) terminated)        |
|    .init_array     RW-  C++ static constructors                      |
|                     (__init_array_start .. __init_array_end)         |
|    .fini_array     RW-  C++ static destructors                       |
|    .data           RW-  initialized globals                          |
|      .sdata              small data                                  |
|                         gp = __sdata_start + 0x800                   |
|    .tdata          RW-  TLS initialized (forced non-empty)           |
|    .tbss           RW-  TLS zero-init (forced non-empty)             |
|    .bss            RW-  zero-init globals                            |
|                     (__bss_start .. __bss_end  <-- _start zeroes)    |
|                                                                      |
|  __program_end                                                       |
|                                                                      |
|  Stack canary          128 B    guard                                |
|  __stack_bottom                                                      |
|  Stack                 4 KB     grows DOWN  (sp = __stack_top)       |
|  __stack_top                                                         |
|                                                                      |
|  Heap                  32 MB    grows UP   (brk: __heap_start..end)  |
|  __heap_end  =  _end                                                 |
|  __memory_end                                                        |
|                                                                      |
|  Defaults:  __ram_length=64M  __heap_size=32M  __stack_size=4K       |
|  Assert:    fits in RAM;  !DEFINED(tohost)                           |
*----------------------------------------------------------------------*

_start (all registers start at 0):
  1. lla gp, __global_pointer$
  2. lla sp, __stack_top
  3. run .init_array constructors  (__libc_start_init)
  4. call main
  5. j .   (PC stall = termination signal)
```

Jolt requires a special ELF layout, enforced by its [provided linker script template](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/src/linker.ld.template). If the template confuses you with a lot of parameters, see [here](https://github.com/xxuejie/musl/blob/6b5289e8b6d20a39cd932b7a7057e3e2559b3b3c/ckb/jolt.ld) for one that's in fact used.

Starting from `0x80000000`, we layout everything needed in an ELF, such as `text` (code), `rodata` (readonly data), `eh_frame` (C++ exception frames), `init_array` (libc init constructors), `data` (globals), `bss` (zero initialized globals). The `__program_end` symbol marks the end of everything loaded by ELF. After `__program_end`, a 128-byte guard section is inserted, then the stack region will be denoted by `__stack_bottom` and `__stack_top` symbols. Following the stack, heap will be defined by `__heap_start` and `__heap_end`. A `__memory_end` symbol is exposed to mark the absolute end of memory used by current Jolt program.

By tracing the exposed symbols, Jolt VM knows exactly the maximum memory used by the program (by `__memory_end` symbol), the stack region (by `__stack_bottom` / `__stack_top`) and the heap region (by `__heap_start` and `__heap_end`).

When booting the Jolt VM, all RISC-V registers will contain 0. The entrypoint code (typically `_start`) will need to load `SP` from `__stack_top`.

Different from SP1, Jolt ensures that all memory is [initialized to 0](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/crates/jolt-prover-legacy/src/zkvm/ram/mod.rs#L708), even in proving mode. So we don't have to zero-initialize BSS manually from `_start`.

## Every VM Makes Its Own Choices

Even though CKB-VM, SP1 and Jolt are all RISC-V VMs, each makes its own design choices. There is no right or wrong, people would design things differently with different backgrounds & preferences. It does mean that we will have to pay attention when porting from one RISC-V VM to another.

# Putting the Minimal Example Together

With all the digging above, my first minimal working example can be found in [this commit](https://github.com/xxuejie/ray-tracer-on-jolt/commit/566d4f74dcf04280dd52332f957c25d79cfadc56). It makes a simple `int main() { return 0; }` C / C++ program run on Jolt VM.

It does require a libc following Jolt's convention and startup sequence. For simplicity, I'm iterating on [my musl fork for CKB-VM](https://github.com/xxuejie/musl), which already has a few handy changes:

* RISC-V bare-metal build workflow.
* Bypassing `sbrk` syscalls, use static memory instead as heap.
* Hijack stdout / stderr writes to proper debugging printer calls.

[This commit](https://github.com/xxuejie/musl/commit/2261add65938d88de36a4e2c0636dbd3d47a9ad5) sets up the structure so the minimal example runs. It basically does 2 things:

* new `_start` implementation that sets `SP` based on Jolt's memory layout.
* A linker script adapted from [Jolt's template](https://github.com/a16z/jolt/blob/main/src/linker.ld.template), catering our needs.

I also introduced [my patched libcxx for CKB-VM](https://github.com/xxuejie/ckb-libcxx-builder) (fortunately, all changes needed for Jolt now are in musl, libcxx needs no changes yet), and the [compiler runtime for CKB-VM](https://github.com/nervosnetwork/compiler-rt-builtins-riscv) (later we will need softfloat). Now the minimal demo works.

# Expanding to Full Ray Tracer

Starting from the minimal example, I gradually added more till ray tracer works. This requires more libc / libc++ changes:

* Musl changes to [setup heap & debug printer](https://github.com/xxuejie/musl/commit/26b538b3bc662d7eb2673795b64153567b045f05), and [argc / argv fixes](https://github.com/xxuejie/musl/commit/6b5289e8b6d20a39cd932b7a7057e3e2559b3b3c).
* [libcxx change](https://github.com/xxuejie/ray-tracer-on-jolt/tree/4b600e6337b2679d13af66dfc4cd724298dba9cc/llvm_patch), specifically in libunwind to skip executing CSR instructions.

Those are enough toolchain changes for Jolt. But we are still not done yet. The original ray tracer writes image to `stdout`, and progress messages to `stderr`, while Jolt VM does allow printing debug messages, we mix `stdout` / `stderr` together. In Jolt's ray tracer, I [patch the code](https://github.com/xxuejie/ray-tracer-on-jolt/blob/4b600e6337b2679d13af66dfc4cd724298dba9cc/tracer_src/camera.h#L24-L54) so image is written to Jolt's output region instead.

If you try the original example on native environment, a ~9MB image file will be generated:

```
$ make run-native IMAGE=full
clang++ -std=c++20 -O2 -ffp-contract=off  tracer_src/main.cc -o build/raytracer_native
./build/raytracer_native > image.ppm
Done.
wrote image.ppm (9120845 bytes)
```

Remember earlier that Jolt allocates 4096 bytes for outputs by default? This is certainly not enough for us. We increased the output buffer to 16MB in both the [Rust runner](https://github.com/xxuejie/ray-tracer-on-jolt/blob/4b600e6337b2679d13af66dfc4cd724298dba9cc/runner/src/main.rs#L11) and the [C++ guest program](https://github.com/xxuejie/ray-tracer-on-jolt/blob/4b600e6337b2679d13af66dfc4cd724298dba9cc/Makefile#L19).

In theory, this now works, but unfortunately it still breaks on my machine with 24GB memory:

```
$ make run-jolt IMAGE=full
```

This will not complete on my system with 24GB memory. An OOM error will be observed. This is due to the fact that Jolt now builds the entire `trace` of the program [into a Vec structure](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/tracer/src/lib.rs#L104). One can think of a `trace` as the entire execution of a RISC-V program. Executing each RISC-V instruction in Jolt VM creates a [Cycle](https://github.com/a16z/jolt/blob/672a9e7e212b2305003f17d71acec672a692c3b0/tracer/src/instruction/mod.rs#L438), a `trace` is just the collection of all `Cycle`s. Ray tracing is a compute-intensive task, even building the full resolution image natively on my machine takes ~30 seconds:

```
$ make run-native IMAGE=full
clang++ -std=c++20 -O2 -ffp-contract=off  tracer_src/main.cc -o build/raytracer_native
./build/raytracer_native > image.ppm
Done.
wrote image.ppm (9120845 bytes)
$ sudo perf stat ./build/raytracer_native > image.ppm
Done.

 Performance counter stats for './build/raytracer_native':

               536      context-switches                 #     17.1 cs/sec  cs_per_second
                48      cpu-migrations                   #      1.5 migrations/sec  migrations_per_second
               158      page-faults                      #      5.0 faults/sec  page_faults_per_second
         31,422.25 msec task-clock                       #      1.0 CPUs  CPUs_utilized
        81,283,573      branch-misses                    #      0.1 %  branch_miss_rate
    54,841,120,844      branches                         #   1745.3 M/sec  branch_frequency
   143,987,777,769      cpu-cycles                       #      4.6 GHz  cycles_frequency
   577,644,648,279      instructions                     #      4.0 instructions  insn_per_cycle
                        TopdownL1                        #     11.9 %  tma_backend_bound
                                                         #     13.2 %  tma_bad_speculation
                                                         #      2.3 %  tma_frontend_bound
                                                         #     72.7 %  tma_retiring

      31.430368173 seconds time elapsed

      31.387057000 seconds user
       0.006993000 seconds sys
```

~577 billion x86_64 instructions are executed to build the full image, significantly more instructions might be needed for RV64IMAC (lacking bit manipulation instructions). As instructions executed grow, the memory consumed by `trace` grows as well. On my 24GB machine, it is impossible to build a `Vec` holding all the `Cycle`s produced building a full resolution image. But theoretically the workflow is fine, so if you have bigger memory you can give it a try. For me, I have to try smaller images:

```
$ make run-jolt IMAGE=small

$ # The default IMAGE option is `small`.
$ make run-jolt
```

Smaller images will have smaller resolution (fewer pixels), fewer rays fired per pixel, fewer bounces per ray, less complexity in the scene. Those can also reduce the computation required to a smaller scale, needing fewer RISC-V instructions to execute, resulting in a smaller `trace`, so it fits in my 24GB machine. However you can tweak the [parameters](https://github.com/xxuejie/ray-tracer-on-jolt/blob/4b600e6337b2679d13af66dfc4cd724298dba9cc/Makefile#L32-L43) for your own test.

To test proving, I will have to try an even tinier image:

```
$ make prove-jolt IMAGE=tiny
```

There is a [plan](https://jolt.a16zcrypto.com/roadmap/streaming.html) in Jolt to reduce the memory requirements on `trace`. Perhaps one day we can build full resolution ray tracer image with much less memory. For now, at least we can verify that the pipeline already works.

# Profiling Jolt Guest Programs

Jolt does offer a simple [guest profiling feature](https://jolt.a16zcrypto.com/usage/profiling/guest_profiling.html), but I'm now spoiled by [pprof](https://github.com/google/pprof) or [samply](https://github.com/mstange/samply), where a decent visualized profiler allows me to dig into whole program running stats.

We mentioned earlier that Jolt builds the `trace` containing full executions of a program. While this is certainly a headache for bigger programs, it does expose program executions to us. It didn't take long for me to put together a profiler [module](https://github.com/xxuejie/ray-tracer-on-jolt/blob/4b600e6337b2679d13af66dfc4cd724298dba9cc/profiler/src/lib.rs), which takes Jolt `trace` then emits a profiler data file.

I use the same format from [CKB-VM's infrastructure](https://github.com/xxuejie/ckb-standalone-debugger/tree/samply/ckb-vm-pprof), so the profiler data can be fed to 3 different tools suiting different needs:

* Generate a flamegraph directly with [inferno](https://github.com/jonhoo/inferno).
* Feed into [pprof](https://github.com/google/pprof) for visualization.
* Feed into [samply](https://github.com/mstange/samply) for visualization.

To profile the program, there are some prerequisites:

```
$ # If you need flamegraph
$ cargo install inferno
$ # This fork of ckb debugger toolkit has support for samply as well
$ git clone https://github.com/xxuejie/ckb-standalone-debugger --branch samply
$ cd ckb-standalone-debugger
$ cargo build --release
$ # You will need ckb-vm-pprof-converter and ckb-vm-samply-converter from target/release folder.
```

Now you can profile the ray tracer:

```
$ PROFILE_FILE=profile.txt make run-jolt

$ # Build a flamegraph:
$ cat profile.txt | inferno-flamegraph > flamegraph.svg

$ # Convert into pprof format and run pprof:
$ ckb-vm-pprof-converter --input-file profile.txt --output-file profile.prof
$ go tool pprof -http 0.0.0.0:8000 build/raytracer profile.prof

$ # Convert to samply format and start samply:
$ ckb-vm-samply-converter --input profile.txt --output profile.json
$ samply load profile.json
```

Using pprof, we can show that 60% of all work is spent on `_muldf3` and `_adddf3` functions:

```
$ go tool pprof -sample_index=cycles -top -nodecount=10 build/raytracer profile.prof
File: raytracer
Type: cycles
Showing nodes accounting for 153462660, 85.22% of 180081350 total
Dropped 114 nodes (cum <= 900406)
Showing top 10 nodes out of 43
      flat  flat%   sum%        cum   cum%
  56762675 31.52% 31.52%   60686475 33.70%  _muldf3
  51928409 28.84% 60.36%   55945287 31.07%  _adddf3
  14798399  8.22% 68.57%   14798527  8.22%  memset
   5923630  3.29% 71.86%    5923630  3.29%  memcpy
   5445194  3.02% 74.89%   18402798 10.22%  vfprintf
   5122025  2.84% 77.73%   86110622 47.82%  :hit(ray const&, interval, hit_record&) const
   4617384  2.56% 80.30%    5252609  2.92%  sqrt
   3393207  1.88% 82.18%    3393207  1.88%  _divdf3
   2783023  1.55% 83.73%    7265416  4.03%  _fwritex
   2688714  1.49% 85.22%    3581298  1.99%  _floatsidf
```

It has been a recurring theme lately. In both the ported games from my previous posts and the ray tracer example here, `softfloat` has been the number one bottleneck. I can only expect this will be the case for the majority of games. Of course, switching to fixed-point math is indeed one solution, but can we do more than that? I'm actually thinking about this. I want to work towards a design, where we can have real [sophisticated 3D physics engine](https://github.com/jrouwe/JoltPhysics) (note there are 2 projects named Jolt: Jolt ZK VM and JoltPhysics, the 3D physics engine) running in a RISC-V VM (either direct execution or ZK), using floating point operations. The big question is how we can make `softfloat` fast, which will be the focus of my next post.

# Closing

Every ZK engine is different, they differ in VM semantics, they also differ in performance tradeoffs. It's quite fun diving into Jolt, comparing it against SP1 to see their differences and unique tradeoffs.

The journey also does not end with SP1 and Jolt. [OpenVM](https://github.com/openvm-org/openvm) from [Axiom](https://www.axiom.xyz/) is another interesting solution. With [first class extensions](https://docs-preview.openvm.dev/book/advanced-usage/creating-a-new-extension), or precompiles, depending on where we are coming from, OpenVM can be a versatile choice for different kinds of applications. For example: what if we run OpenVM on CKB? CKB-VM is already capable of running heavy computations, by building an OpenVM verifier on CKB-VM with custom extensions, how will we balance programs running in OpenVM and proved on CKB-VM, vs extensions that truly run on CKB-VM? This could be another interesting story to dive into.

In fact, when I was designing the whole experiment, I did consider OpenVM. I ended up with Jolt first, because Jolt utilizes 64-bit RISC-V registers now, while OpenVM for now is still on 32-bit registers. My future experiments would take full advantage of 64-bit registers, so Jolt is the natural one to start with. Given time, I'd love to try OpenVM to see how it works in practice, I'm also quite certain that all of that code would happily run on SP1 as well. It would be much fun to build on all those different VMs, exploring and comparing their performance tradeoffs, learning where each one is most suited.
