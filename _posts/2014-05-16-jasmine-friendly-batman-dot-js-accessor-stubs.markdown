---
layout: post
title: "Jasmine-Friendly Batman.js Accessor Stubs"
date: 2014-05-16 12:53
comments: true
categories:
  - Batman.js
---

[`Batman.Object` accessors](http://batmanjs.org/docs/api/batman.object_accessors.html) are the bread and butter of [batman.js](http://batmanjs.org). Stubbing them can make testing much easier.

<!-- more -->


I haven't figured out [`Batman.TestCase`](http://batmanjs.org/docs/testing.html) yet, so I'm still using [jasmine](http://jasmine.github.io/). `Batman.TestCase` [includes `stubAccessor` out of the box](https://github.com/batmanjs/batman/blob/master/src/extras/testing/test_case.coffee#L90), and I ported it to jasmine:

```coffeescript
window.stubAccessor = (object, keypath) ->
  if object.prototype?
    console.warn "You're stubbing an accessor on #{object.name},
        which won't be un-stubbed when the example group finishes!
        Stub accessors on instances, not classes, if possible!"
  stub = spyOn(object.property(keypath), 'getValue')
  object.property(keypath).refresh()
  stub.calls.pop() # ^^ remove call from refresh
  stub
```


This way, the `stub` works just like normal jasmine spies:

```coffeescript
record = new App.MyModel
stub = stubAccessor(record, 'myProperty').andReturn('stubbed!')
record.get('myProperty') # => "stubbed!"
record.get('myProperty')
stub.calls.length # => 2
```

```
record = new App.MyModel
stub = stubAccessor(record, 'myProperty').andCallThrough()
record.set('myProperty', "value!")
record.get('myProperty') # => "value!"
stub.calls.length # => 1
```

However, this `stubAccessor` _doesn't_ stub `set`! Maybe that's a to-do, I haven't needed it yet.