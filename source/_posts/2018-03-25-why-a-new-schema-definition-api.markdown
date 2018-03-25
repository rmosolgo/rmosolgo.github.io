---
layout: post
title: "Why a New Schema Definition API?"
date: 2018-03-25 13:59
comments: true
categories:
- GraphQL
- Ruby
---

GraphQL-Ruby `1.8.0` will have an new class-based API for defining your schema. Let's investigate the design choices in the new API.

<!-- more -->

The new API is backwards-compatible and can coexist with type definitions in the old format. See [the docs](https://github.com/rmosolgo/graphql-ruby/blob/1.8-dev/guides/schema/class_based_api.md#compatibility--migration-overview) for details. `1.8.0.pre` versions are available on RubyGems now and are very stable -- that's what we're running at GitHub!

## Problems Worth Fixing

Since starting at GitHub last May, I've entered into the experience of a huge-scale GraphQL system. Huge scale in lots of ways: huge schema, huge volume, and huge developer base. One of the problems that stood out to me (and to lots of us) was that GraphQL-Ruby simply _didn't help_ us be productive. Elements of schema definition hindered us rather than helped us.

So, our team set out on remaking the GraphQL-Ruby schema definition API. We wanted to address a few specific issues:

- __Familiarity__. GraphQL-Ruby's schema definition API reflected GraphQL and JavaScript more than it reflected Ruby. (The JavaScript influence comes from `graphql-js`, the reference implementation.) Ruby developers couldn't bring their usual practices into schema development; instead, they had to learn a bunch of new APIs and figure out how to work them together.
- __Rails Compatibility__, especially constant loading. A good API would work seamlessly with Rails development configurations, but the current API has some gotchas regarding circular dependencies and reloading.
- __Hackability__. Library code is fine _until it isn't_, and one of the best (and worst) things about Ruby is that all code is open to extension (or monkey-patching 🙈). At best, this means that library users can customize the library code in straightforward ways to better suit their use cases. However, GraphQL-Ruby didn't support this well: to support special use cases, customizations had to be hacked in in odd ways that were hard to maintain and prone to breaking during gem updates.

Besides all that, we needed a _safe_ transition, so it had to support a gradual adoption.

After trying a few different possibilities, the team decided to take a class-based approach to defining GraphQL schemas. I'm really thankful for their support in the design process, and I'm indebted to the folks at Shopify, who used a class-based schema definition system from the start (as a layer on top of GraphQL-Ruby) and [presented their work](https://www.youtube.com/watch?v=Wlu_PWCjc6Y) early on.

## The new API, from 10,000 feet

In short, GraphQL types used to be singleton instances, built with a [block-based API](https://twitter.com/krainboltgreene/status/971797438070599680):

```ruby
Types::Post = GraphQL::ObjectType.define {
  # ...
}
```

Now, GraphQL types are classes, with a DSL implemented as class methods:

```ruby
class Types::Post
  # ...
end
```

Field resolution was previously defined using Proc literals:

```ruby
field :comments, types[Types::Comments] do
  argument :orderBy, Types::CommentOrder
  resolve ->(obj, args, ctx) {
    obj.comments.order(args[:orderBy])
  }
end
```

Now, field resolution is defined with an instance method:

```ruby
field :comments, [Types::Comments], null: true do
  argument :order_by, Types::CommentOrder, required: false
end

def comments(order_by: nil)
  object.comments.order(order_by)
end
```

How does this address the issues listed above?

## More Familiarity

First, using classes reduces the "WTF" factor of GraphQL definition code. A seasoned Ruby developer might (rightly) smell foul play and reject GraphQL-Ruby on principle. (I was not seasoned enough to detect this when I designed the API!)

Proc literals are rare in Ruby, but common in GraphQL-Ruby's `.define { ... }` API. Their lexical scoping rules are different than method scoping rules, making it hard to remember what _was_ and _wasn't_ in scope during field resolution (for example, what was `self`?). To make matters worse, _some_ of the blocks in the `.define` API were `instance_eval`'d, so their `self` would be overridden. Practically, this meant that typos in development resulted in strange `NoMethodError`s.

Proc literals also have performance downsides: they're not optimized by CRuby, so they're [slower than method calls](https://gist.github.com/rmosolgo/6c6a7d787e0f1666f4c6d858c8402a01#gistcomment-1843329). Since they capture a lexical scope, they may also have [unexpected impacts on memory footprint](https://github.com/github/graphql-client/pull/139) (any local variable may be retained, since it might be accessed by the proc). The solutions here are simple: just use methods, the way Ruby wants you to! 😬

In the new class-based API, there are no proc literals (although they're supported for compatibility's sake). There are some `instance_eval`'d blocks (`field(...) { }`, for example), but field resolution is _just an instance method_ and the type definition is a normal class, so module scoping works normally. (Contrast that with the constant assignment in `Types::Post = GraphQL::ObjectType.define { ... }`, where no module scope is used). Several hooks that were previously specified as procs are now class methods, such as `resolve_type` and `coerce_input` (for scalars).

Overriding `!` is another particular no-no I'm correcting. At the time, I thought, "what a cool way to bring a GraphQL concept into Ruby!" This is because GraphQL non-null types are expressed with `!`:

```ruby
# This field always returns a User, never `null`
author: User!
```

So, why not express the concept with Ruby's `!` method (which is usually used for negation)?

```ruby
field :author, !User
```

As it turns out, there are several good reasons for _why not_!

- Overriding `!` breaks the negation operator. ActiveSupport's `.present?` didn't work with type objects, because `!` didn't return `false`, it returned a non-null type.
- Overriding the `!` operator throws people off. When a newcomer sees GraphQL-Ruby sample code, they have a WTF moment, followed by the dreadful memory (or discovery) that Ruby allows you to override `!`.
- There's very little value in importing GraphQL concepts into Ruby. GraphQL-Ruby developers are generally seasoned Ruby developers who are just learning GraphQL, so they don't gain anything by the similarity to GraphQL.

So, overriding `!` didn't deliver any value, but it did present a roadblock to developers and break some really essential code.

In the new API, nullability is expressed with the options `null:` and `required:` instead of with `!`. (But, you can re-activate that override for compatibility while you transition to the new API.)

By switching to Ruby's happy path of classes and methods, we can help Ruby developers feel more at home in GraphQL definitions. Additionally, we avoid some unfamiliar gotchas of procs and clear a path for removing the `!` override.

## Rails Compatibility

Rails' automatic constant loading is wonderful ... until it's _not_! GraphQL-Ruby didn't play well with Rails' constant loading especially when it came to cyclical dependencies, and here's why.

Imagine a typical `.define`-style type definition, like this:

```ruby
Types::T = GraphQL::ObjectType.define { ... }
```

We're assigning the constant `Types::T` to the return value of `.define { ... }`. Consequently, the constant is not defined _until_ `.define` returns.

Let's expand the example to two type definitions:

```ruby
Types::T1 = GraphQL::ObjectType.define { ... }
Types::T2 = GraphQL::ObjectType.define { ... }
```

If `T1` depends on `T2`, _and_ `T2` depends on `T1`, how can this work? (For example, imagine a `Post` type whose `author` field returns a `User`, and a `User` type whose `posts` field returns a list of `Post`s. This kind of cyclical dependency is common!) GraphQL-Ruby's solution was to adopt a JavaScriptism, a _thunk_. (Technically, I guess it's a functional programming-ism, but I got it from `graphql-js`.) A _thunk_ is an anonymous function used to defer the resolution of a value. For example, if we have code like this:

```ruby
field :author, Types::User
# NameError: uninitialized constant Types::User
```

GraphQL-Ruby would accept this:

```ruby
field :author, -> { Types::User }
# Thanks for the function, I will call it later to get the value!
```

Later, GraphQL-Ruby would `.call` the proc and get the value. At that type, `Types::User` would properly resolve to the correct type. This _worked_ but it had two big downsides:

- It added an unfamiliar construct (`Proc`) in an unfamiliar context (a method argument), so it was frustrating and disorienting.
- It added visual noise to the source code.

How does switching to classes resolve this issue? To ask the same question, how come we don't experience this problem with normal Rails models?

Part of the answer has to do with _how classes are evaluated_. Consider two classes in two different files:

```ruby
# app/graphql/types/post.rb
module Types
  class Post < BaseObject
    field :author, Types::User, null: false
  end
end
# app/graphql/types/user.rb
module Types
  class User < BaseObject
    field :posts, [Types::Post], null: false
  end
end
```

Notice that `Post` depends on `User`, and `User` depends on `Post`. The difference is how these lines are evaluated, and when the constants become defined. Here's the same code, with numbering to indicate the order that lines are evaluated:

```ruby
# Let's assume that `Post` is loaded first.
# app/graphql/types/post.rb
module Types                                  # 1, evaluation starts here
  class Post < BaseObject                     # 2, and naturally flows here, constant `Types::Post` is initialized as a class extending BaseObject
    field :author, Types::User, null: false   # 3, but when evaluating `Types::User`, jumps down below
  end                                         # 9, execution resumes here after loading `Types::User`
end                                           # 10
# app/graphql/types/user.rb
module Types                                  # 4, Rails opens this file looking for `Types::User`
  class User < BaseObject                     # 5, constant `Types::User` is initialized
    field :posts, [Types::Post], null: false  # 6, this line finishes without jumping, because `Types::Post` is _already_ initialized (see `# 2` above)
  end                                         # 7
end                                           # 8
```

Since `Types::Post` is _initialized_ first, then built-up by the following lines of code, it's available to `Types::User` in the case of a circular dependency. As a result, the thunk is not necessary.

This approach isn't a silver bullet -- `Types::Post` is not fully initialized by the time `Types::User` needs it -- but it reduces visual friction and generally plays nice with Rails out of the box.

## Hackability

I've used a naughty word here, but in fact, I'm talking about something very good. Have you ever been stuck with some dependency that didn't quite fit your application? (Or, maybe you were stuck on an old version, or your app needed a new feature that wasn't quite supported by the library.) Like it or not, sometimes the only way forward in a case like that is to hack it: reopen classes, redefine methods, mess with the inheritance chain, etc. Yes, those choices come with maintenance downsides, but sometimes they're really the best way forward.

On the other hand, really flexible libraries are _ready_ for you to come and extend them. For example, they might provide base classes for you to extend, with the assumption that you'll override and implement certain methods. In that case, the same hacking techniques listed above have found their time to shine.

`ActiveRecord::Base` is a great example of both cases: plenty of libraries hack methods right into the built-in class (for example, `acts_as_{whatever}`), and also, lots of Rails apps use an `ApplicationRecord` class for their application-specific customizations.

Since GraphQL-Ruby didn't use the familiar arrangement of classes and methods, it was closed to this kind of extension. (Ok, you _could_ do it, but it was a lot of work! And who wants to do that!?) In place of this, GraphQL-Ruby had yet-another-API for extending its DSL. Yet another thing to learn, with more Proc literals 😪.

Using classes simplifies this process because you can use familiar Ruby techniques to build your GraphQL schema. For example, if you want to share code between field resolvers, you can `include` a module and call its methods. If you want to make shorthands for common cases in your app, you can use your `Base` type classes. If you want to add special configuration to your types, you can use class methods. And, whenever that day should come, when you need to monkey-patch GraphQL-Ruby internals, I hope you'll be able to find the right spot to do it!

## Stay Classy

GraphQL-Ruby is three years old now, and I've learned a LOT during that time! I'm really thankful for the opportunity to focus on _developer productivity_ in the last few months, learning how I've prevented it and working on ways to improve it. I hope to keep working on topics like this -- how to make GraphQL more productive for Ruby developers -- in the next year, especially, so if you have feedback on this new API, please [open an issue](https://github.com/rmosolgo/graphql-ruby/issues/new) to share it!

I'm excited to see how this new API changes the way people think about GraphQL in Ruby, and I hope it will foster more creativity and stability.
