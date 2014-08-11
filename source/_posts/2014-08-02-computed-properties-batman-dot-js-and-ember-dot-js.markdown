---
layout: post
title: "Computed Properties: Batman.js and Ember.js"
date: 2014-08-02 09:38
comments: true
categories:
  - Batman.js
  - Ember.js
  - Framework Comparison
---

[Batman.js](http://batmanjs.org) is a front-end MVC framework with an unrivaled implementation of key-value observing. I will explore computed properties in batman.js by contrasting them with Ember.js's computed properties.

<!-- more -->

First, disclaimers!

- I didn't write any of the `Batman.Property` code that makes this feature possible. I'm only a fanboy!
- I don't know Ember.js. I've just gathered examples from the [Ember Guides](http://emberjs.com/guides).

To explore computed properties, let's take the __canonical `fullName` example__. It:

- depends on two other properties, `firstName` and `lastName`
- returns a string that joins `firstName` and `lastName` with a space
- can be set
- sets `firstName` and `lastName` by splitting on whitespace

We'll also explore an __aggregrated `roster` property__ which:

- depends on `fullName` for each person
- joins `fullName` with `, `


## fullName in Ember.js

(This is yanked wholesale from the [Computed Properties Guide](http://emberjs.com/guides/object-model/computed-properties/).)

A couple of things to notice:

- `fullName` is defined as _one function_ which handles `get` and `set` operations.
- `fullName` must be told what properties it depends on.

```javascript
App.Person = Ember.Object.extend({
  firstName: null, // These aren't necessary, they're
  lastName: null,  // just for clarity.

  fullName: function(key, value, previousValue) {
    // setter
    if (arguments.length > 1) {
      var nameParts = value.split(/\s+/);
      this.set('firstName', nameParts[0]);
      this.set('lastName',  nameParts[1]);
    }

    // getter, also the return value is cached
    return this.get('firstName') + ' ' + this.get('lastName');
  }.property('firstName', 'lastName')
});
```


Usage is pretty standard: use `get` and `set` to access properties.

```javascript
var captainAmerica = App.Person.create();
captainAmerica.set('fullName', "William Burnside");
captainAmerica.get('firstName'); // William
captainAmerica.get('lastName');  // Burnside
```

## fullName in Batman.js

Two things to notice:

- `get` and `set` operations are defined _separately_.
- `fullName` doesn't have to be told what its dependencies are.

```coffeescript
class App.Person extends Batman.Object
  @accessor 'firstName' # not necessary,
  @accessor 'lastName'  # just here for clarity

  @accessor 'fullName',
    get: (key) -> "#{@get('firstName')} #{@get('lastName')}"
    set: (key, value) ->
      nameParts = value.split(/\s+/)
      @set('firstName', nameParts[0])
      @set('lastName', nameParts[1])
      return value # should return newly-set value, although the `get` function will be used for caching.
```

The usage is almost identical:

```coffeescript
captainAmerica = new App.Person
captainAmerica.set('fullName', 'William Burnside')
captainAmerica.get('firstName') # William
captainAmerica.get('lastName')  # Burnside
```

## roster in Ember.js

(This was adapted from the [Computed Properties and Aggregate Data Guide](http://emberjs.com/guides/object-model/computed-properties-and-aggregate-data/).)

Some things stood out to me:

- `roster`'s properties are declared with a DSL. Array dependencies are limited to one layer deep (ie, you can't use `@each` twice).
- `mapBy` is provided by `Ember.Enumerable` to handle arrays of objects. Nice!

```javascript
App.PeopleController = Ember.Controller.extend({
  people: [
    App.Person.create({firstName: "Tom", lastName: "Dale"}),
    App.Person.create({firstName: "Yehuda", lastName: "Katz"})
  ],

  roster: function() {
    var people = this.get('people');
    return people.mapBy('fullName').join(', ');
  }.property('people.@each.fullName')
});
```

## roster in Batman.js

Here's the analogous construction in batman.js:

```coffeescript
class App.PeopleController extends Batman.Controller
  @accessor 'people', ->
    new Batman.Set([ # this is future-code: constructor will take an array in v0.17.0
      new App.Person(firstName: "Tom", lastName: "Dale")
      new App.Person(firstName: "Yehuda", lastName: "Katz")
    ])

  @accessor 'roster', ->
    @get('people').mapToProperty('fullName').join(', ')
```

One thing is the same:

- `mapToProperty` works like `mapBy`

You might notice two big differences:

- `people` is a `Batman.Set` instead of a native Array.
- `roster` didn't have to be told what its dependencies are

By using batman.js data structures inside `@accessor` functions, we benefit from batman.js's [automatic source tracking](http://rmosolgo.github.io/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/). It looks like automatic source tracking was considered by the Ember core team, but deemed [impossible](https://github.com/emberjs/ember.js/issues/269#issuecomment-3178319) or [prohibitively expensive](https://github.com/emberjs/ember.js/issues/386#issuecomment-3523589).

I recently saw a quote in a [React.js talk](https://www.youtube.com/watch?v=-DX3vJiqxm4):

> Intellectuals solve probelms. Geniuses prevent them. - Albert Einstein

I think that's just what the Shopify team did when they implemented `Batman.Observable`! The API is very simple and it Just Works<sup>TM</sup>.

## My Opinion

__Pros of batman.js:__

- Elegant `@accessor` API for getters and setters: define `get` and `set` separately instead of testing for arguments.
- Automatic dependency tracking: batman.js knows what objects & properties were accessed during computation and observes accordingly.
- There's no limit to the depth of enumerable dependencies. Any property of a `Batman.Object` that's accessed will be tracked, no matter where it exists in the app.

In fact, `@accessor` is the heart and soul of a batman.js app. You're basically declaring a system of computed properties, then updating that system from user input. Batman.js propagates information to wherever it needs to be.

__Cons of batman.js:__

- "It's just not Ember." You miss out on huge user base, corporate support, and everything that goes with that.
- Beyond that, batman.js resources are sparse. The [new guides](http://batmanjs.org/docs/index.html), [cookbook](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook) and [API docs](http://batmanjs.org/docs/index.html) are improving every week, but for advanced usage you still have to sourcedive sometimes.
- There __is__ a performance hit for global observability. The only place I've noticed it is with complex iteration views ([batmanjs/batman#1086](https://github.com/batmanjs/batman/issues/1086)). I'm hoping to tackle this soon since it's becoming an issue in [PCO Check-ins](http://get.planningcenteronline.com/check-ins).

I'm not aware of any features missing from batman.js, but I do miss the "googleability" of a well-traveled path. Batman.js also lacks some of the dev tools like a decent Chrome extension and a command-line client.

I always want to know _how_ things works, so getting in the source is actually a benefit for me.

__Six of one, half-dozen of the other:__

- Dependency DSL vs `Batman.{DataStructure}`
- Calling super: `this._super` vs. `@wrapAccessor`
- External API with `get` and `set`
- Cached values in computed properties
- In batman.js, you can opt out of tracking with `Batman.Property.withoutTracking`. It's obscure, but I think it's ok because batman.js always covers the more common case.


One thing that I found in neither framework was rate-limited properties, a la Knockout. I'd love to have a built-in option for this in batman.js.


