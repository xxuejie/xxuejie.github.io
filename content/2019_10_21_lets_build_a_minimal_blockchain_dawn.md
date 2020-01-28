+++
title = "Let's Build a Minimal Blockchain 1: Dawn"
date = "2019-10-21"
+++

This will be a different series from `Introduction to CKB Script Programming`, so if you are more keen on CKB scripting, feel free to skip this one. But if you are interested in blockchain in general, this could also be an interesting one :)

So it all started from an inception: if we look at current generation of blockchains, they are all rather complicated. Bitcoin is quite complex, Ethereum is even more so. And while CKB is (arguably) simpler than Ethereum, it's still way more complicated than Bitcoin(but in a good way!). Coming from a [different background](https://www.youtube.com/watch?v=tXVr2E1vfmk), I couldn't help but wonder: is this level of complexity necessary? Is blockchain just so different, or are we deep down the mud of [accidental complexity](https://www.youtube.com/watch?v=rI8tNMsozo0)? Regardless, I'd like to find out the answers.

While simplicity is a debatable question, there're other parts of modern blockchain space that more likely need work. One particular problem, is monolithic. It's very rare that a blockchain let's you swap one part of it for a different implementation. For example, while [alternative networks](https://www.mail-archive.com/bitcoin-development@lists.sourceforge.net/msg03189.html) might be possible, they are still in the minority, some already abandoned. Most other blockchains do not even have a second syncing protocol. While one could argue syncing protocol could more or less related to the security nature of one blockchain(which I still have my doubts), let's look at one other component: why do I need to run a full transaction pool on my node? I'm neither an exchange or mining nodes on my own, can't I just have a node that runs only necessary components, and rely on external services when I do need to send a transaction? Even when I have a transaction pool, it merely just relays transactions to other nodes, the transactions need to reach a mining pool before it can be mined, so why bother wasting resources on one's own machine?

Looking further, there's additional problems that don't get good answers: blockchains will be updated, whether you call it soft-forks or hard-forks, the inevitable result is that you have software that behaves differently based on the exact blocks you are processing. And slowly, your same codebase will be scattered with logics that behave differently across time, and it will be a pain maintaining such a codebase and all the knowledge in your head. Can modern software engineering [help](https://vimeo.com/108441214) with this?

That brings us to this series: if we start freshly from a different angle, refine our scope carefully, what a minimal viable blockchain is gonna be like?

I did some thinking on this problem, and to answer the above question, let's back off a bit and think about this simpler question: what's the crucial part in a blockchain?

Personally, I believe the answer is merely the block verification logic. Literally everything else is just optional, you absolutely do not need a transaction pool, the syncing protocol could also be omitted as long as there's a way to gather blocks. Miner, RPC, etc. can be someone else's problem. Really at fundamental level, a blockchain only needs the block verification logic so as to function.

Starting from there, we can build a blockchain core that verifies blocks. All it does, is accepting blocks, then signaling either new block updates, or fork switching. From there, we can build the surrounding tools all as plugins, such as syncing clients, transaction pools, miners, etc. There's no need to have a single solution for each tool, as long as something works for its designed use case, it will be useful in this rich ecosystem. For example, mining pools might want to have priority syncing for blocks, while exchanges would want to optimize bandwidths for transactions.

But that only answers one part of the problem, what about building maintainable blockchains? The root conflict here, is what we want our software to evolve, different logics are grown to handle blocks from different time. If we look carefully, there's actual one construct in modern blockchains designed to cope of the evolution of time: virtual machines are used to enable new behaviors for tomorrow's applications, but right now, virtual machines are mostly limited to transactions. What if we expand virtual machines to process the whole block? Will that bring any difference?

And before you ask, yes of course, part of my inspiration comes from [substrate](https://substrate.dev/) and [solri](https://solri.org/), but as the author of [CKB VM](https://github.com/nervosnetwork/ckb-vm). Both substrate, and its choice of WASM feels needlessly complicated. While solri is a huge improvement over substrate, it's still an on-going experiment, and part of me feel that we can aim at a more flexible runtime than solri. Hence I've come up with the initial scope of the still unnamed minimal blockchain:

* A block is just a series of bytes, the blockchain itself knows nothing about the block, not even its block hash.
* A program running in CKB VM is in charge of validating and accepting a new block.
* A transactional key-value interface will be provided to the program running in CKB VM for persisting data.
* The core shall only need to provide a pub/sub interface for new block updates as well as fork switching.

The beauty of this scheme, is that any handling of soft/hard forks, will just be simply swapping the program used the validate the blockchain. And your new program could be perfectly containing only logics for handling new code. There's no need to persist old code forever in your codebase. Just like the first time you are reading [SICP](https://mitpress.mit.edu/sites/default/files/sicp/full-text/book/book-Z-H-5.html#%_chap_Temp_2): pyramids are magnificant but static for thousands of years, but what you want is organisms which is chaos in a way but evolable for billions of years to come.

One stretch goal I want, is an [Arrow](https://arrow.apache.org/)-style interface where zero copy streaming protocols can be encouraged. Serving blocks to other clients should never be consuming much resource from the sending end. Hopefully this can contribute to better network performance, cuz quite often block syncing is the slow part in modern blockchains.

Notice I never mentioned whether this is a PoW or PoS blockchain, cuz that question really doesn't make sense: first, while the title says `Build a Minimal Blockchain`, this really is not about building a blockchain, it's about building a set of tools that can make blockchains built with it simpler, more flexible and easily maintainable; second, since a program running in virtual machine handles blockchain verification, you are not limited to one side of the world! This could easily support an alternative implementation of permissionless PoW blockchains such as Bitcoin, Ethereum, or CKB; this could also be adapted to layer 2 PoS blockchains running together with Nervos CKB. It really is up to the programs to say what the current blockchain is.

So that's it for the introductory post, I really don't know how this idea will go, I could be wrong and this could total fail, but one thing I could be sure, is that this surely will be an interesting voyage, I just hope this won't take that long as the [voyager](https://voyager.jpl.nasa.gov/mission/status/) :P