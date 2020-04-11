+++
title = "Diviner: A New Attempt on Deterministic Testing"
date = "2020-04-11"
+++

I've long been fascinated by the problem of deterministic execution. We've stuck so long on the multi-threaded model. Most of us have encountered bugs that only appear with some probabilities. Even though you have prepared a fix, you won't know for sure if it will occur again, all you can do is testing, testing and testing, hoping the problem won't appear again. It is in every engineer's dream, that we can deterministically debug and ensure that we can say with 100% certainty, that a problem has been eliminated.

For the past few months, I've been learning about [TLA+](https://lamport.azurewebsites.net/tla/tla.html), I do firmly believe now TLA+ is an invaluable tool in building sophisticated, multi-threaded, performant (and maybe also distributed) systems. I do prefer to build design first in TLA+ before writing a single line of code for all my projects. But TLA+ can only help you think about the design, and fix any design flaws. There is still the other side of story: actually implement the system. We could have a design validated by TLA+, but what if the code you write is vulnerable to some concurrency bugs that happens with certain probability?

There are, of course, some attempts at the solution, such as [rr](https://rr-project.org/). But one true gem in this area, is [FoundationDB](https://www.foundationdb.org/). If you don't know much about FoundationDB, specifically how they perform testing on it, I highly recommended the following 2 videos:

* <https://www.youtube.com/watch?v=4fFDFbi3toc>
* <https://www.youtube.com/watch?v=fFSPwJFXVlw>

What they did, is they build an actor model on top of C++, use the actor model to write the full database logic. As a result, they can inject the actor-based code into a deterministic testing framework to test all kinds of concurrency problems. Honestly I've watched the videos before, and in earlier time, I wasn't too impressed by their solution for one reason: their simulation framework runs **sequentially** in a single thread, this is far from a real setup, where you have multiple threads running together. The performance numbers you get from the simulation, don't make sense, either.

Luckily, I have a hobby of being a computer archaeologist: from time to time, I will dig out relatively older videos, and re-watch them for new insights. This is from a past experience, that many of the *new* inventions in this industry, are just re-discoveries of old topics, but bottled in modern programming tastes. When I recently dig out the FoundationDB videos and re-watched them, I found I've made a horrible, horrible mistake earlier. This is indeed something big.

# Testing Is Naturally Different From Benchmarks

The key wisdom here, is that testing is naturally different from doing benchmarks. The point of testing is never to get an actual number of running time, but to **explore** all the paths a program can take. Much like TLA+ would explore all the states in your design, a simulation will be more than enough if it can explore all the execution paths a piece of code can take. With code organized in actor model, your logic is naturally split into multiple small atomic pieces, as long as you can enumerate all the different execution orders a program can validly take, a single threaded testing framework can still explore all the paths a multi-threaded solution might result in!

And there is actually more benefits in a simulation environment: when your project is released, people might start to use it, meaning they will try to run your code in many different machines. All those machines will then explore different execution states your program can result in, in a way, we can think of all those machines are busy testing your program for bugs. In order to maintain the quality of your project, you would ideally want to find any new bugs before all those many different machines. Now the problem becomes a race at enumerating possible states and look for bugs. For popular projects, the number of machines run by the users will easily outgrow the machines owned by the project maintainers. The question is: how can you win this game of finding more bugs, but with much fewer machines?

The answer to this, lies in a simulation design like the FoundationDB solution: first, we organize the logic in an actor model framework, so we can use a single threaded simulation test executor to run the tests; second, we mock out all environment related code, such as timers, network IOs, file IOs, etc. This way we can distill the core of our project, which is also where most bugs would occur, into a single threaded, sequential code, with the following benefits:

* When a single test runs in a single threaded environment, a typical multi-core machine can be used to run multiple tests simultaneously;
* With all the IOs mocked out, we can run much fewer code in a test(e.g., we can skip the entire TCP/IP stack), resulting in much faster tests;
* Also with mocked IOs, it's much easier for us to simulate abnormalies, such as congested networks;

All of those benefits meaning the simulation solution can allow us to run much more tests on our code in much less time, giving us a chance to win the bug-finding game. In FoundationDB's example, their estimation is that in several years they have accumulated the [equivalent of a trillion CPU-hours of simulated stress testing](https://apple.github.io/foundationdb/engineering.html) via this design. Till this day, I have yet to see a more advanced testing framework design.

Now there is only one question: while this solution is great and proved to work well, can we leverage it elsewhere? Are we limited to the C++ actor framework? The question here, is of course no!

# Rust: A Natual Choice For Actor Based Simulation Testing

If we think about it, all it requires to do FoundationDB style deterministic simulation testing, is an actor based code, so we can re-organize them for testing needs. The exciting story here, is that Rust, our beloved solution for building high performance distributed software, is already [embracing](https://blog.rust-lang.org/2019/11/07/Async-await-stable.html) an async/await design, which is much like the actor model(well, I'm hardly a computer science professor, and I will leave it to the more qualified ones to tell if async/await is exactly actor model). To make it even more interesting, Rust's [swappable runtime](https://rust-lang.github.io/async-book/02_execution/04_executor.html) design makes it an even greater choice for such a deterministic simulation testing idea: all we need to do, is to use a different runtime in testing, and the problem will be solved.

That brings the leading role of this post: [diviner](https://github.com/xxuejie/diviner)

# Diviner

Once I had this idea, I felt it was so great, that I literally spent all my night time and weekends hacking on this idea, and built [diviner](https://github.com/xxuejie/diviner). It composes of 2 parts:

* A runtime that is designed to be single threaded and deterministic, so we can leverage it to build deterministic simulation tests;
* Wrappers on existing Rust async libraries. The wrappers would compile directly to existing implementations in normal mode(via inline functions and newtypes), but with a special `simulation` feature enabled, they will be compiled to the mock versions which integrate with the above runtime for deterministic testing. Right now I'm starting on [async-std](https://async.rs/), but more wrappers might be added later.

Combined together, diviner provides a FoundationDB style deterministic testing solution for async/await based Rust code. Several examples are provided [here](https://github.com/xxuejie/diviner#examples), showcasing the ability to manipulate time, which allows testing timeouts in a much faster way, as well the ability to test concurrent bugs. With a deterministic seed, diviner will run deterministically, giving you the chance to debug the code as many times as you want. And the beauty part of this, is that it is just natural async/await Rust code, we are not introducing anythning new with diviner.

I do have a different example that I like to make it work in the next couple of days:

```
use byteorder::{ByteOrder, LittleEndian};
use diviner::{
    net::{TcpListener, TcpStream},
    spawn, Environment,
};
use std::io;

async fn handle(stream: Tcpstream) {
    let mut buf = vec![];
    loop {
        let mut t = vec![0; 1024];
        let n = stream.read(&mut t).await.expect("read error!");
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&t[..n]);
        let l = LittleEndian::read_u32(&buf) as usize;
        if buf.len() >= l + 4 {
            let content = &buf[4..l + 4];
            stream.write(content).await.expect("write error!");
            buf = buf.drain(0..l + 4).collect();
        }
    }
}

async fn server(addr: String) -> Result<(), io::Error> {
    let mut listener = TcpListener::bind(addr).await?;

    while let Ok((stream, _)) = listener.accept().await {
        spawn(handle(stream));
    }
    Ok(())
}

fn main() {
    let e = Environment::new();
    let result = e.block_on(async {
        let addr = "127.0.0.1:18000";
        spawn(async {
            server(addr.to_string()).await.expect("server boot error!");
        });
        let data: Vec<u8> = vec![4, 0, 0, 0, 0x64, 0x61, 0x64, 0x61];
        for i in 1..data.len() {
            let mut client = TcpStream::connect(addr).await.expect("connect error!");
            client
                .write(&data[..i])
                .await
                .expect("client write 1 error!");
            client
                .write(&data[i..])
                .await
                .expect("client write 1 error!");
            let mut output: Vec<u8> = vec![0; 4];
            client.read(&mut output).await.expect("client read error!");
            if &output[..] != &data[4..] {
                panic!("Invalid response!");
            }
        }
    });
    match result {
        Ok(val) => println!("The task completed with {:?}", val),
        Err(err) => println!("The task has panicked: {:?}", err),
    }
}
```

This example showcases a typical newcomer mistakes: TCP/IP protocol is stream based, not packet based. While you might provide a buffer of 1KB, the protocol can respond you with any number of bytes, including only 1 byte of data in extreme scenarios. In a real testing, this is really hard to simulate, since you need to create an environment where TCP/IP is so congested, that it only has a very small congestion window. But with diviner, tweaking this in testing would be real simple. And the code you write, just uses TcpListener/TCPStream exactly like the same name structs from async-std. Yes you will have to use diviner to import them, but with inline functions and newtype patterns, performance will not be affected at all. Once you are willing to take this sacrifice, I believe you will discover a whole new world.

So that's what excites me lately. Right now diviner is still in its early days, I will continue to work on diviner in my free time to add the missing parts(such as all the missing wrappers from async-std). If you are interested, feel free to give it a try, and let me know how you feel about it :P
