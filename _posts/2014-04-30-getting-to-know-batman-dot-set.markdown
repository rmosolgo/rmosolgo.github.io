---
layout: post
title: "Getting to Know Batman.Set"
date: 2014-04-30 07:54
comments: true
categories:
  - Batman.js
---

[`Batman.Set`](http://batmanjs.org/docs/api/batman.set.html) is the array-like enumerable of [batman.js](http://batmanjs.org). It offers observable properties (which are automatically tracked by `@accessor`) and useful change events.
<!-- more -->

In batman.js, you need observable data structures everywhere. `Batman.Set` is the observable, array-like enumerable that the framework uses internally, and you can use it too! Besides `Batman.Set`, batman.js provides some other classes to help you get things done:

- `Batman.SetIndex` (created with `indexedBy`) groups a Set's items by a property value
- `Batman.UniqueSetIndex` (created with `indexedByUnique`) looks up items by unique value
- `Batman.SetSort` (created with `sortedBy`) returns a sorted proxy of the Set
- Binary set operations create unions, intersections and complements of sets.

## Batman.Set

`Batman.Set` implements the [set](http://en.wikipedia.org/wiki/Mathematical_set) pattern. It is a _collection of distinct objects_, meaning that there can be no duplicates (unlike an array). Features of `Batman.Set` include:

- Enumeration (`Batman.Set` mixes in [`Batman.Enumerable`](http://batmanjs.org/docs/api/batman.enumerable.html))
- Guaranteed unique contents (a `Batman.Set` won't allow duplicates, even if you call `add` twice.)
- Observable
- Sorting and searching, with internal caching
- Extensible with CoffeeScript `extend` for making custom sets

You can __create__ a `Batman.Set` by passing _n_ items to the constructor:

```coffeescript
set = new Batman.Set(1,2,3,4)
set.get('length') # => 4
```

You can __add__ and __remove__ with the `add` and `remove` functions, which also take any number of items:

```coffeescript
addedItems = set.add(5, 6)
removedItems = set.remove(1)
set.get('length') # => 5
```

If you try to add the same (`===`) item twice, it won't be added:

```coffeescript
addedItems = set.add(5)
set.get('length') # => 5
addedItems        # => []
```

If you try to remove an item that isn't in the set, nothing will happen:

```coffeescript
removedItems = set.remove(100)
set.get('length') # => 5
removedItems      # => []
```

### Observing Batman.Set

Calling these functions inside an accessor function will cause the accessor to track the `Batman.Set`:

- `at`
- `find`
- `merge`
- `forEach` (and any other [`Batman.Enumable` function](http://batmanjs.org/docs/api/batman.enumerable.html), since they call `forEach` under the hood)
- `toArray`
- `isEmpty`
- `has`

So will `get`ting these accessors:

- `first`
- `last`
- `isEmpty`
- `toArray`
- `length`

For example, all these accessors will be recalculated when `students` changes:

```coffeescript
class Classroom extends Batman.Object
  @accessor 'students', -> new Batman.Set

  @accessor 'size', -> @get('students.length')

  @accessor 'hasStudents', ->
    @get('students.isEmpty') # or @get('students').isEmpty()

  @accessor 'numberOfPassingStudents', ->
    # ::count calls forEach in Batman.Enumerable:
    @get('students').count (s) -> s.get('grade') > 1.0
```

`size`, `hasStudents`, and `numberOfPassingStudents` all register `students` as a source. (See [the docs](/docs/api/batman.object_accessors.html#accessors_as_computed_properties) or [this blog post](/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/) for more information about batman.js automatic source tracking.)

Besides automatic source tracking in accessors, you can observe these properties with `observe`.

## `itemsWereAdded`/`itemsWereRemoved`

A set notifies its subscribers by firing:

- `itemsWereAdded` when items are added to the set
- `itemsWereRemoved` when items are removed from the set

Each event is fired with the _items_ that were added and removed.

You can handle these events with `on`:

```coffeescript
set.on 'itemsWereAdded', (addedItems) ->
  alert "There were #{addedItems.length} new items!"

set.on 'itemsWereRemoved', (removedItems) ->
  alert "Say goodbye to #{removedItems.length} items!"
```

_The event _may be_ fired with the internally-determined indexes of the items. This is used internally by batman.js but isn't implemented in all cases._

These functions cause items to be added or removed:

- `add`
- `remove`
- `replace`
- `clear`
- `insert`

Under the hood, batman.js depends on these events to keep `data-foreach` bindings up to date.

## Set Indexes

Set indexes are batman.js's way of searching sets. Batman.js caches these indexes and updates them whenever items are added or removed from the base `Batman.Set`. This way, you can be sure than any indexes you use will be automatically updated when the set is changed.

Consider the `vegetables` set:

```coffeescript
vegetables = new Batman.Set
  {name: "Tomato",    color: "red"}
  {name: "Cucumber",  color: "green"}
  {name: "Radish",    color: "red"}
  {name: "Eggplant",  color: "aubergine"}
```

### Batman.SetIndex

A `Batman.SetIndex` groups the base `Batman.Set` by a property of its members. For example, we can group `vegetables` by `color`:

```coffeescript
vegetablesByColor = vegetables.indexedBy('color')
```

Then, to get vegetables of a certain color, you `get` the color from the set index:

```coffeescript
redVegetables = vegetablesByColor.get('red') # returns a Batman.Set
redVegtables.toArray()
# => [{name: "Tomato", color: "red"}, {name: "Radish", color: "red"}]
```

_(`Batman.SetIndex::get` is an example of the "default accessor as `method_missing`" pattern.)_

The resulting set is just like any other `Batman.Set`, so you can observe it, pass it to view bindings, etc.

If you `get` a value that doesn't exist, you get an empty `Batman.Set`. However, if a matching item is added to the _base_ set, the index will be updated and the derived set will have the matching item added to it. For example, the `yellow` vegetables set is empty at first:

```coffeescript
yellowVegetables = vegetablesByColor.get('yellow')
yellowVegetables.get('length') # => 0
```

But if you add a vegetable with `color: "yellow"`,

```coffeescript
vegetables.add({name: "Butternut Squash", color: "yellow"})
```

it will be immediately added to the derived set:

```coffeescript
yellowVegetables.get('first') # => {name: "Butternut Squash", color: "yellow"}
```

### Batman.UniqueSetIndex

A `Batman.UniqueSetIndex` doesn't return a _set_ of matching items, it returns the _first_ matching item. This is useful when you know that the values of a property will be unique (For example, batman.js uses `MyModel.get('loaded.indexedBy.id')` to update records from JSON by ID).

For example, our `vegetables` all have unique names:

```coffeescript
tomato = vegetables.indexedByUnique("name").get("Tomato")
```

Using `indexedByUnique` in an accessor makes the `Batman.UniqueSetIndex` a source for that accessor. So when the unique set index's value changes, the accessor will be recalculated.

This can be demonstrated by extending our `vegetables` example a little bit. Imagine a garden which should know what vegetables are growing in it. Since it's essentially a group of vegetables, let's extend `Batman.Set`:

```coffeescript
class Garden extends Batman.Set
```

In our app, we want to display red/green for which vegetables are in a garden. For example, `hasTomato`:

```coffeescript
class Garden extends Batman.Set
  @accessor 'hasTomato', ->
    @indexedByUnique('name').get("Tomato")?
```

Now, a Garden will return `true` for `hasTomato` as soon as a tomato is added:

```coffeescript
myGarden = new Garden
  {name: "Spinach", color: "green"}
  {name: "Corn", color: "yellow"}

myGarden.get('hasTomato') # => false
myGarden.add({name: "Tomato", color: "red"})
myGarden.get('hasTomato') # => true
```

## SetSort

A `Batman.SetSort` behaves just like a `Batman.Set`, except that its members are ordered by a given property. If an item is added to the base set, it is also added to the set sort (in its proper place, of course).

Given these vegetables:

```coffeescript
vegetables = new Batman.Set
  {name: "Tomato",    color: "red"}
  {name: "Cucumber",  color: "green"}
  {name: "Radish",    color: "red"}
  {name: "Eggplant",  color: "aubergine"}
```

We can easily sort them by name:

```coffeescript
vegetables.sortedBy("name") # => Batman.SetSort
vegetables.sortedBy("name").mapToProperty("name")
# => ["Cucumber", "Eggplant", "Tomato", "Radish"]
```

They can also be sorted in reverse order:

```coffeescript
vegetables.sortedBy("name", "desc").mapToProperty("name")
# => ["Radish", "Tomato", "Eggplant", "Cucumber"]
```

Or, to sort descending by an accessor:

```coffeescript
vegetables.get('sortedByDescending.name').mapToProperty("name")
# => ["Radish", "Tomato", "Eggplant", "Cucumber"]
```

## Set Caching

You don't have to worry about calling `indexedBy` or `sortedBy` repeatedly. Under the hood, batman.js caches them on their base sets, so it doesn't recalculate the indexes and sorts every time.

## Union, Intersection, Complement

`Batman.BinarySetOperation`s are objects that track _two_ sets and contain the resulting elements from their operations. There are three implemented subclasses of `Batman.BinarySetOperation`:

- [`Batman.SetUnion`](http://batmanjs.org/docs/api/batman.setunion.html) contains all members from both sets, without duplicates.
- [`Batman.SetIntersection`](http://batmanjs.org/docs/api/batman.setintersection.html) contains members which are present in the first set _and_ present in the second set.
- [`Batman.SetComplement`](http://batmanjs.org/docs/api/batman.setcomplement.html) contains members which are in the first set _but not_ present in the second set.

Take note: constructors for binary set operations will fail if either argument is `null`, so be sure to check for that when you're building them!
