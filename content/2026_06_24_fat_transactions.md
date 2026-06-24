+++
title = "Fat transactions, thin transactions"
date = "2026-06-24"
+++

We talk a lot about VMs. This time, I want to expand to a different-yet-related topic.

# ISAs resemble each other

We used to fight on [ISAs (instruction set architecture)](https://en.wikipedia.org/wiki/Instruction_set_architecture) for VMs, we still do. I embrace RISC-V, primarily because it stays frozen. It has a small core everyone agrees to, frozen for decades, yet it is still capable of pushing innovations. New software and optimizations continue to work on the small core.

That said, RISC-V does have quirks: almost everyone is avoiding CSR instructions in software VMs. `jalr` is also painful to implement in a high-performance JIT. Some [design around it completely](https://github.com/jarchain/jar/blob/ce3fa4d0c269356301327bff62fee56d56a40231/website/content/spec/javm.md#how-pvm2-relates-to-rv64e).

On the other hand, WASM has nicer properties for static formal analysis, cleaner structured control flow, and natural resistance to [ROP attacks](https://blog.cryptape.com/against-rop-attacks). However, because the broader WebAssembly ecosystem serves browsers and many non-blockchain use cases, reaching agreement on a small, frozen blockchain-oriented WASM profile is harder than it looks.

There are other VMs as well, each with its own goodies and quirks. We have yet to see one ISA solving all the problems. I still prefer the simplicity of RISC-V in CKB the L1 blockchain. But I know others disagree, based on preferences or different environmental requirements.

Surprisingly, if we look past ISA, optimizing VMs resemble each other greatly. It's like climbing Mount Everest from different routes, each has its own ridges and obstacles, but climbers near the summit often rediscover similar techniques. All of us are trying to minimize VM overheads, deferring more operations to native x86_64 or aarch64 instructions. Frequently, more instructions are introduced at the higher level ISA to mimic similar native instructions from x86_64 or aarch64 CPUs. One famous example is [count leading zero](https://en.wikipedia.org/wiki/Find_first_set).

# VMs need more than just ISAs

ISAs are just like the route one picks to climb, it dictates the journey. But you still have choices:

* Do you carry oxygen?
* Do you use guides, and which guide is your choice?
* How do you plan different stages?

Similarly, blockchain VMs, and also VMs in other use cases as well, have choices apart from ISAs:

* How long can you run a program? How will you meter it?
* How much memory is available per program?
* How can you interact with outside environments, such as fetching inputs?

Those choices are deeply buried in blockchain designs, and you might be surprised how much they can differ from one blockchain to another.

## Common Operations

VMs are different, ISAs vary. Yet at the core of almost every performant virtual machine, the same set of *common operations* exist:

* 64-bit integer operations, such as addition, subtraction, multiplication, division, shifting and other bit-manipulation techniques.
* Memory loads & stores.
* Unconditional jump and conditional branches.

They exist in every efficient ISA, in different formats, different encodings. But the core features are strikingly similar. They also consume the majority of the running time of every program. Fundamentally, modern CPUs are architected using those operations, it is only natural that VMs seeking performance build ISAs with matching instructions, so as to reduce overhead.

In a not-very-accurate way, the number of *common operations* executed, represents the complexity of a program. There are exceptions of course, we will get to that later.

```
| Transaction Type | What it does                            | Rough # of Operations  |
|------------------|-----------------------------------------|------------------------|
| Transfer         | Move tokens from one account to another | 100 - 1,000            |
| Swap             | AMM number calculations, transfers      | ~500,000               |
| Crypto Algorithm | Verify signatures, calculate hashes     | 1,000,000 - 20,000,000 |
| Teeworlds        | 50Hz game logic                         | ~80,000,000            |
```

Here are rough estimates of *common operations* executed, for different kinds of programs on Nervos CKB.

While all of them sure have limits, different blockchain environments have different limits on operations (most of which shall be *common operations*) allowed in a single program:

* Nervos CKB has a limit of 3,500 million `cycles` in a CKB block. In the extreme case, a block can only have one transaction, consuming all of the 3,500 million `cycles`. *Common operations* on CKB range from [1 - 30 cycles](https://github.com/nervosnetwork/rfcs/blob/master/rfcs/0014-vm-cycle-limits/0014-vm-cycle-limits.md#instruction-cycles). In the worst case, this maps to 116 million *common operations*.
* Arbitrum has a limit of 32 million `gas`, or 320,000 million `ink` per transaction. *Common operations* in Arbitrum WASM-based [stylus](https://docs.arbitrum.io/stylus/gentle-introduction) contract, range from [1 - 1000 ink](https://github.com/OffchainLabs/nitro/blob/6dce8d13902649a1acdfd3f2504129f1f5612358/crates/prover/src/programs/meter.rs#L363) with the exception of popcnt. In the worst case, this maps to ~320 million *common operations*.
* Solana has a limit of 1.4 million `compute units`. Common operation consumes [1 compute unit](https://github.com/anza-xyz/agave/blob/f9ec90a60cf52df1aaca81168e43030f57746d6c/program-runtime/src/invoke_context.rs#L103). This means 1.4 million *common operations* can be executed in one Solana transaction.

There are more examples, but a pattern already emerges: blockchains all using performant VMs can still have two orders of magnitude difference, in their allowed *common operations* per transaction. There is no right or wrong, only design tradeoffs. I'm sure those blockchains designed with lower *common operations* have a reason, maybe they want to minimize latency. But problems can arise (or not), depending on the programs you are building. For swaps, lower limit is fine; if we want to architect large-scale on-chain games, having more *common operations* to spare surely is a win.

And of course those numbers are rough, they are not perfectly comparable to each other. I merely use those numbers as hints on how different transactions from different blockchains can be.

### Caveat: Precompiles

Some VMs, especially blockchain VMs, tend to introduce precompiles, or system contracts, whatever they may be called, so complicated algorithms become one instruction. Typical examples include signature verification (`ecrecover`), or hashing (`blake2b`).

That being said, **common operations** still largely rule in the presence of precompiles. More complicated programs typically have more **common operations**. Precompiles solve some of the problems, but not all. One example is that precompiles do not really help when we build game logic for on-chain games.

### A different bet: EVM

EVM took a different architectural bet than RISC-V, WASM, eBPF and similar ISAs. It was designed around 256-bit integers, fitting cryptographic operations it cares most about, such as field elements, hashes, etc. The bet is that a good compiler can optimize general purpose operations to be fast enough. EVM based programs do not share the *common operations* described above, instead they utilizes 256-bit operations exclusively. A direct apples-to-apples comparison is thus not possible, we will have to see if the 256-bit-everywhere wager materializes.

I know many talented people are working on this, maybe we will see it works well one day. Personally, I have my doubts. It reminds me of [auto-vectorization](https://en.wikipedia.org/wiki/Automatic_vectorization). For years, we believed compilers would automatically vectorize sequential code to keep modern SIMD units fed. In practice, Apple [proves](https://en.wikipedia.org/wiki/Apple_M1) that sequential code still rules.

## Memory & IO Limits

Other differences also exist. Memory is the first noticeable one:

* Nervos CKB gives each program 4MB memory space to execute. Tricks like [spawn](https://github.com/nervosnetwork/rfcs/blob/master/rfcs/0050-vm-syscalls-3/0050-vm-syscalls-3.md#spawn) do offer ways to use even more memory.
* Arbitrum allows a [growable memory](https://docs.arbitrum.io/stylus/concepts/vm-differences#wasm-memory), which is only capped by the gas limit you pay for it.
* Solana has a [256KB](https://solana.com/docs/core/programs#limits) heap, and also a maximum of 256KB stack (4KB frame with 64 call depths).

Input data size is another one:

* Nervos CKB has 512KB limit on a transaction. By compacting cells to use, one can fit close to 512KB of input data to a transaction.
* Arbitrum has [117.964KB](https://docs.arbitrum.io/for-devs/troubleshooting-building#i-tried-to-create-a-retryable-ticket-but-the-transaction-reverted-on-l1-how-can-i-debug-the-issue) limit on transaction size. It still allows one to pass over 100KB input data to a transaction.
* Solana uses a limit of [1232 bytes](https://solana.com/docs/core/transactions) for its transactions. This fits a transaction inside a [MTU](https://en.wikipedia.org/wiki/Maximum_transmission_unit).

Please understand I'm not writing this post to bash Solana nor EVM. Each of them is really successful in its own territory, and well deserves respect. That being said, designs have tradeoffs. Maybe on-chain games lean towards the other side of the tradeoff.

# Fat Transactions

I'm coining the phrase `fat transactions` to represent blockchain transactions that:

* Execute >100 million *common operations*
* Require megabytes of memory
* Require >100 KB input data

I have to say the exact numbers might vary, but I want to use the term `fat transactions` to refer to transactions with heavy computations, need more resources so as to run. Teeworlds falls exactly into the `fat transaction` category, where a 50Hz, real-time multiplayer shooter game is validated on chain, costing ~80 million *common operations* for one-minute gameplay. While Teeworlds does not run into memory issues, my later games do push the memory requirements on CKB-VM to the limits, more on this later.

On the other hand, `thin transactions` refer to transactions that fit in an MTU, take a few thousand *common operations* to finish, and can work with <100KB memory.

There is a big middle ground between `fat transactions` and `thin transactions` I'm not touching. I don't know where the exact line lies.

Fintech applications fit perfectly in the `thin transaction` category. Solana pioneered this space, and there are also other low latency blockchains catching up to compete in this space.

I don't deny this is an important use case. In fact, I yearn to see a blockchain replace [SWIFT](https://en.wikipedia.org/wiki/SWIFT). I'm just pointing out that we should distinguish `fat transactions` and `thin transactions`, different designs serve each of them well. While the `thin transaction` space has been quite explored (if you look around, I bet all TPS games now play with `thin transactions`), we should also look into `fat transactions`, see what becomes possible.

## MTU, Batching

It is a thing to design a transaction to fit in an MTU. I first saw this in Solana, some other blockchains share the same design. It surely helps minimize latency, which can be important for fintech.

There are cases you need to break the limitation. Solana introduces [chunking](https://solana.stackexchange.com/questions/18861/solana-program-deploy-tips) to deploy contracts that are bigger. A similar design is also introduced to [Arbitrum](https://forum.arbitrum.foundation/t/implement-an-enhanced-version-of-eip-7954-on-arbitrum-to-raise-contract-the-size-limit-to-at-least-64kb/30428) to allow bigger contracts.

This trick works for occasional tasks such as program deployment, but for daily operations, having hundreds of transactions to do one task can be a nightmare. Even Solana has a [proposal](https://github.com/solana-foundation/solana-improvement-documents/blob/main/proposals/0296-larger-transactions.md) to introduce larger transaction. If your blockchain is still only designing for MTU limit, I recommend thinking again :P

# Zero Knowledge VMs

In a way, I consider zero knowledge VMs a new form of computing machine, just like [vector machines](https://en.wikipedia.org/wiki/Vector_processor), [multi-core processors](https://en.wikipedia.org/wiki/Multi-core_processor), [cache-aware CPUs](https://en.wikipedia.org/wiki/Data-oriented_design), and [modern GPUs & TPUs](https://en.wikipedia.org/wiki/Tensor_Processing_Unit). It has its own tradeoffs and quirks:

* Out-of-order execution, superscalar, cache just do not exist.
* Locality has different meanings.
* Branches are not free, lookups in some designs can be near-free.
* Multiplication / division have a cost similar to addition / subtraction.
* Proving cost dominates, execution only runs once.

This means writing software for ZK VMs will be drastically different compared to current machines. It has the potential to be one fascinating area to study.

This is also where ZK VMs become relevant to the distinction between `fat transactions` and `thin transactions`. ZK VMs can offer a solution so blockchains for `thin transactions` can work with `fat transactions`. By executing off-chain and proving on-chain, ZK VMs enable `fat transactions`, allowing blockchains to focus on `thin transactions`.

For some use cases, this definitely helps. But while ZK is interesting enough, I wonder if ZK VMs will be the only path in the future. Some cases might work better when simple re-execution still works, enabling a simpler architecture and lower cost.

I also have a suspicion here: it's quite possible re-execution might always remain cheaper than ZK proving. Common belief is that proving costs will drop as hardware, algorithms and implementation progress. However, some of those same advancements as progress from other areas might accelerate direct VM execution as well. ZK will get cheaper over time, so will raw VMs. That being said, I'd be glad to be wrong about ZK VMs.

We will just have to wait and see how the future looks.
