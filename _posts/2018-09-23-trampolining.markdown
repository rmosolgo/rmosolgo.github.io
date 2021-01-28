---
layout: post
title: "Trampolining"
date: 2018-09-23 21:04
comments: true
categories:
- Ruby
- Language Implementation
---

As part of my work on [improving GraphQL-Ruby's runtime performance](https://github.com/rmosolgo/graphql-ruby/pull/1394), I've been reading [_Essentials of Programming Languages_](http://www.eopl3.com/). Here, I try to apply their lesson about "trampolining".

<!-- more -->

__TL;DR:__ I applied a thing I read in a textbook and it:

- reduced the stack trace size by 80%
- reduced the live object count by 15%
- kept the same runtime speed

You can see the diff and benchmark results here: https://github.com/rmosolgo/graphql-ruby/compare/1b306fad...eef73b1

## The Problem

It's a bit funny, but it's not _totally clear_ to me what the book is trying to get at here. In the book, they talk about _control context_ or _continuations_ in a way that I would talk about "stack frames". I think the problem is this: when you implement a programming language as an interpreter, you end up with recursive method calls, and that recursion builds up a big stack in the host language. This is bad because it hogs memory.

I can definitely _imagine_ that this is a problem in Ruby, although I haven't measured it. GraphQL-Ruby uses recursion to execute GraphQL queries, and I can _imagine_ that those recursive backtrace frames hog memory for a couple reasons:

- The control frames themselves (managed by YARV or something) take up memory in their own right
- The control frames each have a lexical scope (`binding`), which, since it's still on the stack, can't be GCed. So, Ruby holds on to a lot of objects which _could_ be garbaged collected if the library was written better.

Besides that, the long backtrace adds a lot of noise when debugging.

## Trampolining

In the book, they say, "move your recursive calls to tail position, then, assuming your language has tail-call optimization, you won't have this problem." Well, my language _doesn't_ have tail-call optimization, so I _do_ have this problem! (Ok, it's an [option](https://ruby-doc.org/core-2.4.0/RubyVM/InstructionSequence.html#method-c-compile_option-3D).)

Luckily for me, they describe a technique for solving the problem _without_ tail-call optimization. It's called _trampolining_, and it works roughly like this:

> When a method _would_ make a recursive call, instead, return a `Bounce`. Then, the top-level method, which previously received the `FinalValue` of the interpreter's work, should be extended to accept _either_ a `FinalValue` or a `Bounce`. In the case of a `FinalValue`, it returns the value as previously. In the case of a `Bounce`, it re-enters the interpreter using the "bounced" value.

Using this technique, a previously-recursive method now _returns_, giving the caller some information about how to take the next step.

Let's give it a try.

## The Setup

I want to test impact in two ways: memory consumption and backtrace size. I want to measure these values _during_ GraphQL execution, so what better way to do it but build a GraphQL schema!

You can see the [whole benchmark](https://github.com/rmosolgo/graphql-ruby/compare/1b306fad...eef73b1#diff-7a29575d7b0f8a35812f9323ee46febe), but in short, we'll run a deeply-nested query, and at the deepest point, measure the _backtrace size_ and the number of live objects in the heap:

```ruby
{
  nestedMetric {
    nestedMetric {
      nestedMetric {
        # ... more nesting ...
        nestedMetric {
          backtraceSize
          objectCount
        }
      }
    }
  }
}
```

Where the fields are implemented by:

```ruby
def backtrace_size
  caller.size
end

def object_count
  # Make a GC pass
  GC.start
  # Count how many objects are alive in the heap,
  # subtracting the number of live objects before we started
  GC.stat[:heap_live_slots] - self.class.object_count_baseline
end
```

We'll use these measurements to assess the impact of the refactor.

## The Pledge: Recursive calls

To begin with, the interpreter is implemented as a set of recursive methods. The methods do things like:

- Given an object and a set of selections, resolve the selected fields on that object
- Given a value and a type, prepare the value for a GraphQL response according to the type

These methods are _recursive_ in the case of fields that return GraphQL objects. The first method resolves a field and calls the second method; then the second method, in order to prepare an object as a GraphQL response, calls back to the first method, to resolve selections on that object. For example, execution might work like this:

- Resolve selections on the root object
  - One of the selections returned a User
    - Resolve selections on the User
      - One of the selections returns a Repository
        - Resolve selections on the Repository
          - ...

Do you see how the same procedure is being applied over and over, in a nested way? That's implemented with recursive calls in GraphQL-Ruby.

We can run our test to see how the Ruby execution context looks in this case:

```ruby
# $ ruby test.rb
1b306fad3b6b35dd06248028883cd8a3ec4bdefd
{"backtraceSize"=>282, "objectCount"=>812}
```

This is the baseline for backtrace size and object count, which we're using to measure _memory overhead_ in GraphQL execution. (This describes behavior at [this commit](https://github.com/rmosolgo/graphql-ruby/commit/2401afc4a19f2e5616e1e155f953ec403bf4896c).)

## The Turn: Moving Recursive Calls into Tail Position

As a requirement for the final refactor, we have to do some code reorganization. In the current code, the recursive calls require some setup and teardown around them. For example, we track the GraphQL "path", which is the list of fields that describe where we are in the response. Here's a field with its "path":

```ruby
{
  a {
    b {
      c # The path of this field ["a", "b", "c"]
    }
  }
}
```

In the code, it looks something like this:

```ruby
# Append to the path for the duration of the nested call
@path.push(field_name)
# Continue executing, with the new path in context
execute_recursively(...)
# Remove the entry from `path`, since we're done here
@path.pop
```

The problem is, if I want to refactor `execute_recursively` to become a `Bounce`, it won't do me any good, because the value of `execute_recursively` _isn't returned_ from the method. It's not the last call in the method, so its value isn't returned. Instead, the value of `@path.pop` is returned. (It's not used for anything.)

This is to say: `@path.pop` is in _tail position_, the last call in the method. But I want `execute_recursively` to be in tail position.

### A Hack Won't Work

The easiest way to "fix" that would be to refactor the method to return the value of `execute_recursively`:

```ruby
# Append to the path for the duration of the nested call
@path.push(field_name)
# Continue executing
return_value = execute_recursively(...)
# Remove the entry from `path`, since we're done here
@path.pop
# Manually return the execution value
return_value
```

The problem is, when `execute_recursively` is refactored to be a `Bounce`:

```ruby
# Append to the path for the duration of the nested call
@path.push(field_name)
# Continue executing
bounce = prepare_bounce(...)
# Remove the entry from `path`, since we're done here
@path.pop
# Manually return the execution value
bounce
```

By the time the `bounce` is actually executed, `path` _won't have_ the changes I need in it. The value is pushed _and popped_ before the bounce is actually called.

### Pass the Path as Input

The solution is to remove the need for `@path.pop`. This can be done by creating a _new path_ and passing it as input.

```ruby
# Create a new path for nested execution
new_path = path + [field_name]
# Pass it as an input
execute_recursively(new_path, ...)
```

Now, `execute_recursively` is in tail position!

(The actual refactor is here: https://github.com/rmosolgo/graphql-ruby/commit/ef6e94283ecf280b14fe5417a4ee6896a06ebe69)

## The Prestige: Make it Bounce

Now, we want to replace recursive calls with a _bounce_, where a bounce is an object with enough information to continue execution at a later point in time.

Since my recursive interpreter is implemented with a bunch of stateless methods (they're stateless since the refactor above), I can create a Bounce class that will continue by calling the same method:

```ruby
class Bounce
  # Take the inputs required to call the next method
  def initialize(object, method, *arguments)
    @object = object
    @method = method
    @arguments = arguments
  end

  # Continue by calling the method with the given inputs
  def continue
    @object.send(@method, *@arguments)
  end
end
```

Then, I replace the tail-position recursive calls with bounces:

```diff
- execute_recursively(...)
+ Bounce.new(self, :execute_recursively, ...)
```

Instead of _growing_ the backtrace by calling another method, we'll be _shrinking_ the backtrace by returning from the current method with a Bounce.

You can see the refactor here: https://github.com/rmosolgo/graphql-ruby/commit/b8e51573652b736d67235080e8b450d6fc9cc92e

### How'd it work?

Let's run the test:

```ruby
# $ ruby test.rb
b8e51573652b736d67235080e8b450d6fc9cc92e
{"backtraceSize"=>55, "objectCount"=>686}
```

It's a success! The `backtraceSize` decreased from 282 to 55. The `objectCount` decreased from `812` to `686`.

### Implementation Considerations

__"Trampolining"__ is the process of taking each bounce and continuing it. In my first implementation, `def trampoline` looked like this:

```ruby
# Follow all the bounces until there aren't any left
def trampoline(bounce)
  case bounce
  when Bounce
    trampoline(bounce.continue)
  when Array
    bounce.each { |b| trampoline(b) }
  else
    # not a bounce, do nothing
  end
end
```

My test indicated no improvement in memory overhead, so I frustratedly called it quits. While brushing my teeth before bed, it hit me! I had unwittingly _re-introduced_ recursive method calls. So, I hurried downstairs and reimplemented `def trampoline` to use a `while` loop and a buffer of bounces, an approach which didn't grow the Ruby execution context. Then the test result was much better.

Another consideration is the _overhead of Bounces_ themselves. My first implementation creates a bounce before resolving each field. For very large responses, this will add a lot of overhead, especially when the field is a simple leaf value. This should be improved somehow.

## What about Speed?

It turns out that visitors to the website don't care about backtrace size or Ruby heap size, they just care about waiting for webpages to load. Lucky for me, my benchmark includes some runtime measurements, and the results were basically the same:

```text
# before
Calculating -------------------------------------
                         92.144  (±10.9%) i/s -    456.000  in   5.022617s
# after
Calculating -------------------------------------
                        113.529  (± 7.9%) i/s -    567.000  in   5.031847s
```

The runtime performance was very similar, almost within the margin of error. However, the consideration of Bounce overhead described above could cause _worse_ performance in some cases.

## What's next?

This code isn't _quite_ ready for GraphQL-Ruby, but I think it's promising for a few reasons:

- The reduction of memory overhead and backtrace noise could pay off for very large, nested queries
- I might be able to leverage bounces to give the caller more control over how GraphQL queries are executed. For example, at GitHub, we use GraphQL queries when rendering HTML pages. With some work, maybe we could alternate between bouncing GraphQL and rendering HTML, so we'd get a better progressive rendering experience on the front end.

However, one serious issue still needs to be addressed: what about the `Bounce`'s _own_ overhead? Allocating a new object for _every field execution_ is already a performance issue in GraphQL-Ruby, and I'm trying hard to remove it. So the implementation will need to be more subtle in that regard.
