---
layout: post
title: "Summer Reading: Specializing Ruby"
date: 2016-08-06 11:10
categories:
- Ruby
- Language Implementation
---

[_Specialising Dynamic Techniques for Implementing the Ruby Programming Language_](http://chrisseaton.com/phd/) ("Specializing Ruby") is approachable and enjoyable (despite being a PhD thesis 😝).

<!-- more -->

_Specializing Ruby_ describes [Chris Seaton](https://twitter.com/ChrisGSeaton)'s work on [JRuby+Truffle](http://chrisseaton.com/rubytruffle/). It seems to be aimed at an unfamiliar audience, so it's loaded with background information and careful explanations. Those were a big benefit to me! I'll describe a few things that I enjoyed the most:

- Introduction to Truffle and Graal
- Optimizing Metaprogramming with Dispatch Chains
- Zero-Overhead Debugging
- Interpreting Native Extensions

## Introduction to Truffle and Graal

Seaton's work is built on top of two existing Java projects: __Truffle__ and __Graal__ (pronunciation: 😖❓).

Truffle is a _language implementation framework_ for _self-optimizing AST interpreters_. This means:

- Truffle is for _implementing languages_. People have used Truffle to implement many languages, including Ruby, C, and Python.
- Truffle languages are _AST interpreters_. A Truffle language parses its source code into a tree of nodes (the _abstract syntax tree_, AST), which represents the program. Then, it executes the program by traversing the tree, taking actions at each node.
- Truffle languages can _self-optimize_. Nodes can observe their execution and replace themselves with optimized versions of themselves.

Graal is a _dynamic compiler_ for the JVM, written in Java. A few points about Graal:

- It's a just-in-time compiler, so it improves a program's performance while the program runs.
- Graal is written in Java, which means it can expose its own APIs to other Java programs (like Truffle).
- Graal includes a powerful system for _de-optimizing_. This is especially important for Ruby, since Ruby's metaprogramming constructs allow programs to define new behavior for themselves while running.

Truffle has a "Graal backend," which supports close cooperation between the two. Together, they make a great team for language implementation: Truffle provides a simple approach to language design and Graal offers a means to optimize all the way to machine code.

## Optimizing Metaprogramming with Dispatch Chains

This is a novel optimization technique for Ruby, described in section 5.

Since Ruby is dynamic, method lookups must happen at runtime. In CRuby, call sites have _caches_ which store the result of method lookups and may short-circuit the lookup next time the call happens.

```ruby
some_object.some_method(arg1, arg2)
#          ^- here's the call site
#             the _actual_ method definition to use
#             depends on `some_object`'s class, which is unknown
#             until the program is actually running
```

One such cache is a _polymorphic inline cache_, which is roughly a map of `Class => method` pairs. When CRuby starts the call, it checks the cache for the current receiver's class. On a cache hit, it uses the cached method definition. On a cache miss, it looks up a definition and adds it to the cache.

The cache might look like this:

```ruby
some_object.some_method(arg1, arg2)
# Cache:
#   - SomeObject => SomeObject#some_method
#   - SomeOtherObject => SomeOtherObject#method_missing
```

In some cases, CRuby declares bankruptcy. Dynamic method calls (`.send`) are not cached!

```ruby
some_object.send(method_name, arg1, arg2)
#          ^- who knows what method to call!?!?
```

JRuby+Truffle's solution to this challenge is _dispatch chains._ Each call site (including `.send`) gets a dispatch chain, which is a like two-layer cache. First, it stores the _name_ of the method. Then, it stores the _class_ of the receiver. For a "static" method call, it looks like this:

```ruby
some_object.some_method(arg1, arg2)
# - "some_method" =>
#    - SomeObject => SomeObject#some_method
#    - SomeOtherObject => SomeOtherObject#method_missing
```

And for a dynamic method call, it caches _each_ method name:

```ruby
some_object.send(method_name, arg1, arg2)
# - "some_method" =>
#    - SomeObject => SomeObject#some_method
#    - SomeOtherObject => SomeOtherObject#method_missing
# - "some_other_method" =>
#    - SomeObject => SomeObject#some_other_method
```

In this respect, JRuby+Truffle treats _every_ method call like a `.send(...)`. This cache is implemented with Truffle nodes, so it's optimized as much as the rest of the program.

I wonder if this kind of method cache could be implemented for CRuby!

## Zero-Overhead Debugging

Debugging in JRuby+Truffle (described in section 6) is a tour de force for the Truffle-Graal combo. Other Rubies incur big performance penalties for debugging. Some require a special "debug" flag. But Seaton implements zero-overhead, always-available debugging by applying Truffle concepts in a new way.

Debugging hooks (such as the beginning of a new line) are added as "transparent" Truffle AST nodes, analogous to CRuby's `trace` instruction. By default, they don't do anything -- they just call through to their child nodes. Since they're "just" Truffle nodes, they're optimized like the rest of the program (and since they're transparent, they're optimized away completely). When those nodes are targeted for debugging, they're de-optimized, updated with the appropriate debug code, and the program continues running (and self-optimizing). When the debugger is detached, the node de-optimizes again, replaces itself with transparent nodes again, and the program resumes.

This chapter included a good description of Graal's `Assumption` concept. Assumptions are attached to optimized code. As long as `isValid()` is true, optimized code is executed. However, when an assumption is marked as invalid, Graal transfers execution back to the interpreter. Debugging takes advantage of this construct: debug nodes are transparent under the assumption that no debugger is attached to them. But when a developer attaches a debugger, then that assumption is invalidated and Graal de-optimizes and starts interpreting with the new debug nodes. Removing a debugger does the same thing: it invalidates an assumption, automatically de-optimizing the compiled code.

## Interpreting Native Extensions

Truffle: if it's not solving your problems, you're not using enough of it!

Throughout the paper, Seaton points out the "real-world" challenge of any new Ruby implementation: it simply _must_ support _all_ existing code, including C extensions! If you require developers to rewrite code for a new implementation, they probably won't bother with it.

He also points out that CRuby's C API is an implementer's nightmare (my words, not his). It's tightly coupled to CRuby's implementation it provides direct access to CRuby's memory (eg, string pointers).

Truffle's design offers a solution to this problem. Truffle languages implement common interfaces for AST nodes and objects, meaning that they can be _shared_ between languages! With this technique, JRuby+Truffle can implement Ruby's C API by interpreting C with Truffle. Since it's "just Truffle", C and Ruby ASTs can be seamlessly merged. They are even optimized together, just like a pure-Ruby program.

Seaton describes some particular techniques for adapting the pre-existing TruffleC project to the Ruby C API. In typical fashion, JRuby+Truffle outpaces CRuby -- even for C extensions!

## Conclusion

The only remaining question I have is, how bad is warm-up cost in practice? All of JRuby+Truffle's benchmarks are at "peak performance", but the system is "cold" at start-up, and many triggers in the program can cause the system to de-optimize. Is JIT warm-up a real issue?

"Optimizing Ruby" was a great read. Although I found the subject matter quite challenging, the writing style and occasional illustrations helped me keep up. Practically speaking, I can't use JRuby+Truffle until it runs all of Ruby on Rails, which isn't the case _yet_. I'm eager to see how this project matures!
