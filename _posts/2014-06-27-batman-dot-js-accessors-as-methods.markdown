---
layout: post
title: "Batman.js Accessors as Methods"
date: 2014-06-27 08:10
categories:
  - Batman.js
---

[Batman.js](http://batmanjs.org) is a CoffeeScript front-end MVC framework. One of its core features is _accessors_, which can be used like properties or methods of a `Batman.Object`. They can even take arguments!

<!-- more -->

`Batman.Object` has properties defined with `@accessor` in the class definition. Examples of `@accessor` as accessible properties and computed properties are bountiful. However, I recently learned that accessors can also be made to take arguments, too!

_(You can see this example live on at http://jsbin.com/dalodifo/3/edit .)_

## Definining Accessors with Arguments

To make an accessor that takes arguments, use `Batman.TerminalAccessible`. Let's say I have a `MathObject` which stores a `value` and allows you to perform calculations on it:

```coffeescript
class MathObject extends Batman.Object
  @accessor 'value'

  @accessor 'times', ->
    new Batman.TerminalAccessible (multiplier) =>
      @get('value') * multiplier
```

Now, my `times` accessor takes an argument (`multiplier`) and returns the multiplied value. I pass the argument with `get`, like this:

```coffeescript
fiveObject = new MathObject(value: 5)
fiveObject.get('time').get(10) # => 50
fiveObject.get('time').get(3)  # => 15
```

Under the hood, `fiveObject.get('time')` returns a `Batman.TerminalAccessible`. This object provides [source tracking](/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/) for the function that it calls.

## Objects as Arguments

You can also have `Batman.Objects` as arguments. For example, if we wanted to multiply two `MathObject`s:

```coffeescript
class MathObject extends Batman.Object
  @accessor 'value'

  @accessor 'timesMathObject', ->
    new Batman.TerminalAccessible (mathObj) =>
      @get('times').get(mathObj.get('value'))
```

Now, the other `mathObj` will be included in the source tracking. If `mathObj.value` changes, the value will be recalculated.  This is __essential__ for values computed from two `Batman.Object`s!

## What's the point?

This allows __observable__ "method calls". It's wrapped in batman.js [source tracking](/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/), so whenever the object or the arguments change, the value will be recalculated.

For example, I use it for checking whether a room is at maximum occupancy for certain events:

```coffeescript
location.get('isFullFor').get(earlyEvent) # => false
location.get('isFullFor').get(lateEvent)  # => true
```

When people attend the event (or the location max occupancy is changed), these values are automatically recalculated!

This is the same approach used in batman.js internals for accessing SetIndexes ([source](https://github.com/batmanjs/batman/blob/master/src/set/set.coffee#L19)).

## Accessor Arguments in View Bindings

To pass arguments to accessors in view bindings, you can use the `[...]` or `withArguments` filters. Let's say I want to put this operation in a view binding:


```coffeescript
location.get('isFullFor').get(earlyEvent)
```

`[...]` is shorthand for calling `get` with the given argument. I can use it like this:

```html
<span data-bind='location.isFullFor[earlyEvent]'></span>
```

`earlyEvent` will be looked up in context and the value will be passed to `get`, as in the CoffeeScript above.

You can also use the `withArguments` filter (as of 0.16, [PR](https://github.com/batmanjs/batman/pull/923)) like this:

```html
<span data-bind='location.isFullFor | withArguments earlyEvent'></span>
```

`withArguments` recognizes that it should use `get` in this case.
