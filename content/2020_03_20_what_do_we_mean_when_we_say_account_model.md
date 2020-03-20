+++
title = "What Do We Mean When We Say Account Model?"
date = "2020-03-20"
+++

It is widely believed in the blockchain world that account model has advantages over UTXO model in terms of usability, and I've been working on bridging the differences between UTXO model and account model in a [blockchain](https://github.com/nervosnetwork/ckb). There is some [initial attempt](https://medium.com/nervosnetwork/https-medium-com-nervosnetwork-animagus-part-1-introduction-66fa8ce27ccd-cfb361a7d883) on the problem. But lately, I start to feel that UTXO model and account model are essentially the same thing, or if we rephrase using buzzwords, UTXO model is just a **software defined** version of account model. If this puzzles you don't worry, I will explain in more details below.

To make things easier to understand, in this post I will only use the wording UTXO model. People who know us will know we generalize from the UTXO model into the cell model. The added advantages of cell model do not matter here. I'm gonna argue below that any UTXO model that is capable of storing data(such as CKB's cell model, or even plain old Bitcoin's UTXO model when using `OP_PUSHDATA`), can be equivalent to the account model when it comes to programming model.

# What Is Account Model?

In an account model based blockchain, transactions only state the action, or function call with parameters. The actual state, is computed and inferred from the blockchain, like the diagram below shows:

![Account Model](/images/account_model_1.svg)

Whereas in a UTXO based blockchain, the states are all included in the transaction. You are directly embeding the data you want in transactions. Typically, multiple UTXOs can work together to provide parts of the whole state. When you want to change the data in a part, you include the UTXO for that part as an input in the transaction, and provide a new UTXO containing the updated data. This is shown in the diagram below:

![UTXO Model](/images/utxo_model_1.svg)

There has been debates on the 2 models for quite some time. One obvious consideration, is that the account model has smaller transaction size, but in exchange, the states have to be computed in the account based blockchain, and worse, transactions for the same account needs to be executed sequentially. On the other hand, UTXO based blockchain only needs to do verification work to make sure submitted data are in correct format, transactions accessing different parts of the same account can also be verified in parallel for the better performance. But a drawback of larger transaction size is usually paid, since transactions will need to contain the actual data.

But this is not the main point of this post, each solution has its own way of mitigating the challenges. There is a popular belief, that the account model provides superiority over the UTXO model when building dapps. Another way of saying this, is that UTXO based blockchain cannot have dapps using account model. Is this really true? Let's find out here.

# A Little Transformation

We are gonna look at a real ERC20-like token transferring operation here. In an account model blockchain, typically you have a *token* account storing the token balances of all users. When someone wants to make a transfer, it just submits a transaction stating `from`, `to` and the `balance` to transfer:

![Account Model Concrete](/images/account_model_2.svg)

The blockchain then **executes** the transaction on chain, and updates the internal state containing the changes.

How can we represent this in a UTXO based blockchain? One observation, is that typical account based blockchain represents the whole account state via a key-value store. We can embrace the same abstraction here:

* A pre-defined number of cells are created for each account. Actually, you only need to define the number here, the absent of a cell could be interpreted as a dummy cell;
* Each cell stores a part of the whole key space in the key-value store;
* If a transaction needs to update some value, it first locates the cell containing the key for that value, includes the corresponding cell as transaction input, then provides a new cell containing updated data;

An example for a transaction in this style is shown in the diagram below:

![UTXO Model Concrete](/images/utxo_model_2.svg)

Here the whole account state contains 4 cells, but since only 2 cells need to be updated, the transaction only contains those 2 cells.

