+++
title = "Let's Build a Minimal Blockchain 3: What Is A Blockchain?"
date = "2020-03-16"
+++

If you have followed through this series, you would find the title quite misleading: I'm not gonna build the actual blockchain, I'm just dumping random ideas in the design of modern blockchains. Sadly this series is gonna be of contents like this for a while, at least till I have dumped all the ideas in my head, and I have got some time to do the actual coding part.

Another issue of this series, is that so far it's just full of ideas and no concrete examples. This can be changed easily, in this article we will have real examples to play with. But first let's get to the question: what is a blockchain?

One obvious way to answer that, is whatever is published by the blockchain authors can be consider a blockchain. You can treat the Bitcoin binary released by Bitcoin developers as the Bitcoin blockchain, you can also think the CKB releases as the CKB blockchain. But is this the real answer? Let's think deeper: what is the part that uniquely defines a blockchain? Foundamentally, what is the part that uniquely defines one blockchain, such as CKB, from other blockchains, such as Bitcoin, or Ethereum.

Personally, I feel the answer here, is the consensus protocol, in other words, the logic used to verify a block. If this part is changed, CKB will not be CKB anymore, Bitcoin will also not be Bitcoin. At the very core part, it really is the block accepting code, that truly defines a blockchain.

This brings an interesting question: typically, you would see a big monolithic binary as the blockchain release. This suits ordinary users quite well, but for developers who strives to optimize for performance and resource usage everyday, is this the best option? Would it work better if a monolithic blockchain can be decoupled into the core part as well as optional components? This way one can choose to deactivate components that are not needed, or switch to a different implementation of certain component that suits his/her need better. I do want to mention I'm not talking about micro-service s**t here, I'm merely talking about a plugin-based architecture enabling 2 benefits:

* I don't have to pay the cost for components I don't need
* I can swap to a different component that suits my need better

To me, this would enable a lot of possibilities in the blockchain world. If this still sounds quite abstract to you, let's take a look at a real example.

# ckb-boxer

Luckily, not all blockchains are a big blob of mess. CKB, for instance, has been designed into individual components that communicate to work together. It's quite easy to split the very core block verification part into a separate project. [ckb-boxer](https://github.com/xxuejie/ckb-boxer) is a result of the separation, it contains the very core block verification logic and accompanying storage engine into a separate project, and exposes a very simple stdin/stdout based text protocol, in which you can interact with it. The name comes from the sport boxing. In boxing, the athletes, called boxers, need to control their own body weight to the absolutely needed part, so they can gain the maximum advantage against opponents. ckb-boxer works exactly the same way: it keeps only what the name CKB means, and strip everything else, so you can build whatever tools on top of it, enabling different behaviors. Notice this is never a replacement for the current CKB, for the vast majority of the users, current CKB release is the ideal solution for them, we've got awesome engineers maintaining the codebase for a bright future. But for a very small group of people who want to push the boundaries of CKB, ckb-boxer can be a handy addition in the toolbox.

There's actually one more benefit of ckb-boxer: it packs CKB's storage engine, so it is compatible from the data perspective with the full featured CKB node. One the one hand, this means you can freely copy the data folder from a full features CKB node to ckb-boxer, and vice versa; on another hand, this also means tools that directly read CKB's data folder will also work with ckb-boxer. [ckb-graphql-server](https://github.com/xxuejie/ckb-graphql-server) is such an example, you can use ckb-graphql-server directly on top of ckb-boxer without any problems.

With ckb-boxer in place, let's see a real demo of how one component in a blockchain can be swapped.

# Alternate Syncing Protocol

One obvious idea, is that we can now switch to a different syncing protocol. Notice this never means the current syncing protocol in CKB is not good, it is just that depending on different deployed environments, an alternative syncing protocol might enable different gains. For example, the current syncing protocol spends a great deal of efforts preventing all kinds of attacks, which makes sense in a decentralized environment. But if you have CKB deployed in an Intranet, you are dealing with nodes that you can have a higher level of trust, do you still need a protocol that deals with all kinds of protocol-level attacks? With a different syncing protocol, it's possible to achieve even better performance.

Depending on the requirements, a syncing protocol doesn't even have to complicated, here we can design a very simple syncing protocol that works as follows:

* A node keeps sending `get_block_by_number` requests to a full featured CKB node, fetching latest blocks
* It then sends blocks to ckb-boxer for processing

Different people might have different angles, personally, I would classify this as a syncing protocol as well. Yes it only syncs blocks from another node, it never relays blocks to other nodes, but it fulfills the purpose of downloading all the blocks and create a node one can use.

