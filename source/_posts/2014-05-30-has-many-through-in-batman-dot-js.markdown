---
layout: post
title: "Has Many Through in Batman.js"
date: 2014-05-30 15:27
comments: true
categories:
  - Batman.js
---

[Batman.js](http://batmanjs.org) doesn't support `hasManyThrough` out of the box, but it can be implemented fairly easily with `Set::mappedTo`.

<!-- more -->

_This feature was just merged into the master branch -- download the latest batman.js [here](http://batmanjs.org/download.html)._

# What's a "Has-Many-Through" Association?

It's best shown by example. To join `Household` to `Person`, you might have a "join model", `HouseholdMembership`. The associations look like this:

```coffeescript
class Household extends Batman.Model
  @hasMany 'householdMemberships'

class HouseholdMembership extends Batman.Model
  @belongsTo 'household'
  @belongsTo 'person'

class Person extends Batman.Model
  @hasMany 'householdMemberships'
```

Household `hasMany` memberships, each membership `belongsTo` a person.

```
               __ HouseholdMembership ─── Person
             ╱
Household ─── HouseholdMembership ─── Person
             ╲
               ╲_ HouseholdMembership ─── Person
```

Household has many people _through_ household memberships.

# Has-Many-Through in Batman.js

Although `hasManyThrough` isn't part of batman.js, you can implement a __read-only__ has-many-through using [`Set::mappedTo`](http://batmanjs.org/docs/api/batman.set.html#prototype_function_mappedto). Given classes as defined above, you could add an accessor for `Household::people`:

```coffeescript
# class Household
  @accessor 'people', -> @get('householdMemberships').mappedTo('person')
```

This returns a `Batman.Set` (actually a `Batman.SetMapping`) containing unique `Person`s belonging to those `householdMemberships`. As batman.js does, items added and removed are [automatically tracked](rmosolgo.github.io/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/), so this is safe to use everywhere.

As for __adding items__, you could do it this way:

```coffeescript
# class Household
  addPerson: (person) ->
    @get('householdMemberships').build({person})
```

Again, the `Batman.SetMapping` will take care of keeping everything in sync!