You might noticed that this looks a lot like the [B-tree](https://en.wikipedia.org/wiki/B-tree) data structure used in database and file systems. In a B-tree structure, you want to minimize the actual pages that are modified, which is exactly the same point for our UTXO based design: you want to include and modify as few cells as possible in the transaction. This means while what we have is a naive design, you could leverage the rich research ideas accumulated in the B-tree area to build better designs that provides better results.

If we think about the scheme here, it actually exploits no application specific knowledge, the only assumption is that account model uses a key-value store, which is already the case today. This means we can build a generator of account model on top of the UTXO model:

* The generator answers read requests from dapp developers, it queries current live cells of the account, and extracts values for provided keys;
* The generator also accepts account model style function calls, it runs the function with current live cells, and generates a transaction contains updated cells, relays the transaction to the blockchain for acceptance. For flexibility, we can introduction account model style virtual machines here, such as EVM, Move, etc;
* An on-chain smart contract can then run the same code run by the generator, to validate the correct data has been generated. If a VM such as EVM or Move has been used, we can port the same VM to the on-chain smart contract, and execute the same thing here.

Of course this new generator parts needs to be built to make UTXO based blockchain behave like account based blockchain. My point here, is that this is a total feasible route, meaning the design of a UTXO based blockchain, never really gets in the way of building account model style dapps.

# Duplicating Logic In Generator Is Not A Bad Idea

One constant criticism of this path, which was also my previous concern, is that we are duplicating logic in both the off-chain generator part, and in the on-chain smart contract. But lately, I've been questioning this point: is this really a concern? One widely holded principle in the blockchain world is "don't trust, verify". The smart contract contained in one transaction will not just run on a single node, it will run on every single blockchain node out there. We already have `N` executions of the same smart contract, does it really matter if the generator executes one more time, and make it `N + 1`? We all know when `N + 1` in this case has no difference from `N`. I would personally consider the generator part just one more light client node that validates the smart contract one more time. This won't cause us any problems in the established blockchain design.

If you are still paranoid by this, there is actually one more view to the story: the above design is based on no assumptions other than a key-value store based account model. It's very likely that when we are talking specific dapps, there are properties we can exploit, so the on-chain smart contract does not have to run exactly the same code as the off-chain generator. For example, in an ERC20 token example, there are really only 2 rules that need to be verified on chain:

* Transactions have valid signature;
* Normal transactions cannot issue more tokens than currently issued.

Once those 2 rules are satisfied, the rest of the ERC20 related code can safely run off-chain. Meaning you don't have to re-run the same code on-chain again.

But this is just an optimization for a specific dapp, and I would even question if the optimization is necessary. To me, the previous more generic solution already works quite well.

# Software Defined World

There is of course the problem that a generator part described above needs to be developed. But if we look outside of the blockchain world, and look at the general software industry, we can notice an unstoppable trend:

* CPUs are moving from [CISC](https://en.wikipedia.org/wiki/Complex_instruction_set_computer) design to [RISC](https://en.wikipedia.org/wiki/Reduced_instruction_set_computer) design, software based compilers are used to fill in the missing part in RISC.
* Highly specialized hardware based switches are being eaten by ordinary computers leveraging [sophisticated software](https://github.com/snabbco/snabb)
* Traditional network attached storage or storage area network have been replaced by commodity cloud employing [software defined storage](https://www.redhat.com/en/topics/data-storage/software-defined-storage)
* Even in cellular towers, [more software](https://venturebeat.com/2019/06/17/ericsson-updates-5g-cell-tower-software-to-improve-speed-and-coverage/) has been deployed to provide better performance

Have you noticed a pattern? We are seeing a world where complex, sophisticated hardware has been rapidly replaced with simple hardware. Highly specialized software has been used more and more to complement the features which used to be in hardware. At Nervos Network, we believe blockchains are more like hardware than software, and if we look at the UTXO model vs account model debate, we can see similar conflicts:

* An account based blockchain puts more logic in the blockchain(read: hardware) part;
* A UTXO based blockchain puts less logic in the blockchain(read: hardware) part, and leverage software to fill in more features.

If all we see is one or two single case, it might just be an abnormality, but what we see is an industry-wise shift from more hardware, to more software. I'm not sure about you, but I would personally want to bet that all the bright minds in our industry are making the right choice here :P
