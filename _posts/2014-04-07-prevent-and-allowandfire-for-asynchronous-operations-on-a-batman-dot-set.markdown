---
layout: post
title: "Prevent and allowAndFire for asynchronous operations on a Batman.Set"
date: 2014-04-07 18:12
categories:
  - Batman.js
---

[Batman.js](http://batmanjs.org)'s [`prevent`](http://batmanjs.org/docs/api/batman.eventemitter.html#prototype_function_prevent) and [`allowAndFire`](http://batmanjs.org/docs/api/batman.eventemitter.html#prototype_function_allowandfire) make it easy to fire a callback when you're finished working on the members of a [Batman.Set](http://batmanjs.org/docs/api/batman.set.html).

<!-- more -->

# The Problem


Let's say you have `Batman.Set` (or `Batman.AssociationSet`, or even a plain JS array) whose members are `Batman.Model` instances. You have a `saveAll` function that saves all the members:

```coffeescript
class ThingsController extends Batman.Controller
  saveAll: (setOfRecords) ->
    setOfRecords.forEach (record) -> record.save()
```

But what if you wanted to call a `callback` when the whole operation was finished?

# The Solution

- Set up a listener on the `"finished"` event. Use [`once`](http://batmanjs.org/docs/api/batman.eventemitter.html#prototype_function_once) to avoid observer bloat.
- Before each save operation, `prevent "finished"`
- When each one finishes, `allowAndFire "finished"`.

That way, it will get prevented _n_ times -- once for each item in the set -- and it will finally be fired when the last operation is finished.

Here it is, all together:

```coffeescript
class ThingsController extends Batman.Controller
  saveAll: (setOfRecords, callback) ->
    # observer:
    @once 'finished', ->
      callback()

    setOfRecords.forEach (record) => # mind the fat arrows!

      @prevent('finished')

      record.save (err, record) =>
        @allowAndFire('finished')
```

__Note__: `@prevent` and `@allowAndFire` are provided by [`Batman.EventEmitter`](http://batmanjs.org/docs/api/batman.eventemitter.html), so it will only work with objects which have that mixin. Don't worry -- every object in batman.js is an event emitter! But plain JS objects are not.
