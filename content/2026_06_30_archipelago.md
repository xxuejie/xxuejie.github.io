+++
title = "Archipelagos: Exploring On-Chain Game Design for OHOL"
date = "2026-06-30"
+++

We managed to run the core game loop of [One Hour One Life](https://onehouronelife.com/) (OHOL), a game I deeply admire, on CKB-VM in my last post. This came with compromises, the most noticeable being that we had to introduce [archipelagos](https://en.wikipedia.org/wiki/Archipelago), limiting each deployment on CKB to 256x256 tiles and 64 players.

But blockchains do not just impose limits, they also open up new game design ideas worth exploring. Simply shrinking the map and player count wouldn't be enough on its own to keep the game fun. In this post, I'll walk through some game design ideas that build on what blockchain has to offer.

**Disclaimer**: I'm not a game designer. I played a lot of games as a kid, and have been a loyal [spectator gamer](https://medium.com/@ADSRelease/spectatorship-and-video-games-77c6d0c37711) in the past few years. My experience is limited to [Will Wright's Game Design Course](https://www.masterclass.com/classes/will-wright-teaches-game-design-and-theory), hundreds of episodes of [Extra Credits](https://www.youtube.com/@extracredits), and a bit of dry thinking myself. There is a good chance I will end up describing something that has been tried, or something that's plainly wrong. If something I wrote makes you roll your eyes, please feel free to [email me](mailto:xxuejie@gmail.com) or [tag me on X](https://x.com/xxuejie), I promise I'd be happy to learn more.

# Port: Connecting Archipelagos

In CKB the blockchain, we are free to create many archipelagos. Each archipelago will be managed by a [CKB cell](https://docs.nervos.org/docs/script/script-testing-guide#cell-structure). One can think of a CKB cell as being like a [UTXO](https://en.wikipedia.org/wiki/Unspent_transaction_output) in Bitcoin, with the exception that cells in CKB store data more easily. Essentially, there could be many servers running many archipelagos for many players all on a blockchain. We just need different archipelagos to connect to each other. We can call the CKB cell for an archipelago a `game cell`.

![Port in pixel art](/images/port.png)

*Source: [https://easy-peasy.ai/ai-image-generator/images/hello-create-an-image-1760a20d-eda1-4b64-817e-76aed653bff3](https://easy-peasy.ai/ai-image-generator/images/hello-create-an-image-1760a20d-eda1-4b64-817e-76aed653bff3)*

We can introduce `port` to each archipelago then. As a special object (likely) placed near the edge of an archipelago, `port` enables 2 new actions:

* A player can enter a port carrying a few selected items.
* A player can send some goods into the port, listing items they wish to receive in exchange.

In a way, this is like when someone boards a ship at a port. The player / goods entering the port are thus removed from the current archipelago. The CKB cell for the archipelago no longer stores state for the removed player / goods. Instead, a standalone CKB cell (we can call this cell a `transit cell` for now) is created to hold the player / goods. Later, another archipelago can consume the created `transit cell`, moving the player / goods into its own `game cell`. The player can now play in a new archipelago, experiencing different game lands. Similarly, goods can also be exchanged between different archipelagos for trading.

Archipelagos are small (256x256 tiles), but we can make each archipelago with a theme: one might be rich in forests, another could be full of iron. Some might like deserts with a lot of gold, while others could have many waterways. I actually built a `map baker` that constructs archipelagos in a certain way: the center has abundant basic supplies such as food, stone, fur, etc. The outer area of each archipelago will be built around a theme, so it's rich in one resource, such as forests, water, iron, etc. Themes vary from one archipelago to another, in a [RNG](https://en.wikipedia.org/wiki/Random_number_generation) determined way. We can port the `map baker` (it's not a hard thing at all) to CKB-VM, so the map is created on-chain as part of creation of the `game cell` for the archipelago. Blockchains can provide a seed for the RNG. Luckily, we're fine with a seed that is `reasonably secure`, we don't need it to be `cryptographically secure`, when people don't like a map they can just retry to get a new one.

Following this design, we get plenty of archipelagos, each with different themes and its own tricks to play with. All archipelagos are also connected in a way. People won't feel very isolated.

## Customs: Where Signatures Come In Handy

I remember OHOL tried [500x500 tiles](https://onehouronelife.com/forums/viewtopic.php?id=6715&p=2), or [private villages](https://store.steampowered.com/news/app/595690/view/699890007742088725) so friends can have private play sessions, avoiding griefers. Archipelagos naturally separate one group of players from another. But with connected design, we will run into the same problem: what if one just travels from one archipelago to another, behaving extremely bad in each one of them?

Building on the idea of `port`, we can add `customs`. An archipelago can be configured so joining via `transit cells` requires approval. On a blockchain, `approvals` fundamentally come in the form of `signatures` ([state channels](https://ethereum.org/developers/docs/scaling/state-channels/) or [ephemeral rollups](https://arxiv.org/html/2311.02650v4) might delay signatures a bit but eventually there will be signatures). Some archipelagos might be `pirate lands` where anyone can join, and any goods are accepted. But most archipelagos will probably have some form of protection, where one or more `customs inspectors` check incoming players or goods, and accept only selected ones to ensure proper gameplay.

This way we get (or at least try to get) the best of all worlds: reasonably sized `archipelagos` that fit on-chain, `ports` so archipelagos are connected, and `customs` so archipelagos are safer from griefers.

It's also worth noting that in my OHOL port I have left out the [curses](https://onehouronelife.fandom.com/wiki/Curse) system, hoping the combination of `archipelago` and `customs` will be enough to handle griefers.

## Tutorials Stay Local

Just like OHOL handles tutorials separately, in the port we can also build tutorials as a local-only thing. One can play tutorials on one's own, getting a feel for the game. When one is ready, the tutorial can finish by building a `transit cell` on the CKB blockchain, the player can then officially start the voyage in an archipelago.

# History: Every Island Has Memory

Now let's dive into what a blockchain has to offer to games.

A public blockchain exposes all user interactions. This is both a blessing and a curse: with the exception of ZK, one cannot hide one's own actions; but with publicly available data, everyone is free to dig into history and look for patterns. For truly on-chain games, one should be able to gather all player inputs on-chain, and replay a game countless times, observing how players reacted to events. I actually did this in the Teeworlds port. I didn't do it for the OHOL port but it is something totally doable.

There are 2 particular advantages I think blockchain has to offer:

## Every Life Is Remembered

I actually talked to a friend when I was thinking about porting OHOL to CKB. As a casual gamer, she became fascinated when I talked to her about the design. After digging more into the game, she found it so intriguing that she wanted her child to play it, experiencing first-hand how valuable life is. Every time you play the game, you leave a mark in the world, letting others know you have lived, explored, and contributed to the world. In a way, OHOL feels more than just a game.

Blockchains actually amplify this: in typical MMORPGs, there are server stats, brief histories (e.g., [family trees](http://lineage.onehouronelife.com/server.php?action=front_page) are kept by OHOL which is already really nice), some might have recorded YouTube videos. But a blockchain enables every life to be treated equally: you can dig into blockchain histories, replaying the lifespan of every player across every generation. You can experience again how they grow up, what they find, what they build, and sadly how they pass away. I have memories of playing games as a kid with my parents and relatives, and I believe those memories would be amplified if I could dive back in and see how we used to play.

Maybe this is just me being nostalgic, but I wonder if there are others like me.

## History As A Guard Against Griefers

We talked earlier about how `customs inspectors` decide whether players / goods are accepted into the current archipelago. But we haven't decided how. Goods might be simpler, one just accepts what they need, in exchange for what they can afford. But it's hard to determine whether a player is a griefer just by looking at their stats and carried goods.

You might have realized this already: public replayable histories in blockchains allow us to look into a player's last plays, which can offer insights into the player. In real life, we also frequently rely on a person's past behaviors to predict their future actions. Even if a griefer hides well, they will probably only have the chance to cause damage in one archipelago, before everyone rejects their `transit cell` in future archipelagos.

And it's entirely possible that a griefer might change their identity (private / public key pair in blockchain terminology), and act like a decent person. But given this `scrutinizing history` design, people will be cautious about identities without prior records. It might be troublesome for completely new players (we might want to build some special `archipelagos` to help new players grow into decent histories), but in general such a design might help honest players, and they can enjoy the game more easily with fewer griefers.

# Why Must Every Island Run the Same Laws?

I'm sure most players have been there: you enjoy a game, play it for a while, and then one day, the developers change some rules. Some players are not used to the new rules, complain and struggle to adapt. Some leave, some adapt and stay.

I believe many game developers have experienced the same situation on the other side of the coin: they want to evolve the game, with careful thinking and countless nights of hard work, hoping to make the game better. But with the features rolled out, players received the change differently than the developers had hoped. They had to explain how the new features were designed, and some eventually end up rolling the changes back.

To explore more here, what if a game offered one set of tweakable rules, and players were free to choose exactly which variant they wanted? This might be doable in a single-player game, or a local LAN-based multiplayer game. But in an MMORPG, this is slightly trickier to do. With archipelagos in the OHOL port (I really should come up with a name for this project), it becomes easier. Every archipelago is free to use a different rule set: some might want different families to have [different specialties](https://www.onehouronelife.com/forums/viewtopic.php?id=10369), others want each character to be able to learn [only a finite number of tools](https://onehouronelife.com/forums/viewtopic.php?id=8197) they can use in one lifetime, and still others might want [language barriers](https://steamcommunity.com/app/595690/discussions/0/4293692116960989110/).

Those are real directions that have been tried and discussed in OHOL over the years, with mixed reception. That makes sense: a single shared world has to commit to one set of rules, while players have different preferences. What if, instead, each archipelago could make those decisions for itself? Different archipelagos can still connect to each other: accepting players, trading goods. But each is free to function as it wishes. `Customs` and replayable histories actually play larger roles with this diversity: most archipelagos might want to avoid trading goods with a particular one that has modified its game logic to mint gold day and night.

## Multi-VM, Multi-Chain

This isn't strictly gameplay-related, but we can actually go further. With varying game logic, different `archipelago`s already run on different game code, having different behaviors. We can expand this to different VMs, and even different chains as well: fundamentally, the following choices should all work:

* Different code running on the same VM, the same chain
* Same / different code running on different VMs, the same chain (practically unlikely, but theoretically possible)
* Same / different code running on the same VM, different chains
* Same / different code running on different VMs, different chains

Assuming a cross-chain communication solution like [Chainlink](https://chain.link/) is used, we could have one `archipelago` running on RISC-V based CKB-VM on CKB, trading with another `archipelago` running on the WASM VM on Arbitrum, or have a player move from an `archipelago` powered by [SP1 ZK VM](https://github.com/succinctlabs/sp1) on Solana back to one running on CKB. The OHOL-like universe could span `archipelagos` across different chains (think of them as continents).

# Two-Dimensional Time

Before diving further, I should mention something: this is the most controversial idea in this post. Some might like it, or it might not work out at all. Regardless, it should be fun just to discuss it.

With the exception of [savescumming](https://en.wikipedia.org/wiki/Saved_game#Savescumming) and rewinding supported in some games (like the [Forza Horizon](https://en.wikipedia.org/wiki/Forza_Horizon) series), most games run in a linear timeline. You cannot go back in time to return to an earlier game state. This is especially the case for modern MMORPGs. On-chain games, where every player input is recorded on the blockchain, do let you locate an earlier point in the game's history.

In the OHOL port, there is the possibility that, by agreement, an archipelago can revert to an earlier point in time, making different decisions from there, growing the archipelago into a different state. Time becomes, in a sense, two-dimensional. Players can take archipelagos in different directions, exploring the most fun way to play.

Again, it's worth noting that this might not in fact be good game design. It might be a side effect of me watching [Arrival](https://en.wikipedia.org/wiki/Arrival_(film)) and [Interstellar](https://en.wikipedia.org/wiki/Interstellar_(film)) too many times. It might not belong in the on-chain OHOL port at all. At the very least, `customs` and replayable histories can help people who do not like this concept to avoid `archipelago`s taking advantage of it.

# Recap

I want to repeat this once more: I have very limited knowledge and experience in game design. It's quite likely that some of the above ideas will make you laugh, or maybe even mad. They might not make sense at all. But they are my true thoughts, and I'd really love feedback from any of you: if a game is designed this way, do you see yourself playing it?

If we think about it, sovereignty lies at the center of blockchain games:

* I can decide what game logic I want in my game.
* I can decide what external players / resources are allowed in my game.
* I can decide how to evolve my game across a two-dimensional time.

I don't believe all games will be like this. Just like cooking, talented game designers will still craft amazing games for all of us to enjoy, but every one of us should also be able to cook up a dish of our own every now and then. I believe that a new genre may emerge as blockchains become more capable of running game logic.

And the journey does not stop at OHOL on-chain, either. I think we might have even more complex game logic on-chain, which will be my next quest.
