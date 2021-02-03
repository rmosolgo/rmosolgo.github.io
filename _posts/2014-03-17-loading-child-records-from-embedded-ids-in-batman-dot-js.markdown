---
layout: post
title: "Loading Child Records from Embedded IDs in Batman.js"
date: 2014-03-17 11:03
categories:
categories:
  - Batman.js
---

[Batman.js](http://batmanjs.org/) provides a powerful [model associations](http://batmanjs.org/docs/api/batman.model_associations.html) inspired by Ruby on Rails. But, if you're loading child items from ids, it's not going to work out of the box.

<!-- more -->

## The problem

Batman.js `@hasMany` (in v0.15.0, anyways) doesn't support loading items from JSON like this:

```javascript
  {
    "parent" : {
      "id": 1,
      "children": [10, 11, 12] /* <- here's tough part */
    }
  }
```

## The solution

Instead of `Model.hasMany`, use a custom encoder to load the records:

```coffeescript
class Parent extends Batman.Model
  @encode 'children',
    encode: (value, key, builtJSON, record) ->
      ids = value.mapToProperty('id')
      builtJSON.key = ids

    decode: (value, key, incomingJSON, outgoingObject, record) ->
      ids = value
      childRecords = new Batman.Set
      ids.forEach (id) ->
        child = new Child # <-- your Child class here
        child.set('id', id)
        child.load()
        childRecords.add(child) # one caveat -- the childRecords' attributes will be empty until their requests come back.
      childRecords.set('loaded', true)
      outgoingObject.key = childRecords
      record.set(key, childRecords) # this will fire updates in case bindings are waiting for this data
```

Make sure to add your own `Child` class! Also, note that their attributes will be empty until their AJAX requests resolve!
