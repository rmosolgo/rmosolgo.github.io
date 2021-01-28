---
layout: post
title: "Optimizing GraphQL-Ruby"
date: 2017-03-08 08:02
comments: true
categories:
- GraphQL
- Ruby
---

Soon, `graphql-ruby` 1.5.0 will be released. Query execution will be ~70% faster than 1.3.0!

<!-- more -->

Let's look at how we reduced the execution time between those two versions. Thanks to [@theorygeek](https://github.com/theorygeek) who optimized the middleware chain helped me pinpoint several other bottlenecks!

## The Benchmark

To track GraphQL execution overhead, I [execute the introspection query](https://github.com/rmosolgo/graphql-ruby/blob/master/benchmark/run.rb) on a [fixture schema](https://github.com/rmosolgo/graphql-ruby/blob/master/spec/support/dummy/schema.rb) in graphql-ruby's test suite.

On GraphQL 1.3.0, the benchmark ran around 22.5 iterations per second:

<p><img src="/assets/images/optimizing_graphql_ruby/1-3-0-bench.png" width="500" /></p>

On [master](https://github.com/rmosolgo/graphql-ruby/commit/943e68f40a11f3f809ecd8485282eccdd6a6991b), it runs around 38 iterations per second:

<p><img src="/assets/images/optimizing_graphql_ruby/1-5-0-bench.png" width="500" /></p>

That's almost 1.7x faster!

```ruby
38.0 / 22.5
# => 1.6888888888888889
```

So, how'd we do it?

## Looking Under the Hood with RubyProf

To find where time was spent, I turned to [ruby-prof](https://github.com/ruby-prof/ruby-prof). I [wrapped GraphQL execution](https://github.com/rmosolgo/graphql-ruby/pull/579) with profiling and inspected the result:

```text
Thread ID: 70149906635240
Fiber ID: 70149911114440
Total: 0.474618
Sort by: self_time

 %self      total      self      wait     child     calls  name
  4.60      0.074     0.022     0.000     0.052     6893  *Class#new
  3.99      0.019     0.019     0.000     0.000     8715  *GraphQL::Define::InstanceDefinable#ensure_defined
  3.13      0.015     0.015     0.000     0.000    25403   Module#===
  2.64      0.013     0.013     0.000     0.000     8813   Kernel#hash
  2.49      0.074     0.012     0.000     0.063     3496  *GraphQL::Schema::MiddlewareChain#call
  1.85      0.009     0.009     0.000     0.000     4184   GraphQL::Query::Context::FieldResolutionContext#query
  1.78      0.017     0.008     0.000     0.008     2141   #<Module:0x007f9a18de37a8>#type
  1.63      0.008     0.008     0.000     0.000     1960   GraphQL::Query::Context::FieldResolutionContext#initialize
  1.54      0.012     0.007     0.000     0.005     1748   GraphQL::Query#get_field
  1.53      0.014     0.007     0.000     0.006     1748   GraphQL::Query#arguments_for
  1.52      0.007     0.007     0.000     0.000     8356   Kernel#is_a?
  1.51      0.010     0.007     0.000     0.003     7523   Kernel#===
  1.44      0.022     0.007     0.000     0.015     1959   GraphQL::Query::Context::FieldResolutionContext#spawn
  1.32      0.012     0.006     0.000     0.006     1748   GraphQL::Execution::Lazy::LazyMethodMap#get
  1.31      0.010     0.006     0.000     0.003     1748   GraphQL::Execution::FieldResult#value=
  1.29      0.032     0.006     0.000     0.026     1748   GraphQL::Field#resolve
  1.25      0.042     0.006     0.000     0.037     1748   #<Module:0x007f9a18de37a8>#resolve
  1.16      0.015     0.006     0.000     0.010     1748   GraphQL::Execution::FieldResult#initialize
  1.06      0.010     0.005     0.000     0.005     2815   GraphQL::Schema::Warden#visible?
  1.05      0.014     0.005     0.000     0.009     1748   GraphQL::Schema::MiddlewareChain#initialize
  1.03      0.005     0.005     0.000     0.000     2815   <Module::GraphQL::Query::NullExcept>#call
  0.97      0.014     0.005     0.000     0.009      756   Hash#each_value
# ... truncated ...
```

A few things stood out:

- ~5% of time was spent during ~7k calls to `Class#new`: this is time spent initializing new objects. I think initialization can also trigger garbage collection (if there's not a spot on the free list), so this may include GC time.
- ~4% of time was spent during ~9k calls to `InstanceDefinable#ensure_defined`, which is part of graphql-ruby's definition API. It's _all_ overhead to support the definition API, 😿.
- Several methods are called `1748` times. Turns out, this is _once per field in the response_.
- With that in mind, `25,403` seems like a lot of calls to `Module#===`!

## Reduce GC Pressure

Since `Class#new` was the call with the most `self` time, I thought I'd start there. What kind of objects are being allocated? We can filter the profile output:

```text
~/code/graphql $ cat 130_prof.txt | grep initialize
  1.63      0.008     0.008     0.000     0.000     1960   GraphQL::Query::Context::FieldResolutionContext#initialize
  1.16      0.015     0.006     0.000     0.010     1748   GraphQL::Execution::FieldResult#initialize
  1.05      0.014     0.005     0.000     0.009     1748   GraphQL::Schema::MiddlewareChain#initialize
  0.69      0.006     0.003     0.000     0.002     1833   Kernel#initialize_dup
  0.46      0.002     0.002     0.000     0.000     1768   Array#initialize_copy
  0.30      0.001     0.001     0.000     0.000      419   GraphQL::Execution::SelectionResult#initialize
  0.28      0.001     0.001     0.000     0.000      466   Hash#initialize
  0.17      0.010     0.001     0.000     0.009       92   GraphQL::InternalRepresentation::Selection#initialize
  0.15      0.002     0.001     0.000     0.001      162   Set#initialize
  0.15      0.001     0.001     0.000     0.000       70   GraphQL::InternalRepresentation::Node#initialize
  0.07      0.001     0.000     0.000     0.001       58   GraphQL::StaticValidation::FieldsWillMerge::FieldDefinitionComparison#initialize
  0.04      0.001     0.000     0.000     0.000       64   GraphQL::Query::Arguments#initialize
  0.01      0.000     0.000     0.000     0.000       11   GraphQL::StaticValidation::FragmentsAreUsed::FragmentInstance#initialize
  0.01      0.000     0.000     0.000     0.000        1   GraphQL::Query#initialize
# ... truncated ...
```

Lots of GraphQL internals! That's good news though: those are within scope for optimization.

`MiddlewareChain` was ripe for a refactor. In the old implementation, _each_ field resolution created a middleware chain, then used it and discarded it. However, this was a waste of objects. Middlewares don't change during query execution, so we should be able to reuse the same list of middlewares for each field.

This required a bit of refactoring, since the old implementation modified the array (with `shift`) as it worked through middlewares. In the end, this improvement was added in [`5549e0cf`](https://github.com/rmosolgo/graphql-ruby/pull/462/commits/5549e0cff288a9aecd676603cbb62628a34b4ec8). As a bonus, the number of created `Array`s (shown by `Array#initialize_copy`) also declined tremendously since they were used for `MiddlewareChain`'s internal state. Also, calls to `Array#shift` were removed, since the array was no longer modified:

```text
~/code/graphql $ cat 130_prof.txt | grep shift
  0.61      0.003     0.003     0.000     0.000     3496   Array#shift
~/code/graphql $ cat 150_prof.txt | grep shift
~/code/graphql $
```

🎉 !

The number `FieldResult` objects was also reduced. `FieldResult` is used for execution bookkeeping in some edge cases, but is often unneeded. So, we could optimize by removing the `FieldResult` object when we had a plain value (and therefore no bookkeeping was needed): [`07cbfa89`](https://github.com/rmosolgo/graphql-ruby/commit/07cbfa89031819d3886f220de8256e83ff59f298)

A very modest optimization was also applied to `GraphQL::Arguments`, reusing the same object for empty argument lists ([`4b07c9b4`](https://github.com/rmosolgo/graphql-ruby/pull/500/commits/4b07c9b46345144c7d88e429e7b55e09b0615517)) and reusing the argument default values on a field-level basis ([`4956149d`](https://github.com/rmosolgo/graphql-ruby/pull/500/commits/4956149df0a4ab8a449679bcd9af20b3dad72585)).

## Avoid Duplicate Calculations

Some elements of a GraphQL schema don't change during execution. As long as this holds true, we can cache the results of some calculations and avoid recalculating them.

A simple caching approach is to use a hash whose keys are the inputs and whose values are the cached outputs:

```ruby
# Read-through cache for summing two numbers
#
# The first layer of the cache is the left-hand number:
read_through_sum = Hash.new do |hash1, left_num|
  # The second layer of the cache is the right-hand number:
  hash1[num1] = Hash.new do |hash2, right_num|

    # And finally, the result is stored as a value in the second hash:
    puts "Adding #{left_num} + #{right_num}"
    hash2[right_num] = left_num + right_num
  end
end

read_through_sum[1][2]
# "Adding 1 + 2"
# => 3

read_through_sum[1][2]
# => 3
```

The first lookup printed a message and returned a value but the second lookup did _not_ print a value. This is because the block wasn't called. Instead, the cached value was returned immediately.

This approach was applied aggressively to `GraphQL::Schema::Warden`, an object which manages schema visibility on a query-by-query basis. Since the visibility of a schema member would remain constant during the query, we could cache the results of visibility checks: first [`1a28b104`](https://github.com/rmosolgo/graphql-ruby/pull/462/commits/1a28b10494bf508519f8f9b4a1a589c458837cf7), then [`27b36e89`](https://github.com/rmosolgo/graphql-ruby/pull/462/commits/27b36e89ca24b1dc8ec3e2d27612a6fb99039e54).

This was also applied to field lookup in [`133ed1b1e`](https://github.com/rmosolgo/graphql-ruby/pull/402/commits/133ed1b1e0577df1db222a892d8afd95082c6d33) and to `lazy_resolve` handler lookup in [`283fc19d`](https://github.com/rmosolgo/graphql-ruby/pull/402/commits/283fc19d72eb9890ea6254f7fc79600f3f0bfbeb).

## Use `yield` Instead of `&block`

Due to the implementation of Ruby's VM, calling a block with [`yield` is much faster than `block.call`](https://github.com/JuanitoFatas/fast-ruby#proccall-and-block-arguments-vs-yieldcode). `@theorygeek` migrated `MiddlewareChain` to use that approach instead in [`517cec34`](https://github.com/rmosolgo/graphql-ruby/pull/462/commits/517cec3477097ddb05db0e02b6752be552d2e3dd).

## Remove Overhead from Lazy Definition API (warning: terrible hack)

In order to handle circular definitions, graphql-ruby's `.define { ... }` blocks aren't executed immediately. Instead, they're stored and evaluated only when a definition-dependent value is required. To achieve this, all definition-dependent methods were preceeded by a call to `ensure_defined`.

Maybe you remember that method from the _very top_ of the profiler output above:

```text
 %self      total      self      wait     child     calls  name
  4.60      0.074     0.022     0.000     0.052     6893  *Class#new
  3.99      0.019     0.019     0.000     0.000     8715  *GraphQL::Define::InstanceDefinable#ensure_defined
```

A fact about `GraphQL::Schema` is that, by the time it is defined, _all_ lazy definitions have been executed. This means that during query execution, calling `ensure_defined` is _always_ a waste!

I found a way to remove the overhead, but it was a huge hack. It works like this:

When a definition is added (with `.define`):

- store the definition block for later
- find each definition-dependent method definition on the defined object and gather them into an array:

  ```ruby
  @pending_methods = method_names.map { |n| self.class.instance_method(n) }
  ```
- _replace_ those methods with dummy methods which:
  - call `ensure_defined`
  - re-apply all `@pending_methods`, overriding the dummy methods
  - call the _real_ method (which was just re-applied)


This way, subsequent calls to definition-dependent methods _don't_ call `ensure_defined`. `ensure_defined` removed itself from the class definition after its work was done!

You can see the whole hack in [`18d73a58`](https://github.com/rmosolgo/graphql-ruby/pull/483/commits/18d73a58314cab96c28a9861506b6ad18c8df3aa). For all my teasing, this is something that makes Ruby so powerful: if you can imagine it, you can code it!

## The Final Product

Two minor releases later, the profile output is looking better! Here's the output on master:

```text
Thread ID: 70178713115080
Fiber ID: 70178720382840
Total: 0.310395
Sort by: self_time

 %self      total      self      wait     child     calls  name
  4.06      0.013     0.013     0.000     0.000     7644   Kernel#hash
  2.93      0.021     0.009     0.000     0.012     2917  *Class#new
  2.89      0.009     0.009     0.000     0.000     4184   GraphQL::Query::Context::FieldResolutionContext#query
  2.74      0.009     0.009     0.000     0.000    13542   Module#===
  2.60      0.008     0.008     0.000     0.000     1960   GraphQL::Query::Context::FieldResolutionContext#initialize
  2.27      0.013     0.007     0.000     0.006     1748   GraphQL::Query#arguments_for
  2.25      0.010     0.007     0.000     0.003     7523   Kernel#===
  2.14      0.022     0.007     0.000     0.015     1959   GraphQL::Query::Context::FieldResolutionContext#spawn
  2.09      0.007     0.007     0.000     0.000     8260   Kernel#is_a?
  1.87      0.039     0.006     0.000     0.033     1748   GraphQL::Schema::RescueMiddleware#call
  1.75      0.013     0.005     0.000     0.008     1748   GraphQL::Execution::Lazy::LazyMethodMap#get
  1.69      0.005     0.005     0.000     0.000     2259   Kernel#class
  1.68      0.044     0.005     0.000     0.039     3496  *GraphQL::Schema::MiddlewareChain#invoke_core
  1.33      0.004     0.004     0.000     0.000     1747   GraphQL::Query::Context::FieldResolutionContext#schema
  1.31      0.029     0.004     0.000     0.025     1748   <Module::GraphQL::Execution::Execute::FieldResolveStep>#call
  1.20      0.004     0.004     0.000     0.000     1748   GraphQL::Execution::SelectionResult#set
  1.15      0.048     0.004     0.000     0.044     1748   GraphQL::Schema::MiddlewareChain#invoke
  1.14      0.017     0.004     0.000     0.013     1748   GraphQL::Schema#lazy_method_name
  1.07      0.004     0.003     0.000     0.001     1044   Kernel#public_send
  1.05      0.020     0.003     0.000     0.017     1748   GraphQL::Schema#lazy?
  1.02      0.004     0.003     0.000     0.000     1806   GraphQL::InternalRepresentation::Node#definition
```

Here are the wins:

- Object allocations reduced by 58%
- Method calls to gem code and Ruby built-ins reduced by ... a lot!
- Calls to `ensure_defined` reduced by 100% 😆

And, as shown in the benchmark above, 1.7x faster query execution!

There's one caveat: these optimization apply to the GraphQL runtime _only_. _Real_ GraphQL performance depends on more than that. It includes application-specific details like database access, remote API calls and application code performance.
