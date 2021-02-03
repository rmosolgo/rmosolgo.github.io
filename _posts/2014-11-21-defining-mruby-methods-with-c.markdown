---
layout: post
title: "Defining mruby Methods with C"
date: 2014-11-21 10:25
categories:
  - mruby
---

You can use C code to prepare methods for [mruby](http://www.mruby.org) scripts.

<!-- more -->

The steps are:

- Defining a method
- Getting argument values
- Adding the method to the `mrb_state`

## Defining a Method

To define a Ruby function, make a C function that:

- accepts two arguments, a `mrb_state` and a `mrb_value`
- returns a `mrb_value`.

Here's a minimal method definition:

```c
mrb_value
ruby_method(mrb_state *mrb, mrb_value self)
{
  return mrb_nil_value();
}
```

The __arguments__ are:

1. `mrb_state`, the current mruby VM instance
2. `mrb_value`, the current `self` (caller of this method)

Notice that you don't define the Ruby arguments here. You'll handle those later by getting them from the `mrb_state`.

The __return type__ must be `mrb_value`. If it's not, your program will crash (`Segmentation Fault` :( ) when the return value is accessed (no compile-time error). If your method shouldn't return anything, use `return mrb_nil_value();`

mruby implements a lot of the built-in classes' instance methods this way, for example: `String#capitalize!`([src](https://github.com/mruby/mruby/blob/e77ea4e5f2b823181020bb3a337509ba028b6dc4/src/string.c#L855)).

## Getting Arguments

You might have noticed that your C function definition _didn't_ define any arguments. Instead, you get your arguments by extracting them from `mrb_state`.

```c
mrb_value
ruby_method(mrb_state *mrb, mrb_value self)
{
  // Initialize a variable
  mrb_int some_integer;
  // Extract a value
  mrb_get_args(mrb, "i", &mrb_int);

  return mrb_nil_value();
}
```

`mrb_get_args` takes a string whose letters say what kind of arguments and how many arguments to extract. The [`mrb_get_args` source](https://github.com/mruby/mruby/blob/5c6d6309b6b5e01ef3ff38f772e0fdd3fc5dd372/src/class.c#L437) documents the different possibilities.

Notably, anything after a `|` is __optional__.

For a __default value__, assign a value to the variable and make the argument optional. In this example, `inherit` defaults to `TRUE`:

```c
  mrb_bool inherit = TRUE;
  mrb_get_args(mrb, "|b", &inherit);
```

That's from [C implementation of `Module#constants`](https://github.com/mruby/mruby/blob/b28ec1bc88d29d8e7205401a6e323f20581d642f/src/variable.c#L988). Another nice example is [the `String#[]` source](https://github.com/mruby/mruby/blob/e77ea4e5f2b823181020bb3a337509ba028b6dc4/src/string.c#L831).

## Adding Methods to mruby State

To add a method to the mruby state, you must attach it to some object. To make a method global, you can define it on `Object`. Let's do that.

We'll use `mrb_define_method`, which accepts five arguments:

```c
mrb_define_method(mrb_state *mrb, struct RClass *c, const char *name, mrb_func_t func, mrb_aspec aspec)
```

- `mrb_state *mrb`: the open mruby VM instance
- `struct RClass *c`: the mruby class to attach the method to
- `const char *name`: the Ruby name for this method
- `mrb_func_t func`: the C function to execute for this Ruby method
- `mrb_aspec aspec`: the number & types of arguments for this method


In fact, __specifying arguments__ is not currently used ([github issue](https://github.com/mruby/mruby/issues/791)). To pass some value here, you can use some [convenient macros from `mruby.h`](https://github.com/mruby/mruby/blob/5c6d6309b6b5e01ef3ff38f772e0fdd3fc5dd372/include/mruby.h#L232-L251).


So, let's add a global method, `greet!`. Here's the method:

```c
static mrb_value
mrb_greet(mrb_state *mrb, mrb_value self) {
  printf("Hello, mruby!\n");
  return mrb_nil_value();
}
```

Then, attach it to `Object`, which will make it global:

```c
mrb_define_method(mrb, mrb->object_class, "greet!", mrb_greet, MRB_ARGS_NONE());
```

Now, you can run in your Ruby script:

```ruby
greet!
```
