---
layout: post
title: "GraphQL Dataloader"
date: 2021-02-13 00:00
categories:
  - Ruby
  - GraphQL
---

GraphQL-Ruby 1.12 ships with a new `GraphQL::Dataloader` feature for batch-loading data.

<!-- more -->

It uses Ruby's [Fiber API](https://ruby-doc.org/core-3.0.0/Fiber.html) to manage data dependencies without any intermediary proxy or promise objects. You can enable it in your schema with:

```ruby
class MySchema < GraphQL::Schema
  # enable the new Fiber-backed batch loader
  use GraphQL::Dataloader
end
```

This blog post doesn't cover _how to use_ `GraphQL::Dataloader`, but you can find those docs [on GraphQL-Ruby's website](https://graphql-ruby.org/dataloader/overview.html).

Below, we'll investigate how it works, why I chose Fibers, and a list of caveats.

Many thanks to Matt Bessey, whose [proof-of-concept](https://github.com/bessey/graphql-fiber-test/tree/no-gem-changes) began my work on this feature.

## How It Works

Basically, the `GraphQL::Dataloader` has three steps:

1. Run GraphQL execution, but queue up jobs to _actually_ resolve fields or load arguments
2. Spin up Fibers to pull jobs that resolve fields (or load arguments). Those jobs re-enter Step 1 after the user code (field execution) has been called.

    Steps 1 and 2 happen concurrently: GraphQL execution queues up jobs, then the job runner starts running those jobs. The jobs themselves do two things:

    - Run application-defined code,
    - Then, re-enter GraphQL execution, which queues up more jobs

    However, the Fibers that run those jobs may _pause_ at any time. They may call `Fiber.yield`, which returns control to the parent Fiber. When this happens, the parent Fiber checks if the job queue has any remaining jobs; if it does, it creates a new Fiber to run those jobs until that Fiber pauses or no jobs remain on the queue.

    Jobs are drawn from the queue until no jobs remain. Any paused Fibers are stored for resuming later.

3. After the job queue is exhuasted, `GraphQL::Dataloader` initiates batched calls to external sources. After each source returns, it updates its own cache of results.

    When all external data sources have made their calls and populated their caches, the Fibers created by Step 2 are each resumed (once), which begins the back-and-forth between Step 1 and Step 2 above.

Let's look at each of those steps more closely.

### Step 1: GraphQL Execution

There are some parts of GraphQL that _never require external data_. For example:

- Merging selection sets from various parts of the query
- Enumerating the selections on an object and finding the corresponding field definitions
- Checking if the application's returned value for a field was `nil`
- Adding AST location info to an execution error

These operations can run without regard for batch loading. However, execution continues to operations which _may_ require external data:

- Loading objects by ID (eg `argument :post_id, ... loads: Types::Post`)
- Resolving fields (eg `field :author`)

In order to support batch loading, these operations are captured in jobs (which are `Proc`s) and pushed on to a queue (an `Array`) to be run later.

Before long, GraphQL-Ruby runs out of operations of the first kind (no data requirement) and queues up some jobs of the second kind (may require data).

At this point, `GraphQL::Dataloader` "runs" for the first time.

### Step 2: Run Jobs

A "job" is a Proc which may call `dataloader.yield`. By calling `dataloader.yield`, the job tells `GraphQL::Dataloader` "I am waiting for some batch-loaded data." Under the hood, `dataloader.yield` calls `Fiber.yield`, which causes the job to pause _in-place_ -- no further Ruby code will run until that Fiber is manually resumed.

A field might pause by calling `.load` on a source:

That is, fields call "sources" like this:

```ruby
field :author, Types::Author, null: true

def author
  Sources::Author.load(object.author_id)
end
```

`Source#load` is implemented to register a request for data, yield, then return the loaded value:

```ruby
class GraphQL::Dataloader::Source
  def load(key)
    if results.key?(key)
      results[key]
    else
      pending_keys << key
      dataloader.yield
      results[key]
    end
  end
end
```

In that way, `.load` _assumes_ that, after calling `dataloader.yield`, its cache will have been populated for any `pending_keys`.

Jobs that _don't pause_ will re-enter Step 1. That's because the job _contains_ a call to continue GraphQL execution. For example:

```ruby
dataloader.append_job {
  # Call user code
  result = graphql_field.call(object, arguments, context)
  # Store the return value
  update_response(path, result)
  # Continue evaluating the query
  continue_executing(graphql_field.return_type, result, context)
}
```

However, that continued GraphQL execution will eventually run out of no-data-requirement work to do, and may enqueue new jobs along the way. So, running jobs may cause more jobs to be added to the queue.

Jobs are run by a collection of Fibers, basically like this:

```ruby
while pending_jobs.any?
  f = Fiber.new {
    while (job = pending_jobs.shift)
      job.call
    end
  }
  f.resume
  if f.alive?
    paused_fibers << f
  end
end
```

In the end, we're left with:

- An empty job queue. (If there was more work that wasn't waiting for batched data, we'd want to run it.)
- A set of Fibers who yielded, and don't want to be resumed until their data is ready

### Step 3: Batch-load external data

Once we reach the end of the job queue, then we're left with a set of paused jobs, waiting for data to be ready. `GraphQL::Dataloader` responds by triggering batch loads for each "source" who received a request for data. (A `GraphQL::Dataloader::Source` is a "kind" of data that can be batch-loaded.)

It looks kind of like this:

```ruby
pending_sources.each do |source|
  source.load_requested_data
end
```

However, two factors complicate this:

- A source _may_ call out to another source. In this case, the source calls `dataloader.yield`.
- When that happens, we should take care to call the _dependency_ before resuming the dependent source.

So, those factors are addressed by:

- Batch-loading data inside Fibers, so that we can control their flow with `dataloader.yield` and `fiber.resume`.
- Using a stack instead of a queue, so that the must "urgent" sources are run next.

It ends up looking more like this:

```ruby
def create_source_fiber
  # This fiber will trigger batch loads until it runs out of
  # pending sources or `yield`s
  Fiber.new {
    while (source = pending_sources.shift)
      source.load_requested_data
    end
  }
end

source_fiber_stack = [create_source_fiber]
while (f = source_fiber_stack.pop)
  f.resume
  # If the fiber paused _in the middle_ of resolving data,
  # put the fiber back on the stack.
  if f.alive?
    source_fiber_stack << f
  end
  # But if there are any _more_ sources to run, make a new fiber
  # to run those sources _before_ resuming the paused one
  if pending_sources.any?
    source_fiber_stack << create_source_fiber
  end
end
```

When that concludes, we'll know that no more batch loading sources are pending.

### And Around Again

At that point, any Fibers that `dataloader.yield`ed in Step 2 can be resumed. `load_requested_data` will have populated internal caches, which will return values to those Fibers who requested them.

As described in Step 2, those Fibers will interleave GraphQL execution and application code until they all finish, or they all pause to wait for data.

And so on!

### What About Promises?

In fact, there's basically a _third_ kind of operation which can depend on external data loading, which is `.sync`ing Promises (as returned by the venerable batch-loading library `GraphQL::Batch`.) For this reason, the cycle described above also includes the Promise-syncing part of GraphQL-Ruby's runtime.

## Why Fibers?

My interest in Fibers was motivated by two things:

- Ruby 3's [Fiber Scheduler API](https://ruby-doc.org/core-3.0.0/Fiber/SchedulerInterface.html) (and [ioquatix's RubyKaigi presentation about it](https://youtu.be/Y29SSOS4UOc))
- [Matt Bessey's "why not..." tweet](https://twitter.com/mjhbessey/status/1341439453332697097) in December 2020

As proven in the prototype of a Fiber-backed dataloader, it's _possible_ to build batch loading into GraphQL-Ruby _without any_ proxy objects or promises. In my experience, those objects add a lot of cognitive overhead to the source code and, becuase they're unfamiliar, lead to subtle bugs or misbehaviors that we aren't great at identifying.

Additionally, the Fiber Scheduler API could give us parallel I/O "for free." In that setup, Fibers that make I/O or system calls _automatically_ call `Fiber.yield`. `GraphQL::Dataloader` could use that signal to start off with another Fiber, executing some other part of the GraphQL query. Beyond that, it looks like a Fiber scheduler should also be able to _resume_ Fibers in an evented manner. In my implementation described above, a long-running I/O call would cause any Fibers "behind" it to wait. But with an evented schedulers, you could resume Fibers with short-running external calls even while the long-running ones are still waiting to return.

## Caveats

Although I find these approaches really promising, I also see some possible trouble down the line:

- Fibers are not well-adopted in Ruby/Rails. `Thread.current[...]` values are not assigned inside new Fibers, and lots of libraries and applications use that for "global" context. (GraphQL-Ruby did, before this feature was added!)
- Fibers are hard to debug and profile. The backtrace of a Fiber begins with `Fiber.new`, so it loses some context. Ruby profilers (at least [ruby-prof](https://github.com/ruby-prof/ruby-prof/issues/271)) might not play nice with Fibers.

I haven't adopted this dataloader in my day job yet, but I hope I can make time to try it out soon and sort some of these out for myself.

## Conclusion

GraphQL-Ruby's new Fiber-backed dataloader offers a slick API and might bring parallel-by-default I/O to GraphQL execution.