Let's now implement this protocol, as we can see below, it just takes a 50-line JS file to implement the protocol:

```
$ export TOP=$(pwd)
$ cat << EOF > fib.ts
#!/usr/bin/env node

const Blockchain = require("./blockchain.umd.js");
const Toolkit = require("ckb-js-toolkit");
const { spawn } = require("child_process");
const process = require("process");
const readline = require("readline");

if (process.argv.length !== 5) {
  console.log(`Usage: ${process.argv[1]} <rpc path> <ckb-boxer binary> <start block number>`)
  process.exit(1)
}

const RPC = process.argv[process.argv.length - 3];
const BOXER_PATH = process.argv[process.argv.length - 2];
const START_BLOCK_NUMBER = BigInt(process.argv[process.argv.length - 1]);

function sleep(ms = 0) {
  return new Promise(r => setTimeout(r, ms));
}

(async () => {
  const boxer = spawn(BOXER_PATH, ["run", "-C", "data"],
                      Object.assign({}, process.env, {
                        RUST_LOG: "debug"
                      }));
  boxer.stdout.on("data", data => {
    console.log(`Boxer STDOUT: ${data}`);
  });
  boxer.stderr.on("data", data => {
    console.log(`Boxer STDERR: ${data}`);
  });

  const rpc = new Toolkit.RPC(RPC);
  const tip_number = BigInt((await rpc.get_tip_header()).number);
  let current_number = START_BLOCK_NUMBER;
  while (current_number <= tip_number) {
    const block = await rpc.get_block_by_number("0x" + current_number.toString(16));
    const normalizedBlock = Toolkit.normalizers.NormalizeBlock(block);

    const serializedBlock = Blockchain.SerializeBlock(normalizedBlock);
    const serializedBlockHex = new Toolkit.Reader(serializedBlock).serializeJson();

    console.log(`Sending block ${current_number} to ckb-boxer`);
    boxer.stdin.write("0001NBLK" + serializedBlockHex.substr(2) + "\n");
    current_number += BigInt(1);
  }

  await sleep(2000);
}) ();
EOF
```

We will need a couple of dependencies to run the protocol here:

```
$ cd $TOP
$ npm install ckb-js-toolkit@0.6.0 rollup@2.0.6
$ cargo install moleculec
$ git clone https://github.com/xxuejie/ckb-boxer
$ cd ckb-boxer
$ cargo build --release
$ cd $TOP
# I'm running the code under Linux, if you use other platforms, you might need
# to tweak the downloaded binaries here
$ curl -LO https://github.com/nervosnetwork/ckb/releases/download/v0.29.0/ckb_v0.29.0_x86_64-unknown-linux-gnu.tar.gz
$ curl -LO https://github.com/xxuejie/moleculec-es/releases/download/0.1.1/moleculec-es_0.1.1_Linux_x86_64.tar.gz
$ curl -LO https://raw.githubusercontent.com/nervosnetwork/ckb/a8dbc63c4e1a1a6c4432979cb48e8df831560ef5/util/types/schemas/blockchain.mol
$ tar xzf ckb_v0.29.0_x86_64-unknown-linux-gnu.tar.gz
$ tar xzf moleculec-es_0.1.1_Linux_x86_64.tar.gz
$ moleculec --language - --schema-file blockchain.mol --format json > blockchain.json
$ ./moleculec-es -inputFile blockchain.json -outputFile blockchain.js
$ npx rollup -f umd -i blockchain.js -o blockchain.umd.js --name Blockchain
```

Let's start a full featured CKB node that syncs mainnet as normal here:

```
$ cd $TOP
$ ./ckb_v0.29.0_x86_64-unknown-linux-gnu/ckb init -C mainnet -c mainnet
$ ./ckb_v0.29.0_x86_64-unknown-linux-gnu/ckb run -C mainnet
```

Wait for a while for the full featured CKB to sync some blocks. Now in a different terminal, we can now start our alternative syncing solution:

