---
layout: post
title: "Property Caching in Batman.js"
date: 2014-03-31 09:09
comments: true
categories:
  - Batman.js
---

[Batman.js](http://batmanjs.org) objects ([`Batman.Object`](batmanjs.org/docs/api/batman.object.html) instances) have properties defined with [`@accessor`](batmanjs.org/docs/api/batman.object_accessors.html). These properties are cached until one of their sources busts their cache.

<!-- more -->

# Batman.Object Properties

 In batman.js, all properties should be declared with `@accessor`. When I say _property_, I mean a property declared with `@accessor`.

When a property's value is retrieved (with `get`), it tracks calls that it makes to other properties. These internal calls (to `get`) define the property's _sources_. The value will be cached. Since it knows what it depends on, they only recalculate themselves when their caches are busted. (Passing the `cache: false` option makes a property not cached.) When one of the property's sources are changed, its cache is busted and it will recalculate _next time_ you `get` its value.

After a property recalculates, it checks if its _new_ result doesn't equal its _cached_ result ( `!==` , CoffeeScript `isnt`). If it determines a new value, then the property busts its dependents' caches, too

To sum up the introduction:

- Sources are tracked at calculation-time, not load time. They're tracked when a property calculates itself.
- A property isn't caluclated if it's never retrieved.
- A property is cached and isn't recalculated until one of its sources signals a change.
- When a property's source changes, the cache is busted and it will recalcute next time it is retrieved with `get`
- If the result of recalculation is a different value (`!==`), the property notifies _its_ subscribers (if present) to recalculate.

# A Day in the Life of a Batman.js Property

`fullName` is the quintessential computed property:

```coffeescript
class Person extends Batman.Object
  @accessor 'fullName', -> "#{@get('firstName')} #{@get('lastName')}"
```

Let's see how it's used with a `Person`. You can get metadata for a property with the `Batman.Object::property(name)` function.

When a person is initialized, the `fullName` has no value:

```coffeescript
morganFreeman = new Person(firstName: "Morgan", lastName: "Freeman")
morganFreeman.property('fullName').value # => null
```

It hasn't been requested yet, so it hasn't been calculated. The property also has no sources:

```coffeescript
morganFreeman.property('fullname').sources # => null
```

However, if you `get` the property, it will be calculated and its sources will be identified.

```coffeescript
morganFreeman.get('fullName') # => "Morgan Freeman"
```

Now let's inspect the underlying `Batman.Property`:

```coffeescript
fullName = morganFreeman.property("fullName")
```

Its value is cached:

```coffeescript
fullName.value  # => "Morgan Freeman"
fullName.cached # => true
```

And it knows its sources:

```coffeescript
fullName.sources.map (s) -> return s.key
# => ["firstName", "lastName"]
```

If you change one of `fullName`'s sources, it is no longer cached:

```coffeescript
morganFreeman.set("firstName", "Lucius")
morganFreeman.set("lastName", "Fox")
morganFreeman.property("fullName").cached # => false
```

And since we haven't asked for its value again, it hasn't been recalculated:

```coffeescript
morganFreeman.property("fullName").value # => "Morgan Freeman"
```

But `get`ting its value will cause it to be recalculated & cached:

```coffeescript
morganFreeman.get('fullName') # => "Lucius Fox"
morganFreeman.property('fullName').value  # => "Lucius Fox"
morganFreeman.property('fullName').cached # => true
```

# Another Look

Here's the same story, in a chart:

[![Batman.js property caching](/images/batman-properties.png)](/images/batman-properties-large.png)
