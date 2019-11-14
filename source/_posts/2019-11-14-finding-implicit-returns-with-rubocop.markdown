---
layout: post
title: "Finding implicit returns with Rubocop"
date: 2019-11-14 09:57
comments: true
categories:
- Ruby
- Rubocop
---

Some notes on a refactor implemented with a Cop.

<!-- more -->

I've developed a real affection for Rubocop over the last couple of years. (Sorry to my old coworkers and friends at Planning Center, who put up with my complaining about it back then!) What I've come to appreciate is:

- No fights about style. If it passes the linter, it's ok to ship.
- Using Rubocop to enforce usage conventions. For example, we have a cop to make sure that some risky methods aren't used in the codebase.
- Using Rubocop to upgrade old code to be compliant. For example, we realized we were sometimes using `Promise.all(...) do` instead of `Promise.all(...).then do`. The old code didn't work at all. We added a Cop with an `autocorrect` implementation, so we could upgrade any mistakes automatically!

## The Refactor: Returning Promises

We have some GraphQL/GraphQL-Batch code for making authorization checks. They look basically like this:

```ruby
class Types::Repository
  def authorized?(repository, ctx)
    # Load some data which is required for the check:
    batch_load(repository, :owner).then do |owner|
      # Call the authorization code:
      Authorization.can_see?(ctx[:viewer], repository, owner)
    end
  end
end
```

The `authorized?` check returns a `Promise` (for GraphQL-Batch), and inside that promise, `.can_see?` returns `true` or `false` (synchronously).

However, to improve data access, we wanted to implement a new authorization code path:

```ruby
# Returns Promise<true|false>
Authorization.async_can_see?(viewer, repo, owner)
```

This new code path would improve the database access under the hood to use our batch loading system.

After implementing the codepath, how could we update the ~1000 call sites to use the new method?

## The Problem: Boolean Logic

The easiest solution would be find-and-replace, but that doesn't quite work because of boolean logic with Promises. Some of our authorization checks combined two checks like this:

```ruby
# Require both checks to pass:
Authorization.can_see?(...) && Authorization.can_see?(...)
```

If we updated that to `async_can_see?`, that code would break. It would break because `async_can_see?` _always_ returns a `Promise`, which is truthy. That is:

```ruby
promise_1 && promise_2
```

That code _always_ returns true, even if one of the promises _would_ resolve to `false`. (The Ruby `Promise` object is truthy, and we don't have access to the returned value until we call `promise.sync`.)

So, we have to figure out _which code paths_ can be automatically upgraded.

## The Solution, In Theory

Roughly, the answer is:

> If an authorization _returns the value_ of `.can_see?`, then we can replace that call with `.async_can_see?`.

This is true because GraphQL-Ruby is happy to receive `Promise<true|false>` -- it will use its batching system to resolve it as late as possible.

So, how can we find cases when `.can_see?` is used as a return value? There are roughly two possibilities:

- explicit `return`s, which we don't use often
- implicit returns, which are the last expressions of any branches in the method body.

This post covers that _second case_, implicit returns. We want to find implicit returns which are _just_ calls to `.can_see?`, and automatically upgrade them. (Some calls will be left over, we'll upgrade those by hand.)

We assume that any code which is _more complicated_ than _just_ a call to `.can_see?` can't be migrated, because it might depend on the synchronous return of `true|false`. We'll revisit those by hand.

## The Implementation: A Cop

I knew I wanted two things:

- For new code, require `async_can_see?` whenever possible
- For existing code, upgrade to `async_can_see?` whenever it's possible

Rubocop will do both of these things:

- A linting rule will fail the build if invalid code is added to the project, addressing the first goal
- A well-implemented `def autocorrect` will fix existing violations

But it all depends on implementing the check well: can I find implicit returns? Fortunately, I only need to find them _well enough_: it doesn't have to find _every possible_ Ruby implicit return; it only has to find the ones actually used in the codebase!

By an approach of trial and error, here's what I ended up with:

```ruby
# frozen_string_literal: true
class AsyncCanSeeWhenPossible < Rubocop::Cop
  MSG = <<-ERR
When `.can_see?` is the last call inside an authorization method, use
`.async_can_see?` instead so that the underlying calls can be batched.
ERR

  # If the given node is a call to `:can_see?`, it's yielded
  def_node_matcher :can_see_call, "$(send s(:const, {nil (:cbase)}, :Authorization) :can_see? ...)"

  # Look for nested promises -- treat the body of a nested promise just like the method body.
  # (That is, the implicit return of the block is like the implicit return of the method)
  def_node_matcher :then_block, "(block (send _ :then) _ $({begin send block if case} ...))"

  # Check for `def self.authorized?` and call the cop on that method
  def on_defs(node)
    _self, method_name, *_args, method_body = *node
    if method_name == :authorized?
      check_implicit_return(method_body)
    end
  end

  # Replace `.can_see?` with `.async_can_see?`
  def autocorrect(node)
    lambda do |corrector|
      _receiver, method_name, *rest = *node
      corrector.replace(node.location.selector, "async_can_see?")
    end
  end

  private

  # Continue traversing `node` until you get to the last expression.
  # If that expression is a call to `.can_see?`, then add an offense.
  def check_implicit_return(node)
    case node.type
    when :begin
      # This node is a series of expressions.
      # The last one is the implicit return.
      *_prev_exps, last_expression = *node
      check_implicit_return(last_expression)
    when :block
      # It's a method call that receives a block.
      # If it's a then-block, check its body for implicit returns.
      then_block(node) do |block_body|
        check_implicit_return(block_body)
      end
    when :if
      # Check each branch of an `if ...` expression, because
      # each branch may be an implicit return
      # (elsif is part of the `else_exp`)
      _check, if_exp, else_exp = *node
      check_implicit_return(if_exp)
      # This can be null if there is no else expression
      if else_exp
        check_implicit_return(else_exp)
      end
    when :case
      # Check each branch of the case statement, since each one
      # could be an implicit return.
      _subject, *when_exps, else_exp = *node
      when_exps.each do |when_exp|
        *_when_conditions, condition_body = *when_exp
        check_implicit_return(condition_body)
      end
      # There may or may not be an `else` branch.
      if else_exp
        check_implicit_return(else_exp)
      end
    when :send
      # This is a method call -- if it's a plain call to `.can_see?`, flag it.
      can_see_call(node) do |bad_call|
        add_offense(bad_call, location: :selector)
      end
    else
      # We've reached an implicit return which is not:
      #
      # - An expression containing other implicit returns
      # - An expression calling `.can_see?`, which we know to upgrade
      #
      # So, ignore this implicit return.
    end
  end
end
```

With this cop, `rubocop -a` will upgrade the easy cases in existing code, then I'll track down the harder ones by hand!

I think the implementation could be improved by:

- Also checking explicit `return`s. It wasn't important for me because there weren't any in this code base. `next` Could probably be treated the same way, since it exists `then` blocks.
- Flagging _any_ use of `.can_see?`, not only the easy ones. I expect that some usages are inevitable, but better to require a `rubocop:disable` in that case to mark that it's not best-practice.

(Full disclosure: we haven't shipped this refactor yet. But I enjoyed the work on it so far, so I thought I'd write up what I learned!)
