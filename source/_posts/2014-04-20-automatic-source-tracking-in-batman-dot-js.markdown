---
layout: post
title: "Automatic Source Tracking in Batman.js"
date: 2014-04-20 21:18
comments: true
categories:
  - Batman.js
---
In [batman.js](http://batmanjs.org), properties automatically track their sources. This is done by tracking all calls to `get` when an accessor function is executed.

<!-- more -->

I hope to cover automatic dependency tracking in batman.js by describing:

- The "source" relationship between properties
- The structure of the tracker stack
- How the tracker stack is used internally by batman.js

Then I will cover several examples of source tracking:

- No depencies
- One dependency
- Nested dependencies
- Parallel dependencies
- Outside dependencies
- Conditionals
- Iteration

## Sources/Dependencies

Consider `Tree`:

```coffeescript
class Tree extends Batman.Object
  @accessor 'species'
  @accessor 'isOak', -> @get('species') is 'oak'
```

A `Tree`'s `isOak` changes when `species` changes. For example:

```coffeescript
shadeTree = new Tree(species: 'maple')
shadeTree.get('isOak')
# => false
shadeTree.set('species', 'oak')
shadeTree.get('isOak')
# => true
```

We can describe the relationship between `isOak` and `species` in two ways:

- `isOak` _depends on_ `species`
- `species` is `isOak`'s  _source_

## The Source Tracker Stack

The __global source tracker stack__ is an array of arrays:

- Each sub-array is a _list of sources_ for a property whose value is being calculated.
- Each member of a sub-array is a _source_ for that property.

Here's an example tracker stack:

```
  [
    [
      <Batman.Property "species">,
      <Batman.Property "age">
    ],
    [
      # no sources
    ]
  ]
```

- The global tracker is an array
- Its members are arrays
- Inside those arrays are sources
- Some properties have no other sources

_I'll be using strings to represent sources, but batman.js actually uses [`Batman.Property` instances](http://batmanjs.org/docs/api/batman.property.html). A `Batman.Property` has a `base` (usually a `Batman.Object`) and a `key`, which is the string identifier for the property._

## How Batman.js Uses Source Tracker Stack

Internally, batman.js uses the source tracker stack whenever properties are evaluated with `get` (if they weren't already [cached](/blog/2014/03/31/property-caching-in-batman-dot-js/)). `get` functions are wrapped with batman.js's source tracking:

```text
┌────────────────────────────────────────────────────
│ -> Property is pushed to open tracker,
│    if there is one
│ -> Batman.js opens the stack for sources
│  ┌─────────────────────────────────────────────────
│  │  -> Accessor function is executed
│  │     and returns a value
│  └─────────────────────────────────────────────────
│ -> Batman.js registers sources
└────────────────────────────────────────────────────
```

At the beginning each call to `get("property")`, batman.js:

1. __Adds `property` to the current open tracker, if there is one.__  To determine whether the current `get` is called in the context of evaluating another property, batman.js checks for an open tracker (ie, an array inside the global source tracker). If there is one, it pushes the current property as source of whatever property was being evaluated.
1. __Pushes a new entry in the tracker.__ Batman.js prepares the source tracker for any dependencies by pushing a child array. If any other properties are accessed, they will be pushed to that child array (via step 1 above!).

When `get` functions finish, batman.js cleans up the source tracker stack by:

1. __Getting the list of sources__ by popping off of the global source tracker.
1. __Creating observers__ for all sources.


## No Dependencies

In a property lookup, there are no other calls to `get`, so the source tracker doesn't do very much. Here's what it would look like if you watched the global source tracker:

```coffeescript
# Call stack              # Source tracker stack
                          # []
shadeTree.get('species')  # []
  # there is no entry in the stack to add `species` to.
  # batman.js pushes an entry for `species`'s sources
                          # [ [] ]
  -> return 'oak'         # [ [] ]
  # batman.js registers sources (none!) and clears the tracker
```

Batman.js prepared to track the sources for `species`, but didn't find any.

## One Dependency

The example above, calling `get('isOak')` [causes batman.js to calculate](/blog/2014/03/31/property-caching-in-batman-dot-js/) the tree's `isOak` value.

Here's what the tracker stack would look like:

```coffeescript
# Call stack              # Source tracker stack
                          # []
shadeTree.get('isOak')    # []
  # there is no entry in the stack to add `isOak` to.
  # batman.js pushes an entry in the source tracker for `isOak`'s sources
                          # [ [] ]
  -> @get('species')
  # batman.js adds `species` to `isOak`'s sources
                          # [ [species] ]
  # batman.js pushes an entry in the source tracker for `species`
                          # [ [species], [] ]
    -> return             # [ [species], [] ]
    # batman.js pops `species`'s sources -- but there weren't any
  -> is 'oak'             # [ [species] ]
  -> # batman.js pops `isOak`'s dependencies and registers them internally
  -> return               # []
```

## Deeply-Nested Dependencies

Batman.js handles nested calls to `get` by pushing entries to the source tracker. When the nested class resolve, entries are popped back off the source tracker.

For example, let's add another property that depends on `isOak`:

```coffeescript
class Tree extends Batman.Object
  # ...
  @accessor 'hasAcorns', -> @get('isOak')
```

`hasAcorns`'s only source is `isOak`. The dependency chain looks like this:

```
species -> isOak -> hasAcorns
```

So, here's what the source tracker stack looks like for calculating `hasAcorns`:

```coffeescript
# Call stack                # Source tracker stack
                            # []
shadeTree.get('hasAcorns')
                            # [ [] ]
  -> @get('isOak')
                            # [ [isOak], [] ]
    -> @get('species')      # [ [isOak], [species], [] ]
      -> return
      # batman.js doesn't register any sources for `species`
                            # [ [isOak], [species] ]
    -> return
    # batman.js registers `isOak`'s source, `species`
                            # [ [isOak] ]
  -> return
  # batman.js registers `hasAcorn`'s source, `isOak`
```

_Note:_ Batman.js only evaluates properties that aren't [cached](blog/2014/03/31/property-caching-in-batman-dot-js/), so you don't have to worry about "abusing" deeply nested properties.

## Parallel Dependencies

Properties may also have multiple, non-nested sources. These are parallel sources:

```coffeescript
class Tree extends Batman.Object
  @accessor 'description', ->
    "#{@get('age')}-year-old #{@get('species')}"
```

`description` depends on `age` _and_ `species`. If either one changes, the property will be reevaluated.

When `description` is calculated, it will register `age` and `species` as sources. Here's what it would look like:

```coffeescript
# Call stack                # Source tracker stack
                            # []
shadeTree.get('description')
                            # [ [] ]
  -> @get('age')
                            # [ [age] ]
                            # [ [age], [] ]
    -> return
                            # [ [age] ]
  -> @get('species')
                            # [ [age, species] ]
                            # [ [age, species], [] ]
    -> return
                            # [ [age, species] ]
  ->
  # batman.js registers both sources
                            # []
```

## Dependencies on Other Objects

So far, all examples have used `@get` inside accessors. However, it's safe to access properties of any `Batman.Object` with `get` inside an accessor function. This is because the `Batman.Property` is aware of its _base_ and _key_. _Base_ is the object that the property belongs to and _key_ is the string name of the property. When you use `get` on another object, the correct object and property are tracked as sources.

For example, `Tree::ownerName` depends on an outside object (a `Person` object):

```coffeescript
class Tree extends Batman.Object
  # ...
  @accessor 'ownerName', ->
    ownerId = @get('ownerId')
    # find owner by id:
    owner = Person.get('all').indexedByUnique('id').get(ownerId)
    owner.get('name')
```

In this case `owner.get('name')` registers a `Batman.Property` whose base is a `Person`. If that person's name changes, `ownerName` will be reevaluated.

## Conditionals

Let's add a property to `Tree` that has some conditional logic. `Tree::bestAvailableFood` contains conditional branching:

```coffeescript
class Tree extends Batman.Object
  @accessor 'bestAvailableFood', ->
    if @get('hasFruit')
      "fruit"
    else if @get('hasAcorns')
      "acorns"
    else
      null
```

Batman.js will only track calls to `get` that are _actually executed_, so if `hasFruit` returns true, then `hasAcorns` won't be registered as a source.

What if `hasAcorns` changes? It doesn't matter -- the property would still evaluate to `"fruit"` (from the `hasFruit` branch), so batman.js saved itself some trouble!

If `hasFruit` and `hasAcorns` both returned false, they would both be registered as sources (as in the "parallel sources" example). The property would be reevaluated if either one changed.

## Iteration

Iteration is safe inside accessor bodies as long as you play by batman.js's rules:

- __Enumerables must extend `Batman.Object`__ so that they're observable. Plain JavaScript Arrays and Objects can't be registered as sources.
- __Enumerables must be retrieved with `get`__ so that a wholesale replacement of the enumerable is observed, too.

Let's look at two accessors that have iteration in their `get` functions: one has an early return, the always visits each member of the set.

_These accessors could be simplifed by using [`Batman.Enumerable`](http://batmanjs.org/docs/api/batman.enumerable.html) functions, but they're spelled out for clarity's sake!_

### Early Return

`Tree::hasFruit` returns as soon as it finds a limb with fruit:

```coffeescript
class Tree extends Batman.Object
  @accessor 'limbs' # has a Batman.Set

  @accessor 'hasFruit', ->
    @get('limbs').forEach (limb) ->
      return true if limb.get('hasFruit')
    false
```

During evaluation, `limbs` and each `limb.hasFruit` will be added as sources, until a `limb.hasFruit` returns true.

Some limbs won't be observed as sources, but that's OK: the property will be true _as long as_ the first true `limb.hasFruit` still evaluates to true. If that first `limb.hasFruit` becomes `false`, the property will be reevaluated.

Similarly, if one of the earlier limbs becomes `true`, the property will be reevaluated. (And in that case, it will register fewer sources, since it made fewer iterations before finding a `true` value.)

### Depends on Every Member

`Tree::totalFruits` is the sum of fruits on all limbs, so it must observe _every_ limb:

```coffeescript
  @accessor 'totalFruits', ->
    totalCount = 0
    @get('limbs').forEach (limb) ->
      totalCount += limb.get('fruits.length') || 0
    totalcount
```

Since every limb will be visited during evaluation, every limb will be added as a source. Whenever one of the `limb.fruits.length` changes, the property will be reevaluated.
