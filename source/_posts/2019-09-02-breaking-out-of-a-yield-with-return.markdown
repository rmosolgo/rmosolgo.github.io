---
layout: post
title: "Breaking out of a yield with return"
date: 2019-09-02 11:28
comments: true
categories:
- Ruby
---


Did you know that calling `return` in one Ruby method could affect the flow of another method? I discovered it today while hunting a [GraphQL-Ruby bugfix](https://github.com/rmosolgo/graphql-ruby/commit/400bb71bc). You can get more reliable behavior with `ensure`, if it's appropriate.

<!-- more -->

### Instrumentating a block

Let's imagine a simple instrumentation system, where method wraps a block of code and tags it with a name:

```ruby
def instrument_event(event_name)
  puts "begin    #{event_name}"
  result = yield
  puts "end      #{event_name}"
  result
end
```

You could use this to instrument a method call, for example:

```ruby
def do_stuff_with_instrumentation
  instrument_event("do-stuff") do
    do_stuff
  end
end

do_stuff_with_instrumentation
# begin    do-stuff
# end      do-stuff
```

It prints the `begin` message, then the `end` message.

### Returning early

But what if you return early from the block? For example:

```ruby
# @param return_early [Boolean] if true, return before actually doing the stuff
def do_stuff_with_instrumentation(return_early:)
  instrument_event("do-stuff") do
    if return_early
      # Return from this method ... but also return from the `do ... end` instrumentation block
      return
    else
      do_stuff
    end
  end
end
```

If you instrument it _without_ returning from inside the block, it logs normally:

```ruby
do_stuff_with_instrumentation(return_early: false)
# begin    do-stuff
# end      do-stuff
```

But, if you return early, you only get _half_ the log:

```ruby
do_stuff_with_instrumentation(return_early: true)
# begin    do-stuff
```

Where's the `end` message?

### It Jumped!

Apparently, the `return` inside the inner method (`#do_stuff_with_instrumentation`) broke out of its own method _and_ out of `#instrument_event`. I don't know why it works like that.

### With Ensure

If you refactor the instrumentation to use `ensure`, it won't have this issue. Here's the refactor:

```ruby
def instrument_event(event_name)
  puts "begin    #{event_name}"
  yield
ensure
  puts "end      #{event_name}"
end
```

Then, it prints normally:

```ruby
do_stuff_with_instrumentation(return_early: true)
# begin    do-stuff
# end      do-stuff
```

Of course, this also changes the behavior of the method when errors happen. The `ensure` code will be called _even if_ `yield` raises an error. So, it might not always be the right choice. (I bet you could use `$!` to detect a currently-raised error, though.)
