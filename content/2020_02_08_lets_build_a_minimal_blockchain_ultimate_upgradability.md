+++
title = "Let's Build a Minimal Blockchain 2: Ultimate Upgradability"
date = "2020-02-08"
+++

[Last time](../2019_10_21_lets_build_a_minimal_blockchain_dawn) I mentioned the very core of a blockchain: the block verification logic. This time, we will look at the bigger problem: everyone seems to be providing upgradable block verification logic, no matter it's called `runtime`, `module` or something else. But there's more to just block verification, how can we ensure the ultimate upgradability of a blockchain?

# Network Stack

The network stack in a blockchain is one component that typically receives the least amount of changes after launch. It is usually left there unchanged, following "if it ain't broke, don't fix it" principle. Some of the reason might be compatibility needs, other reasons might also include security, etc. And when there is a change needed, you might encounter release notes [like following](https://bitcoin.org/en/alert/2018-09-21-required-upgrade):

> You should not run any version of Bitcoin Core other than 0.16.3. Older versions should not exist on the network. If you know anyone who is running an older version, tell them to upgrade it as soon as possible.

Different people would have different interpretations here, many would argue this is not a problem. But personally I'm not so sure on this: manual intervention is required here to download the latest version of Bitcoin and upgrade the current version. For large organizations with sophisticated ops team, this might seem transparent. But for the many of us running nodes in home computer, manual invervention, while might be easy most of the time, is still work required. In addition, to people who just want a [plug-n-forget node](https://keys.casa/lightning-bitcoin-node/) running Bitcoin helping his/her business, manual work is always a hurdle. I know many will have different opinions but to me, this is some sort of "fork", cuz forks, when looking from the ordinary eyes of end-user, is just upgrading to a newer version of software, which is no different from what the above release note requires people to do.

I'm not sure if this question is useful, but I have never seen people raising this question so I want to do it here: is it possible to have a blockchain node that can transparently upgrade network stack(and hopefully many other parts) without restarting the node? Can we truly have a piece of blockchain software that runs forever?

First, I think we should talk about a totally different issue:

# Native Languages vs Image Based Languages

I don't usually care for programming languages. I believe we do have far too many programming languages, many of which are only differs in the superficial syntaxes. But looking beyond that, there are still several different unique types of programming langauges, and the choices between them can make quite a big difference.

In recent years, native languages, such as Rust, Go, Elixir are starting to make their revenges. With the development of type inference algorithms, native languages start to gain some of the benefits of dynamic languages, while at the same time providing better stories in terms of performance, as well as code maintainability. This is indeed an advancement in a sense, but on the other hand we are also losing one unique possibility that is (at least till now) only feasible in dynamic languages: the ability to alter code on the fly.

While many of the toy grade dynamic languages do not offer this feature, almost hidden in the history there is a unique branch of programming languages named `image based languages`. The way they work, is that a runtime environment is started first, then the environment could be used to run different applications, even new applications deployed on the fly. What this means, is that while some code could be packed together with the runtime environment (called an `image`) to boot together, more code could be added on the fly which alter the application behavior. This means unlike a native language, an image based language could be used to provide upgradability.

Unfortunately, most image based languages have either been a lost art or only filled in a niche environment. It is really hard to find an industry grade image based programming language that is not only used by die-core lovers, but I think we do still have one available.

# BEAM!

Now we are coming to the topic of this talk! I personally believe BEAM, which is the VM powers [Erlang](http://erlang.org/)/[Elixir](https://elixir-lang.org/), can be a perfect fit for building blockchains. We have continuously talked about how we feel blockchains are exactly like hardware. Well it turns out BEAM has been used for years to build software for hardware that never stops, such as telephone switches. When putting into the best use, I do feel BEAM will have unique advantages for building blockchains:

## Network stack

Believe it or not, the original use for Erlang, is telephone switches with relays voice data from one wire to one of many other wires. If we wrap our head a bit, I personally feel this is exactly what the network stack in modern blockchain does:

* You are maintaining a series of connections with other peers, telephone switches do that, check;
* From time to time, you receive a transaction/block, and wants to relay it to one or many different other locations, telephone switches do that and they even do something more: they have real-time requirements, check;
* You do want to minimize the downtime when it happens, telephone switches usually have legal contracts preventing downtime, check

Besides those points, there are actually more that can be brought by BEAM:

### Zero Downtime

As mentioned above, telephone switches usually have legal contracts preventing downtime, they have to do hot upgrades with no downtime, which provides the exact benefit that we can upgrade the network stack of a blockchain, when powered by BEAM.

In fact our requirements might not be as harsh as telephone switches, we could tolerate slight downtime, all we need to do is reduce manual human interventions. So we can do something simpler here:

* In the initial handshake protocol, each peer includes its own protocol version;
* When a peer using a higher version protocol notices a lower version protocol, it sends the new upgraded network stack code to the other peer;
* When the peer with lower version protocol receives and validates(possibly via signature verification) the code, it reloads it current network stack, and runs the upgraded network stack

This means a reconnection might be needed when a node is upgrading its own network stack, but at least we are cutting the human intervention, and those who are really annoyed by this are well welcome to implement the full Erlang hot upgrading protocol, resulting in a real zero downtime upgrades.

### Fairness

A telephone switch doesn't run only one telephone line at a time, it runs numerous telephone lines simultaneously, and all of them should function smoothly without delays. That's why BEAM treats fairness as the top priority when scheduling code running on it. It ensures all parts of the code gets a fair chance to run. This might sound counter-intuitive at first but it actually suits a blockchain stack quite well. Let me explain.

In the network stack of many blockchains, there is an IBD(Initial Block Download) mode, and a normal mode. This is because when a node initially starts to sync, it needs to grab a lot of blocks, and we have to handle it specially, so it won't affect other peers currently in a network. With a fairness scheduler, we might be able to simply the code, so a network stack without IBD can still handle initial node syncing as well as normal block syncing in a fairness way. Note this might be possible in other stacks, but the thing is: if we have a well-designed foundation that has this property developed and tested for years, why not embrace that instead of rolling one on our own?

## Block validation logic(and others)

People who know Erlang/Elixir well might start to object me: but Erlang/Elixir is slow in modern blockchain's standard! You might never have a fast modern blockchain built with Erlang/Elixir!

I totally agree with that, that's why I believe the futures lies in a hybrid stack between a network stack via BEAM, and a native, fast language such as Rust that can unleash all potentials of a computer. BEAM is slow indeed, but the other side of story, is that network stack should never take a huge portion of the CPU time in a well-tuned application. I would personally argue 5% of the CPU time is well enough to perform all the networking stack in a modern blockchain, even when we are using Erlang/Elixir running on BEAM. You could use Rust however you want to unleash the beast in your computer for maximum blockchain performance.

And yet there is still a way to ensure upgradability when using native Rust code:

* BEAM does provide a [way](http://erlang.org/doc/man/erl_nif.html) to perform upgrades on native code it uses. This means even though we are packing our block validation logic(and possibly many other parts, such as storage) in native code, it is still possible to perform hot upgrades on the native part without restarting the whole node. This means it's easy to implement things like "when the block number reaches 600000, we will start using the new block validation rules", and this could all work without any restarts to the whole application, a blockchain node can perfectly run forever as long as it needs.
* There will be people who are frightened by the need to dynamiclly run native code, or people who want to leverage more than one CPU architecture. It's perfectly possible to leverage techniques mentioned in the [previous post](../2019_10_21_lets_build_a_minimal_blockchain_dawn): one can pack the core block verification logic in RISC-V, and runs it in a CKB VM instance. That means for the most of the time, all you need to do, is upgrade the program running in the VM, you don't have to touch the dangerous action of upgrading a whole module written in native code. This whole process still works.

# Ultimate Upgradability

People who know me will know that I'm a Gopher fan, and there was a time that I used to believe Go can be a quite decent fit for building blockchains. But lately I stopped thinking that way, I believe the future of blockchains lies in a hybrid solution between a BEAM powered network stack, and a native code module written (possibly) in Rust. The result here, will a blockchain that can truly runs forever without needs for any forks.

And it's actually not about forks, it's just about minimizing human interventions. If I'm just a merchant using Bitcoin to accept payments, why should I care about forks? As long as bitcoin continuously works for me, I am not worried about how many forks it performs underneath. Right now people worries about forks since forks require them to upgrade their software at a certain time frame, if a blockchain supports transparent, seamless upgrades, I wonder if forks will still be so hard to perform.

Some might call this imaginary features, but we are in a very early phase of the field, and we are seeing people throw the old blockchains and start from new all the time. Who knows the stack we have today will work tomorrow? Personally I believe that is a future that is worth to explore more.
