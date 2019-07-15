+++
title = "Introduction to CKB Script Programming 2: Script Basics"
date = "2019-07-13"
+++

Last post introduced current CKB's validation model. This post will get more fun, since we will show how to deploy script codes to CKB for real. I'm hoping after this post, you should be able to explore the CKB world and work on new script codes as you wish.

Note even though I believe CKB's programming model is quite stable now, development is still happening so there might be changes. I will try my best to make sure this post is updated but if anything confuses you, this post is describing CKB as of [this commit](https://github.com/nervosnetwork/ckb/commit/80b51a9851b5d535625c5d144e1accd38c32876b) now.

A warning here: this will be a long post, since I want to fill in enough for the more interesting topic next week. So you don't have to finish it at once if you don't have enough time. I've tried to split it into individual sections, so you can try each one at a time.

# Wording

Before we continue, let's distinguish between 2 terms: script, and script code.

In this post and hopefully the whole series, we will distinguish between script, and script code. Script code actually refers to the program you write and compile to use on CKB. Script, on the other hand, actually refers to the script data structure used in CKB, which is a little more than just the script code:

```rust
pub struct Script {
    pub args: Vec<Bytes>,
    pub code_hash: H256,
    pub hash_type: ScriptHashType,
}
```

We can ignore `hash_type` for now, a future post will explain what it is and it's interesting usage. Later in this post, we will show that `code_hash` actually just identifies a script code, so for now we can just think of it as script code. What script also includes, is the `args` part, which distinguishes script from script code. `args` can be used here to provide additional arguments for a CKB script, for example, while people might all be using the same default lock script code, each of them might have their own pubkey hash, `args` is exact the place to hold pubkey hash. This way each user of CKB can have different lock script, while sharing the same lock script code.

Note that in most cases, script and script code can be used interchangably, but if you are confused at some places, it might be worthwhile to think of the difference between the 2.

# A Minimal CKB Script Code

