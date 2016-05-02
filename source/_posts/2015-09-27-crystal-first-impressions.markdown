---
layout: post
title: "Crystal First Impressions"
date: 2015-09-27 21:47
comments: true
categories:
 - Programming
 - Crystal
---


The [Crystal programming language](http://crystal-lang.org/) combines Ruby-like syntax with a really powerful compiler. As a result, it's fun to write, fast to run, and hard to screw up!

<!-- more -->

My Crystal experience so far:

- [danott](https://github.com/danott) mentioned it in our Slack a few weeks ago
- I read the great [Crystal docs](http://crystal-lang.org/docs/)
- I cobbled together [a lisp (barely)](https://github.com/rmosolgo/crythtal)

I'd say it's a combination of:

- a more-stable-Ruby (like Elixir, but without Erlang)
- a developer-friendly, life-embetter-ing type system (like Elm, but ... not JavaScript)
- a real compiler! (like C, but fun to read and write)

Um, what else could you want?! (See last paragraph 😛)

## Crystal Syntax

Crystal brings the best of Ruby:

- __Concise literals__, just like Ruby (take it for granted until you use regexps in Python 🙀)
- __Great OO support__, classes & modules just like Ruby
- __Attractive syntax__ thanks to blocks, operator overloading and optional parens
- __consistent__, predictable standard library (like Ruby)

Plus, some improvements over Ruby:

- __Method overloading__
- Python-like __keyword args__: must have default value, may be passed as kwargs or positional args (I could go either way on this since Ruby 2.1, but it beats `options={}`)
- More robust __Proc literals__, reminded me of Elixir
- Convention: __`?` methods return maybe-nil types__, while their counterparts raise on nil
- First-class __enums__ & __tuples__
- __Immutable strings__, like Ruby 3 will have (?)

For completeness, you lose some things from Ruby:

- Runtime __code creation__, like `define_method` & friends
- Runtime __code evaluation__, like `eval` & friends

Crystal offers a powerful __macro system__ that makes up for the loss of runtime metaprogramming. Unlike C preprossing, Crystal macros are awesome. You basically define functions which are called at compile-time, then generate code with liquid-like syntax.

## Crystal Typing

### Inferring Types

Crystal infers types from your code, so these are OK:

```ruby
my_string = "Hello World"
# String
my_hash = {key: "value", key2: "value2"}
# Hash(Symbol, String)
my_array = [1,2,3]
# Array(Int32)
```

When types mix, Crystal automatically unions them. It will ensure any usages of the variable in question are valid for both types. For example:

```ruby
my_variable = "string"
my_variable = 1
# String | Int32

# Ok, because String & Int32 both implement #to_f
my_variable.to_f

# You can add runtime checks to call type-specific methods
if my_variable.is_a?(String)
  my_variable.upcase
end
```

There are some times you need to define types to help the compiler. For example, there aren't any values here to tell the compiler what to expect:

```ruby
some_array =  [] of Int32
# You can use custom types, too
some_hash =   {} of Symbol => SomeCustomClass
```

### Goodbye, NoMethodErrors

If you're like me, you hate this:

```
undefined method `whatever' for nil:NilClass
```

Something somehow became nil. 😢

Instead, Crystal reads your code, and if there's somewhere a value could be nil, it throws a compile error:

```
in ./src/lisp/binding.cr:55: undefined method 'find_owner' for Nil

      @parent.find_owner(key)
              ^~~~~~~~~~
```

You have two options:

- Add an explicit not-nil check (`if object.is_a?(String) ...`) so the compiler knows it will be safe
- Refactor so the value won't be nil

Of course, the first one seems better at the start, but I hope to get better at the second one 😁.

## What's Missing?

Crystal really shows its youth. Its shortcomings all fall in that vein:

- __Poorly documented__, which isn't so bad if you're coming from Ruby
- __Few projects__ out there (I think the [package repository is a free Heroku app]( http://crystalshards.herokuapp.com/))
- Standard library has __some kinks__, they say it is still changing

One example of a standard library kink is the handling of `break`, `next` and `return` in blocks. If you want to exit a block early, you have to choose one of those three. The problem is that, to choose the right one, you have to know whether the method captures the block into a proc or simply yields values to it. It's a drag to have to know a method's implementation to call it! (IRL, I didn't run into this and I suspect it would be easy enough to work around it.)

## Now What?

I really liked Crystal and I hope I can work with it more!