```
$ cd $TOP
$ ./ckb_v0.29.0_x86_64-unknown-linux-gnu/ckb init -C alternate -c mainnet
$ chmod +x runner.js
$ ./runner.js http://127.0.0.1:8114 ckb-boxer/target/release/ckb-boxer 1
(omitted some log lines...)
Sending block 129 to ckb-boxer
Sending block 130 to ckb-boxer
Sending block 131 to ckb-boxer
Sending block 132 to ckb-boxer
Sending block 133 to ckb-boxer
Boxer STDOUT: 0000TIPH0000000000000000
2020-03-16 04:34:36.843 +00:00 main INFO ckb-boxer  ckb-boxer is now booted
2020-03-16 04:34:36.847 +00:00 ChainService INFO ckb-chain  block: 1, hash: 0x2567f226c73b04a6cb3ef04b3bb10ab99f37850794cd9569be7de00bac4db875, epoch: 0(1/1743), total_diff: 0x3b1bb3d4c1376a, txs: 1
0000NBLK2567f226c73b04a6cb3ef04b3bb10ab99f37850794cd9569be7de00bac4db875
2020-03-16 04:34:36.848 +00:00 ChainService INFO ckb-chain  block: 2, hash: 0x2af0fc6ec802df6d1da3db2bfdd59159d210645092a3df82125d20b523e0ea83, epoch: 0(2/1743), total_diff: 0x58a98dbf21d31f, txs: 1
0000NBLK2af0fc6ec802df6d1da3db2bfdd59159d210645092a3df82125d20b523e0ea83
2020-03-16 04:34:36.848 +00:00 ChainService INFO ckb-chain  block: 3, hash: 0x247167d03a723f6b8999da09d94b61fadf47f94364d729cb6272edc1f20009b7, epoch: 0(3/1743), total_diff: 0x763767a9826ed4, txs: 1
0000NBLK247167d03a723f6b8999da09d94b61fadf47f94364d729cb6272edc1f20009b7
(more log lines...)
```

Here you can notice that ckb-boxer is already started to accept blocks. Our simple syncing protocol works!

Of course this is a overly-simplified example, it won't do us any good in a real production setup. However it is enough to state a point: a syncing protocol only has to satisfy the given requirements, it doesn't have to be complex. In some cases, a similar protocol could indeed work: suppose someone sets up a writer that writes all CKB blocks to AWS S3, a minimal runner much like the above can then be used to grab blocks on S3 and feed them to ckb-boxer.

## Generaized Syncing Protocol

The main point I want to make here, is that I question if a generalized syncing protocols for most, if not all, blockchains can be viable. I could definitely be wrong on this, but the more I think, the more I feel a vast number of blockchains out there, can work with such a generalized syncing protocol:

* The syncing protocol consists of 3 main entities: headers, blocks, and compact blocks;
* Headers are synced first among nodes, preliminary checks on the headers can help the node eliminate most invalid blocks. For example PoW check in PoW blockchains can work here, PoS blockchains might have similar mechanisms that the node can levarage(notice I'm not super familiar with PoS blockchains on a protocol level, so this might be wrong here);
* Blocks are then downloaded and validated on the best chain per downloaded headers, if block validation fails somewhere, the node might need to go back to previous steps to sync headers on a different fork;
* When the full content for the latest block can be inferred from previous few blocks or other information(such as data synced in a separate protocol), a compact block containing only the necessary information can be sent instead to save the bandwith.

If you think about this, I believe you will agree with me, that many blockchains can be abstracted and synced via this single protocol. There will always be outliers of course, but if we have a single syncing protocol that works with enough blockchains, I personally feel that will help us build a better blockchain world. We already started to see cross-chain initiatives, if multiple chains can share more infrastructure, such as syncing protocol, that will greatly reduce operational burden on dapp developers.

So this is my wish for the future: we first shrink each blockchain to the core part, then a unified syncing protocols can be used to support multiple blockchains at once. And it's not just syncing protocols, there might be more components, such as transaction pools, RPC calls for fetching blockchains, it might result in a better world: even though existing solutions already provide sample syncing protocols that are quite good in many cases, they still require you to run the whole thing, which might still be operational burdens. If a new blockchain can be shrinked to the minimal core blockchain part, a common infrastructure can be used to run many blockchains in parallel without affecting one another, resulting in much less development and operation burdens.

# Recap

I do believe we should go back to the basis: a blockchain should only be the core blockchain logic. Right now there are just too many things that will hinder your eyes, such as building a syncing protocol, building a transaction pool, tuning a multi-threaded infrastructure. The result of all of those, is that a developer might only be able to spend a tiny fraction of the time on the core logic of the blockchain, which IMHO, is not the best way to build a blockchain. We deserve something much better, I yearn for a world where a blockchain developer can focus the entire efforts on making sure the blockchain logic is flawless, instead of wasting efforts on surrounding components that are only essential, but not unique to the developer's own innovated blockchain.