As you might have already heard, CKB is based on the open source RISC-V ISA. But what does that even mean? In my words, it means we are (sort of) embedding a real mini computer in CKB, instead of a virtual machine. The benefit of a real computer, is that you can write any logic you want in any language you want. The first few examples we show here will be written in C for simplicity(well I mean simplicity in the toolchain, not the [language](http://blog.llvm.org/2011/05/what-every-c-programmer-should-know.html)), but later we will switch to JavaScript based script code, and hopefully show more languages in the series. On CKB there's endless possibilities.

As we mentioned about, CKB VM is more like a real mini computer. CKB script code also looks like a normal Unix style executable program we run on a computer:

```c
int main(int argc, char* argv[])
{
  return 0;
}
```

When compiled via a C compiler, this will become a script code that is runnable on CKB. In other words, CKB just take plain old Unix style executables(but in RISC-V architecture instead of the popular x86 architecture), and run it in a virtual machine environment. If the program returns with 0 as the return code, we consider the script succeeds, all non-zero return codes will be considered script faliures.

In the example above, we are showing a script code that always succeeds, since the return code will always be zero. Please don't use this as your lock script code, otherwise your token can be taken away by anyone.

But the example above won't be interesting, here we will start with an interesting idea: personally I dislike carrot. I do know that carrot is great from a nutritional point of view, but I still want to avoid it due to the taste. Now what if I want to set a rule, that none of my cells on CKB has data that begin with `carrot`? Let's write a script code to ensure this.

In order to ensure none of the cells can have `carrot` in cell data, we need a way to first read cell data in the script. CKB provides `syscalls` to help with this.

To ensure the security of CKB script, each script has to run in an isolated environment that is totally separated from the main computer you are running CKB. This way it won't be able to access data it doesn't need, such as your private keys or passwords. However, for a script to be useful, there must be certain data it want to access, such as the cell a script guards, or a transaction a script validates. CKB provides `syscalls` to ensure this, syscalls are defined in RISC-V standard, they provide a way to access certain resources provided by the environment. In a normal situation, the environment here means the operating system, but in the case of CKB VM, the environment refers to the actual CKB process. With syscalls, a CKB script can access the whole transaction containing itself, including inputs, outputs, witnesses, and deps.

The good news, is that we have encapsulated syscalls in an easy to use [header file](https://github.com/nervosnetwork/ckb-system-scripts/blob/66d7da8ec72dffaa7e9c55904833951eca2422a9/c/ckb_syscalls.h), you are very welcome to poke around this file to see how syscalls are implemented. The bottomline is you can just grab this header file and use the wrapped functions to make syscalls as you want.

Now with the syscalls at hand, we can start with our carrot-forbidden script:

```c
#include <memory.h>
#include "ckb_syscalls.h"

int main(int argc, char* argv[]) {
  int ret;
  size_t index = 0;
  volatile uint64_t len = 0; /* (1) */
  unsigned char buffer[6];

  while (1) {
    len = 6;
    memset(buffer, 0, 6);
    ret = ckb_load_cell_by_field(buffer, &len, 0, index, CKB_SOURCE_OUTPUT,
                                 CKB_CELL_FIELD_DATA); /* (2) */
    if (ret == CKB_INDEX_OUT_OF_BOUND) {               /* (3) */
      break;
    }

    if (memcmp(buffer, "carrot", 6) == 0) {
      return -1;
    }

    index++;
  }

  return 0;
}
```

Several points worth explaining here:

1. Due to C quirks, the `len` field needs to be marked as `volatile`. We will use it both as an input and output parameter, and CKB VM only can set the output when it lives in memory. `volatile` ensures a C compiler keeps it as a RISC-V memory based variable.
2. When making a syscall, we need to provide the following: a buffer to hold the data provided by the syscall; a `len` field denoting both the buffer length, and available data length returned by the syscall; an offset into the input data buffer, and several parameters denoting the exact field we are fetching in the transaction. For more details, please refer to our [RFC](https://github.com/nervosnetwork/rfcs/blob/master/rfcs/0009-vm-syscalls/0009-vm-syscalls.md).
3. For maximum flexibility, CKB uses the return value of the syscall to represent data fetching status: 0(or `CKB_SUCCESS`) means success, 1(or `CKB_INDEX_OUT_OF_BOUND`) means you have finished fetching all indices in a kind, 2(or `CKB_ITEM_MISSING`) means an entity is not present, such as fetching a type script from a cell that doesn't have one.

So to recap, this script would loop through all output cells in the transaction, load the first 6 bytes of each cell data and test if those bytes match `carrot`. If we found a match, the script would return `-1`, denoting an error status, if no match is found, the script exits with `0`, meaning execution success.

To perform the loop, the script would keep an `index` variable, in each loop iteration, it would tries to make the syscall to fetch the cell denoted by current `index` value, if the syscall returns `CKB_INDEX_OUT_OF_BOUND`, it means the script has iterated through all the cells, hence it just exits the loop, otherwise, the loop would continue, the cell data is tested, then `index` variable is incremented for the next iteration.

This concludes your first useful CKB script code! In the next section, we will see how we can deploy it to CKB and run it.

# Deploying a Script to CKB

First, we need to compile the carrot source code written above. Since GCC already has upstream RISC-V support, you can of course use the official GCC to build your script code. Or you can use the [docker image](https://hub.docker.com/r/nervos/ckb-riscv-gnu-toolchain) we have prepared to save the trouble of compiling GCC:

```bash
$ ls
carrot.c  ckb_consts.h  ckb_syscalls.h
$ sudo docker run --rm -it -v `pwd`:/code nervos/ckb-riscv-gnu-toolchain:xenial bash
root@dc2c0c209dcd:/# cd /code
root@dc2c0c209dcd:/code# riscv64-unknown-elf-gcc -Os carrot.c -o carrot
root@dc2c0c209dcd:/code# exit
exit
$ ls
carrot*  carrot.c  ckb_consts.h  ckb_syscalls.h
```

And that's it, CKB can use the compiled executable from GCC directly as scripts on chain, there's no way for further processing. We can now deploy it on chain. Note that I will use CKB's Ruby SDK since I used to be a Ruby programmer, and Ruby feels the most natural one(but not necessarily the best one) to me. Please refer to the official [README](https://github.com/nervosnetwork/ckb-sdk-ruby/blob/develop/README.md) for how to set it up.

To deploy the script to CKB, we can just create a new cell, with the script code as cell data part:

```ruby
pry(main)> data = File.read("carrot")
pry(main)> data.bytesize
=> 6864
pry(main)> carrot_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(8000), CKB::Utils.bin_to_hex(data))
```

Here I simply create a new cell with enough capacity by sending tokens to myself. Now we can create the type script containing the carrot script code:

```ruby
pry(main)> carrot_data_hash = CKB::Blake2b.hexdigest(data)
pry(main)> carrot_type_script = CKB::Types::Script.new(code_hash: carrot_data_hash, args: [])
```

Recall the Script data structure:

```rust
pub struct Script {
    pub args: Vec<Bytes>,
    pub code_hash: H256,
    pub hash_type: ScriptHashType,
}
```

We can see that instead of embedding the script code directly in the script data structure, we are only including the code hash, which is a Blake2b hash of the actual script binary code. Since carrot script doesn't use an argument, we can use empty array for `args` part.

Note I'm still ignoring `hash_type` here, we will leave to a future post to see a different way of specifying code hash. For now, let's keep it simple here.

To run the carrot script, we need to create a new transaction, and set carrot type script as the type script of one of the output cells:

```ruby
pry(main)> tx = wallet.generate_tx(wallet2.address, CKB::Utils.byte_to_shannon(200))
pry(main)> tx.outputs[0].instance_variable_set(:@type, carrot_type_script.dup)
```

There's one more step needed: in order for CKB to locate the carrot script, we need to reference the cell containing carrot script in one of transaction deps:

```ruby
pry(main)> carrot_out_point = CKB::Types::OutPoint.new(cell: CKB::Types::CellOutPoint.new(tx_hash: carrot_tx_hash, index: 0))
pry(main)> tx.deps.push(carrot_out_point.dup)
```

Now we are ready to sign and send the transaction:

```ruby
[44] pry(main)> tx.witnesses[0].data.clear
[46] pry(main)> tx = tx.sign(wallet.key, api.compute_transaction_hash(tx))
[19] pry(main)> api.send_transaction(tx)
=> "0xd7b0fea7c1527cde27cc4e7a2e055e494690a384db14cc35cd2e51ec6f078163"
```

Since this transaction does not have any cell containing `carrot` in the cell data, the type script validates successfully. Now let's try a different transaction that does have a cell that begins with `carrot`:

```ruby
pry(main)> tx2 = wallet.generate_tx(wallet2.address, CKB::Utils.byte_to_shannon(200))
pry(main)> tx2.deps.push(carrot_out_point.dup)
pry(main)> tx2.outputs[0].instance_variable_set(:@type, carrot_type_script.dup)
pry(main)> tx2.outputs[0].instance_variable_set(:@data, CKB::Utils.bin_to_hex("carrot123"))
pry(main)> tx2.witnesses[0].data.clear
pry(main)> tx2 = tx2.sign(wallet.key, api.compute_transaction_hash(tx2))
pry(main)> api.send_transaction(tx2)
CKB::RPCError: jsonrpc error: {:code=>-3, :message=>"InvalidTx(ScriptFailure(ValidationFailure(-1)))"}
from /home/ubuntu/code/ckb-sdk-ruby/lib/ckb/rpc.rb:164:in `rpc_request'
```

We can see our carrot script rejects a transaction that generates a cell with carrot. Now I can use this script to make sure all my cells are free from carrots!

So to recap, to deploy and run a script as type script, what we need to do is:

1. Compile the script to RISC-V executable binary
2. Deploy the binary in a cell's data part
3. Create a type script data structure with the blake2b hash of the binary as `code hash`, any required arguments of the script code in the `args` part
4. Create a new transaction with the type script set in one of the generated cells
5. Include the outpoint to the cell containing the script code as one of the transaction deps

That's really all you need! If your script has run into problems, those are the points you need to check.

Although we only talk about type scripts here, lock script works exactly the same way. The only quirk you need to keep in mind, is that when you create a cell with a specificed lock script, the lock script won't run here. It only runs when you are consuming the cell. So while type script can be used to create the logic that runs when you create the cell, lock script is used to create the logic that runs when you consume the cell. Given this consideration, please make sure your lock script is correct, otherwise you might be losing the tokens in the following scenarios:

* Your lock script has a bug that someone else can unlock your cell.
* Your lock script has a bug that no one(including you) can unlock your cell.

One tip we can provide here, is always test your script as a type script attached to an output cell in your transaction, this way when error happens, you will know immediately, your tokens can stay safe.

# Dissecting the Default Lock Script Code

With the knowledge we have, let's look at the default lock script code included in CKB. To avoid confusion, we are looking at the lock script code as of [this commit](https://github.com/nervosnetwork/ckb-system-scripts/blob/66e2b3fc4fa3e80235e4b4f94a16e81352a812f7/c/secp256k1_blake160_sighash_all.c).

The default lock script code would loop through all input cells that have the same lock script as itself, and perform the following steps:

* It grabs the current transaction hash via a provided syscall.
* It grabs the corresponding witness data for current input.
* For the default lock script, it is assumed that the first argument in witness contains the recoverable signature signed by cell owner, and the rest arguments are optional user provided arguments.
* Default lock script code runs a blake2b hash on the concatenated binary data of the transaction hash, and all the user provided arguments(if exists).
* The blake2b hash result is then used as the message part for the secp256k1 signature verification. Note the actual signature is provided in the first argument in witness data structure.
* If the signature verification fails, the script exits with a failure return code. Otherwise it continues with the next iteration.

Note we talked about the difference between script and script code earlier. Each different pubkey hash would result in different lock script, hence if a transaction has input cells with the same default lock script code but different pubkey hash(hence different lock script), multiple instances of the default lock script code will be executed, each with its own set of cells sharing the same lock script.

Now we can walk through different segments of the default lock script code:

```c
if (argc != 2) {
  return ERROR_WRONG_NUMBER_OF_ARGUMENTS;
}

secp256k1_context context;
if (secp256k1_context_initialize(&context, SECP256K1_CONTEXT_VERIFY) == 0) {
  return ERROR_SECP_INITIALIZE;
}

len = BLAKE2B_BLOCK_SIZE;
ret = ckb_load_tx_hash(tx_hash, &len, 0);
if (ret != CKB_SUCCESS) {
  return ERROR_SYSCALL;
}
```

When arguments are included in `args` part of `Script` data structure, they are presented to the actual running script program via the Unix conventional `arc`/`argv` way. To further preserve conventions, we insert a dummy argument at `argv[0]`, so your first include argument starts at `argv[1]`. In the case of default lock script code, it accepts one argument, which is the pubkey hash generated from the owner's private key.

```c
ret = ckb_load_input_by_field(NULL, &len, 0, index, CKB_SOURCE_GROUP_INPUT,
                             CKB_INPUT_FIELD_SINCE);
if (ret == CKB_INDEX_OUT_OF_BOUND) {
  return 0;
}
if (ret != CKB_SUCCESS) {
  return ERROR_SYSCALL;
}
```

Using the same technique as shown in the carrot example, we check if there's more input cells to test. There're 2 differences from previous examples:

* If we just want to know if a cell exists and don't need any of the data, we can just pass in `NULL` as the data buffer, and a `len` variable with value 0. This way the syscall would skip data filling and just provided available data length and correct return code for processing.
* In the carrot example, we are looping through all inputs in the transaction, but here we just care about input cells of the same lock script. CKB named cells with the same lock(or type) script as cells with the same `group`. And here, we can use `CKB_SOURCE_GROUP_INPUT` instead of `CKB_SOURCE_INPUT` denoting the syscalls to only count cells in the same group, i.e., cells who have the same lock script as the current cell.

```c
len = WITNESS_SIZE;
ret = ckb_load_witness(witness, &len, 0, index, CKB_SOURCE_GROUP_INPUT);
if (ret != CKB_SUCCESS) {
  return ERROR_SYSCALL;
}
if (len > WITNESS_SIZE) {
  return ERROR_WITNESS_TOO_LONG;
}

if (!(witness_table = ns(Witness_as_root(witness)))) {
  return ERROR_ENCODING;
}
args = ns(Witness_data(witness_table));
if (ns(Bytes_vec_len(args)) < 1) {
  return ERROR_WRONG_NUMBER_OF_ARGUMENTS;
}
```

Continue down the path, we are loading the witness for current input. Corresponding witnesses and inputs have the same index. Right now CKB uses flatbuffer as the serialization format in syscalls, so if this feels weird to you, [flatcc's documentation](https://github.com/dvidelabs/flatcc) is your best friend.

```c
/* Load signature */
len = TEMP_SIZE;
ret = extract_bytes(ns(Bytes_vec_at(args, 0)), temp, &len);
if (ret != CKB_SUCCESS) {
  return ERROR_ENCODING;
}

/* The 65th byte is recid according to contract spec.*/
recid = temp[RECID_INDEX];
/* Recover pubkey */
secp256k1_ecdsa_recoverable_signature signature;
if (secp256k1_ecdsa_recoverable_signature_parse_compact(&context, &signature, temp, recid) == 0) {
  return ERROR_SECP_PARSE_SIGNATURE;
}
blake2b_state blake2b_ctx;
blake2b_init(&blake2b_ctx, BLAKE2B_BLOCK_SIZE);
blake2b_update(&blake2b_ctx, tx_hash, BLAKE2B_BLOCK_SIZE);
for (size_t i = 1; i < ns(Bytes_vec_len(args)); i++) {
  len = TEMP_SIZE;
  ret = extract_bytes(ns(Bytes_vec_at(args, i)), temp, &len);
  if (ret != CKB_SUCCESS) {
    return ERROR_ENCODING;
  }
  blake2b_update(&blake2b_ctx, temp, len);
}
blake2b_final(&blake2b_ctx, temp, BLAKE2B_BLOCK_SIZE);
```

The first argument in witness is the signature to load, while the rest arguments, if presented, are appened to transaction hash for a blake2b operation.

```c
secp256k1_pubkey pubkey;

if (secp256k1_ecdsa_recover(&context, &pubkey, &signature, temp) != 1) {
  return ERROR_SECP_RECOVER_PUBKEY;
}
```

Using the hashed blake2b result as message, we then do secp256 signature verification.

```c
size_t pubkey_size = PUBKEY_SIZE;
if (secp256k1_ec_pubkey_serialize(&context, temp, &pubkey_size, &pubkey, SECP256K1_EC_COMPRESSED) != 1 ) {
  return ERROR_SECP_SERIALIZE_PUBKEY;
}

len = PUBKEY_SIZE;
blake2b_init(&blake2b_ctx, BLAKE2B_BLOCK_SIZE);
blake2b_update(&blake2b_ctx, temp, len);
blake2b_final(&blake2b_ctx, temp, BLAKE2B_BLOCK_SIZE);

if (memcmp(argv[1], temp, BLAKE160_SIZE) != 0) {
  return ERROR_PUBKEY_BLAKE160_HASH;
}
```

Last but not least, we also need to check the pubkey contained from the recoverable signature is indeed the pubkey used to generated the pubkey hash included in the lock script arguments. Otherwise, someone might use a signature generated from a different pubkey to steal your token.

In short, the scheme used in the default lock script resembles a lot like the solution used in [bitcoin now](https://bitcoin.org/en/transactions-guide#p2pkh-script-validation).

# Introducing Duktape

I'm sure you feel the same way as I do now: it's good we can write contracts in C, but C always feels a bit tedious and, let's face it, dangerous. Is there a better way?

Yes of course! We mentioned above CKB VM is essentially a mini computer, and there are tons of solutions we can explore. One thing we have prepared here, is that we can write CKB script codes in JavaScript. Yes you got it right, plain ES5(yes I know, but this is just one example, and you can use a transpiler) JavaScript.

How this is possible? Since we have C compiler available, all we did is just take a JavaScript implementation for the embeded system, in our case, [duktape](https://duktape.org/), compile it from C to RISC-V binary, put it on chain, then boom, we can run JavaScript in CKB! Since we are working with a real mini computer here, there's no stopping us from embeding another VM as CKB script to CKB VM, and exploring this VM on top of VM path.

And we can actually expand from this path, we can have JavaScript on CKB via duktape, we can also have Ruby on CKB via [mruby](https://github.com/mruby/mruby), we can even have Bitcoin Script or EVM on chain if we just compile their VM and put it on chain. This ensures CKB VM can both help us preserve legacy and build a diversified ecosystem. All languages should be and are treated equal on CKB, the freedom should be in the hands of blockchain contract developers.

At this stage you might want to ask: yes this is possible, but won't VM on top of VM be slow? I believe it really depends on your use case to say if this is gonna be slow. I'm a firm believer that benchmarks make no sense unless we put it in a real use case with standard hardware requirements. So wait to see if this is really gonna be an issue. In my opinion, higher languages are more likely to be used in type scripts to guard cell transformation, in this case, I doubt it's gonna be slow. Besides, we are also working on this field to optimize both CKB VM and the VMs on top of CKB VM to make it faster and faster :P

To use duktape on CKB, first you need to compile duktape itself into a RISC-V executable binary:

```bash
$ git clone https://github.com/nervosnetwork/ckb-duktape
$ cd ckb-duktape
$ sudo docker run --rm -it -v `pwd`:/code nervos/ckb-riscv-gnu-toolchain:xenial bash
root@0d31cad7a539:~# cd /code
root@0d31cad7a539:/code# make
riscv64-unknown-elf-gcc -Os -DCKB_NO_MMU -D__riscv_soft_float -D__riscv_float_abi_soft -Iduktape -Ic -Wall -Werror c/entry.c -c -o build/entry.o
riscv64-unknown-elf-gcc -Os -DCKB_NO_MMU -D__riscv_soft_float -D__riscv_float_abi_soft -Iduktape -Ic -Wall -Werror duktape/duktape.c -c -o build/duktape.o
riscv64-unknown-elf-gcc build/entry.o build/duktape.o -o build/duktape -lm -Wl,-static -fdata-sections -ffunction-sections -Wl,--gc-sections -Wl,-s
root@0d31cad7a539:/code# exit
exit
$ ls build/duktape
build/duktape*
```

Like the carrot example, the first step here is to deploy duktape script code in a CKB cell:

```ruby
pry(main)> data = File.read("../ckb-duktape/build/duktape")
pry(main)> duktape_data.bytesize
=> 269064
pry(main)> duktape_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(280000), CKB::Utils.bin_to_hex(duktape_data))
pry(main)> duktape_data_hash = CKB::Blake2b.hexdigest(duktape_data)
pry(main)> duktape_out_point = CKB::Types::OutPoint.new(cell: CKB::Types::CellOutPoint.new(tx_hash: duktape_tx_hash, index: 0))
```

Unlike the carrot example, duktape script code now requires one argument: the JavaScript source you want to execute:

```ruby
pry(main)> duktape_hello_type_script = CKB::Types::Script.new(code_hash: duktape_data_hash, args: [CKB::Utils.bin_to_hex("CKB.debug(\"I'm running in JS!\")")])
```

Notice that with a different argument, you can create a different duktape powered type script for different use case:

```ruby
pry(main)> duktape_hello_type_script = CKB::Types::Script.new(code_hash: duktape_data_hash, args: [CKB::Utils.bin_to_hex("var a = 1;\nvar b = a + 2;")])
```

This echos the differences mentioned above on script code vs script: here duktape serves as a script code providing a JavaScript engine, while different script leveraging duktape script code serves different functionalities on chain.

Now we can create a cell with the duktape type script attached:

```ruby
pry(main)> tx = wallet.generate_tx(wallet2.address, CKB::Utils.byte_to_shannon(200))
pry(main)> tx.deps.push(duktape_out_point.dup)
pry(main)> tx.outputs[0].instance_variable_set(:@type, duktape_hello_type_script.dup)
pry(main)> tx.witnesses[0].data.clear
pry(main)> tx = tx.sign(wallet.key, api.compute_transaction_hash(tx))
pry(main)> api.send_transaction(tx)
=> "0x2e4d3aab4284bc52fc6f07df66e7c8fc0e236916b8a8b8417abb2a2c60824028"
```

We can see that the script executes successfully, and if you have `ckb-script` module's log level set to `debug` in your `ckb.toml` file, you can also notice the following log:

```bash
2019-07-15 05:59:13.551 +00:00 http.worker8 DEBUG ckb-script  script group: c35b9fed5fc0dd6eaef5a918cd7a4e4b77ea93398bece4d4572b67a474874641 DEBUG OUTPUT: I'm running in JS!
```

Now you have successfully deploy a JavaScript engine on CKB, and run JavaScript based script on CKB! Feel free to try any JavaScript code you want here.

# A Thought Exercise

Now you are familiar with CKB script basics, here's one thought exercise: in this post you've seen what an always-success script looks like, but what about an always-failure script? How small an always-faliure script(and script code) can be?

A hint: this is NOT a gcc flag-tweaking optimization contest, this is merely a thought exercise.

# Next

I know this is a long post, I hope you have tried this and successfully deployed a script to CKB. In the next post, we will introduce an important topic: how to issue your own user defined tokens(UDT) on CKB. The best part of UDTs on CKB, is that each user can store their UDTs in their own cells, which is different from ERC20 tokens on Ethereum, where everyone's token will have to live in the token issuer's single address. All of this can be achieved by using type scripts alone. If you are interested please stay tuned :)
