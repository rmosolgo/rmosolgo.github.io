---
layout: post
title: "Parallelism in GraphQL-Ruby"
date: 2017-01-22 10:23
categories:
- Ruby
- GraphQL
---

It's possible to get IO operations running in parallel with the [`graphql` gem](https://github.com/rmosolgo/graphql-ruby).

<!-- more -->

I haven't tried this extensively, but I had to satisfy my curiosity!

## Setup: Long-Running IO

Let's say we have a GraphQL schema which has long-running IO- or system-bound tasks. Here's a silly example where the long-running task is `sleep`:

```ruby
QueryType = GraphQL::ObjectType.define do
  name "Query"
  field :sleep, !types.Int, "Sleep for the specified number of seconds" do
    argument :for, !types.Int
    resolve ->(o, a, c) {
      sleep(a["for"])
      a["for"]
    }
  end
end

Schema = GraphQL::Schema.define do
  query(QueryType)
end
```

Let's consider a query like this one:

```
query_str = <<-GRAPHQL
{
  s1: sleep(for: 3)
  s2: sleep(for: 3)
  s3: sleep(for: 3)
}
GRAPHQL

puts query_str

puts Benchmark.measure {
  Schema.execute(query_str)
}
```

How long will it take?

```
$ ruby graphql_parallel.rb
{
  s1: sleep(for: 3)
  s2: sleep(for: 3)
  s3: sleep(for: 3)
}
  0.000000   0.000000   0.000000 (  9.009428)
```

About 9 seconds: three `sleep(3)` calls in a row.

## Working in Another Thread

The [`concurrent-ruby` gem](https://github.com/ruby-concurrency/concurrent-ruby) includes `Concurrent::Future`, which runs a block in another thread:

```ruby
future = Concurrent::Future.execute do
  # This will be run in another thread
end


future.value
# => waits for the return value of the block
#    and returns it
```

We can use it to put our `sleep(3)` calls in different threads. There are two steps.

First, use a `Concurrent::Future` in the resolve function:

```diff
- sleep(a["for"])
- a["for"]
+ Concurrent::Future.execute {
+  sleep(a["for"])
+  a["for"]
+ }
```

Then, tell the Schema to handle `Concurrent::Future`s by calling `#value` on them:

```diff
 Schema = GraphQL::Schema.define do
   query(QueryType)
+  lazy_resolve(Concurrent::Future, :value)
 end
```

Finally, run the same query again:

```
$ ruby graphql_parallel.rb
{
  s1: sleep(for: 3)
  s2: sleep(for: 3)
  s3: sleep(for: 3)
}
  0.000000   0.000000   0.010000 (  3.011735)
```

🎉 Three seconds! Since the `sleep(3)` calls were in different threads, they were executed in parallel.

## Real Uses

Ruby can run IO operations in parallel. This includes filesystem operations and socket reads (eg, HTTP requests and database operations).

So, you could make external requests inside a `Concurrent::Future`, for example:

```ruby
Concurrent::Future.execute {
  open("http://wikipedia.org")
}
```

Or, make a long-running database call inside a `Concurrent::Future`:

```ruby
Concurrent::Future.execute {
  DB.exec(long_running_sql_query)
}
```

## Caveats

Switching threads incurs some overhead, so multithreading won't be worth it for very fast IO operations.

GraphQL doesn't know which resolvers will finish first. Instead, it starts each one, then blocks until the first one is finished. This means that subsequent long-running fields may have to wait longer than they "really" need to. For example, consider this query:


```
{
  sleep(for: 5)
  nestedSleep(for: 2) {
    sleep(for: 2)
  }
}
```

Even with multithreading, this would take about 7 seconds to execute. First, GraphQL would wait for `sleep(for: 5)`, then it would get to `nestedSleep(for: 2)`, which would have already finished, then it would execute `sleep(for: 2)`.

## Conclusion

If your GraphQL schema is wrapping pre-existing HTTP APIs, using a technique like this could reduce your GraphQL response time.
