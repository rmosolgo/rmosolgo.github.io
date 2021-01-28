---
layout: post
title: "A New Runtime in GraphQL-Ruby 1.9"
date: 2019-01-29 07:22
comments: true
categories:
  - Ruby
  - GraphQL
---

GraphQL-Ruby 1.9.0 introduces a new runtime called `GraphQL::Execution::Interpreter`. It offers better performance and some new features.

<!-- more -->

In [isolated benchmarks](https://github.com/rmosolgo/graphql-ruby/issues/861#issuecomment-458533219), the new runtime is about 50% faster. We saw about a 10% speedup in GitHub when we migrated.

You can opt in by adding to your schema:

```ruby
class MySchema < GraphQL::Schema
  # To use the new runtime
  use GraphQL::Execution::Interpreter
  # To skip preprocessing (you can use the interpreter without adding this)
  use GraphQL::Analysis::AST
end
```

But why rewrite?

## Problem 1: per-field context objects

Previously, each field evaluated by GraphQL-Ruby got its own instance of `GraphQL::Query::Context::FieldResolutionContext`. This was introduced so that fields using `graphql-batch`-style Promises could reliably access context values (like `ctx.path`) _after_ returning from the resolver (ie, when the promise was synced.)

The problem was, the bigger the response, the more `ctx` objects would be created -- and most of the time (for example, plain scalar fields), they were never _used_ by application code. So, we allocated, initialized, then GCed these objects for nothing!

In fact, it wasn't for _nothing_. As time passed, I started using those context objects inside execution code. For example, null propagation was implemented by climbing _up_ the tree of context objects. So you couldn't just _stop_ creating them -- the runtime depended on them.

### Solution: one mutable context

To remove this performance issue, I went _back_ to creating a single `Query::Context` object and passing it to resolvers. If you're using the new class-based API, you might have noticed that `self.context` is a `Query::Context`, not a `Query::Context::FieldResolutionContext`. I did it this way to pave the way for removing this bottleneck.

But what about access to runtime information?

### Solution: explicit requests for runtime info

For fields that _want_ runtime info (like `path` or `ast_node`), they can opt into it with `extras: [...]`, for example:

```ruby
field :items, ..., extras: [:path]
```

By adding that configuration, the requested value will be injected into the resolver:

```ruby
def items(path:)
  # ...
end
```

`path` will be a frozen Array describing the current point in the GraphQL response.

### Solution: reimplementing the runtime

Finally, since `FieldResolutionContext`s aren't necessary for user code, we can rewrite execution to _not_ create or use them anymore. Under the hood, `GraphQL::Execution::Interpreter` doesn't create those `ctx` objects. Instead, null propagation is implemented manually and all necessary values are passed from method to method.

## Problem 2: inefficient preprocessing

Years ago, someone requested the feature of _rejecting a query before running it_. They wanted to analyze the incoming query, and if it was too big or too complicated, reject it.

How could this be implemented? You could provide user access to the AST, but that would leave some difficult processing to user code, for example, merging fragments on interfaces.

So, I added `GraphQL::InternalRepresentation` as a normalized, pre-processed query structure. Before running a query, the AST was transformed into a tree of `irep_node`s. Users could analyze that structure and reject queries if desired.

In execution code, why throw away the result of that preprocessing? The runtime also used `irep_node`s to save re-calculating fragment merging.

In fact, even _static validation_ used the `irep_node` tree. At some point, rather than re-implement fragment merging, I decided to hook into that rewritten tree to implement `FragmentsWillMerge`. After all, why throw away that work?

(As it turns out, someone should fire the GraphQL-Ruby maintainer. These layers of code were _not_ well-isolated!!)

### Problem 2.1: Preparing the `irep_node`s was slow and often a waste

Since the `irep_node` tree was built for _analysis_, it generated branches for _every_ possible combination of interfaces, objects, and unions. This meant that, even for a query returning very simple data, the pre-processing step might be _very_ complex.

To make matters worse, the complexity of this preprocessing would grow as the schema grew. The more implementers an interface has, the longer it takes to calculate the possible branches in a fragment.

### Problem 2.2: Runtime features were implemented during preprocessing

Not only was the work complex, but it also couldn't be cached. This is because, while building the `irep_node` tree, `@skip` and `@include` would be evaluated with the current query variables. If nodes were skipped, they were left out of the `irep_node` tree.

This means that, for the _same_ query in your code base, you _couldn't_ reuse the `irep_node` tree, since the values for those query variables might be different from one execution to the next. Boo, hiss!

### Problem 2.3: A wacky preprocessing step is hard to understand

I want to empower people to use GraphQL-Ruby in creative ways, but throwing a wacky, custom data structure in the mix doesn't make it easy. I think an easier execution model will encourage people to learn how it works and build cool new stuff!

### Solution: No preprocessing

The new runtime evaluates the AST directly. Runtime features (`@skip` and `@include`, for example) are implemented at, well, _runtime_!

### Solution: AST Analyzers

Since you can't use the `irep_node` tree for analysis anymore, the library includes a new module, `GraphQL::Analysis::AST`, for preprocessing queries. Shout out to [@xuorig](https://github.com/xuorig) for this module!

### Solution: Moving ahead-of-time checks to runtime

For GitHub, we moved a lot of analyzer behavior to runtime. We did this because it's easier to maintain and requires less GraphQL-specific knowledge to understand and modify. Although the client experience is _slightly_ different, it's still good.

For example, we had an analyzer to check that pagination parameters (eg `first` and `last`) were valid. We moved this to runtime, adding it to our connection tooling.

### Solution: `GraphQL::Execution::Lookahead`

`irep_node`s _were_ useful for looking ahead in a query to see what fields would be selected next. (Honestly, they weren't _that good_, but they were the only thing we had, beside using the AST directly).

To support that use, we now have `extras: [:lookahead]` which will inject an instance of `GraphQL::Execution::Lookahead`, with an API _explicitly for_ checking fields later in the query.

## Other considerations

### Resolve procs are out

As part of the change with removing `FieldResolutionContext`, the new runtime doesn't support proc-style resolvers `->(obj, args, ctx) {...}`. Besides `ctx`, the `args` objects (`GraphQL::Query::Arguments`) are not created by the interpreter either. Instead, the interpreter uses plain hashes.

Instead of procs, methods on Object type classes should be used.

This means that proc-based features are also not supported. Field instrumenters and middlewares won't be called; a new feature called field extensions should be used instead.

### `.to_graphql` is _almost_ out

When the class-based schema API was added to GraphQL-Ruby, there was a little problem. The class-based API was great for developers, but the execution API expected legacy-style objects. The bridge was crossed via a compatibility layer: each type class had a `def self.to_graphql` method which returned a legacy-style object based on that class. Internally, the class and legacy object were cached together.

The interpreter _doesn't_ use those legacy objects, only classes. So, any type extensions that you've built will have to be supported on those _classes_.

The catch is, I'm not _100% sure_ that uses of legacy objects have all been migrated. In GitHub, we transitioned by delegating methods from the legacy objects to their source classes, and I haven't removed those delegations yet. So, there might still be uses of legacy objects 😅.

In a future version, I want to remove the use of those objects _completely_!

# Conclusion

I hope this post has clarified some of the goals and approaches toward adding the new runtime. I'm already building new features for it, like custom directives and better subscription support. If you have a question or concern, please [open an issue](https://github.com/rmosolgo/graphql-ruby/issues/new) to discuss!
