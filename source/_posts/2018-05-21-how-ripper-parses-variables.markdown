---
layout: post
title: "How Ripper parses variables"
date: 2018-05-21 14:11
comments: true
categories:
- Ruby
- Ripper
---

Ruby has a few different kinds of variables, and Ripper expresses them with a few different nodes.

<!-- more -->

Here are the different variables in Ruby:

```ruby
a   # Local variable (or method call on self)
$a  # Global variable
A   # Constant
@a  # Instance variable
@@a # Class variable

# Bonus, not variables:
a()       # explicit method call (with parens) on implicit self
a b       # explicit method call (with args) on implicit self
self.a    # explicit method call (with dot) on explicit self
```

Here is how Ripper parses the above code:

```ruby
# Ripper.sexp_raw(...) =>

[:program,
 [:stmts_add,
  [:stmts_add,
   [:stmts_add,
    [:stmts_add,
     [:stmts_add,
      [:stmts_add,
       [:stmts_add,
        [:stmts_add, [:stmts_new], [:vcall, [:@ident, "a", [1, 0]]]],
        [:var_ref, [:@gvar, "$a", [2, 0]]]],
       [:var_ref, [:@const, "A", [3, 0]]]],
      [:var_ref, [:@ivar, "@a", [4, 0]]]],
     [:var_ref, [:@cvar, "@@a", [5, 0]]]],
    [:method_add_arg, [:fcall, [:@ident, "a", [8, 0]]], [:arg_paren, nil]]],
   [:command,
    [:@ident, "a", [9, 0]],
    [:args_add_block,
     [:args_add, [:args_new], [:vcall, [:@ident, "b", [9, 2]]]],
     false]]],
  [:call, [:var_ref, [:@kw, "self", [10, 0]]], :".", [:@ident, "a", [10, 5]]]]]
```

([Ripper-preview](https://ripper-preview.herokuapp.com/?code=a+++%23+Local+variable+%28or+method+call+on+self%29%0D%0A%24a++%23+Global+variable%0D%0AA+++%23+Constant%0D%0A%40a++%23+Instance+varaible%0D%0A%40%40a+%23+Class+variable%0D%0A%0D%0A%23+Bonus%2C+not+variables%3A%0D%0Aa%28%29+++++++%23+explicit+method+call+%28with+parens%29+on+implicit+self%0D%0Aself.a++++%23+explicit+method+call+%28with+dot%29+on+explicit+self))

Let's check out those nodes.

### :vcall

```ruby
# a
[:vcall, [:@ident, "a", [1, 0]]]]
```

A `:vcall` is a bareword, either a local variable lookup _or_ a method call on self. Used alone, this can only be determined at runtime, depending on the binding. If there's a local variable, it will be used. My guess is that `:vcall` is short for "variable/call"

Interestingly, there is a single-expression case which _could_ be disambiguated statically, but Ripper still uses `:vcall`:

```ruby
# a b
[:command,
 [:@ident, "a", [1, 0]],
 [:args_add_block,
  [:args_add, [:args_new], [:vcall, [:@ident, "b", [1, 2]]]],
  false]]]]
```

### :var_ref

```ruby
# $a
[:var_ref, [:@gvar, "$a", [1, 0]]]
# A
[:var_ref, [:@const, "A", [1, 0]]]
# @a
[:var_ref, [:@ivar, "@a", [4, 0]]]
# @@aa
[:var_ref, [:@cvar, "@@a", [5, 0]]]
```


`:var_ref` (presumably "variable reference") is shared by many of these examples, and can always be resolved to a _variable_ lookup, never a method call.
Its argument tells what kind of lookup to do (global, constant, instance, class), and what name to look up.

### Method calls

Some Ruby can be statically known to be a method call, _not_ a variable lookup:

```ruby
# a(), explicit method call (with parens) on implicit self
[:method_add_arg, [:fcall, [:@ident, "a", [1, 0]]], [:arg_paren, nil]]
# self.a, explicit method call (with dot) on explicit self
[:call, [:var_ref, [:@kw, "self", [1, 0]]], :".", [:@ident, "a", [1, 5]]]
# a b, explicit method call (with arguments) on implicit self
[:command,
   [:@ident, "a", [10, 0]],
   [:args_add_block,
    [:args_add, [:args_new], [:vcall, [:@ident, "b", [10, 2]]]],
    false]]]
```

In these cases, `:fcall`, `:call` and `:command` are used to represent definite method sends.

Interestingly, `:var_ref` is used for `self`, too.
