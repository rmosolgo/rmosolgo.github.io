---
layout: post
title: "Batman.Model lifecycle callbacks"
date: 2014-03-19 10:52
comments: true
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
---

A `Batman.Model` has a `lifecycle` object that fires events on the record when it's being dirtied, cleaned, loaded, saved or destroyed.

<!-- more -->

## Hooking up callbacks

Love 'em or hate 'em, Active Record callbacks can be just the thing for certain problems. `Batman.Model` provides similar functionality for records.

You can hook into lifecycle events by creating listeners on the prototype:

```coffeescript
class App.AddressBook extends Batman.Model
  @::on 'before save', ->
    # remove contacts with no email:
    contacts = @get('contacts')
    contacts.forEach (contact) ->
      if !@contact.get('email')
        contacts.remove(contact)
```

__One caveat:__ Unlike ActiveRecord's `before_validation`, you can't abort a storage operation from a batman.js lifecycle callback. You can `throw`/`catch`, though:

```coffeescript
class App.AddressBook extends Batman.Model
  @::on 'before save', -> throw "Stop saving!"

addressBook = new App.AddressBook
try
  addressBook.save()
catch err
  # => err is "Stop saving!"
  addressBook.isNew() # => true
```

## Available callbacks

These keys can be observed like this:

```coffeescript
class App.AddressBook extends Batman.Model
  @::on "#{someEventName}", -> someCallback()
```

### Saving Records

For records where `isNew` is `true`, `create` callbacks are fired. Otherwise, `save` callbacks are fired.

1. `enter dirty`
1. `set`
1. `enter creating` OR `enter saving`
1. `create` OR `save`
1. `exit creating` OR `exit saving`
1. `enter clean`
1. `created` OR `saved`
1. Callback passed to `Model::save`
1. `enter destroying`
1. `destroy`
1. `exit destroying`
1. `enter destroyed`
1. `destroyed`
1. Callback passed to `Model::destroy`

### Loading a Record From Memory

1. `enter loading`
1. `load`
1. `exit loading`
1. `enter clean`
1. `loaded`
1. Callback passed to `Model.load`


### Others

There are others... Check out `Batman.StateMachine` to see specific transition events and see `InstanceLifecycleStateMachine` for other events and transitions not listed here. There are tons of combinations, but I tried to hit the main ones!

## How it works

Every `Batman.Model` instance has a `InstanceLifecycleStateMachine` at `lifecycle`. That state machine extends `Batman.DelegatingStateMachine`, which means it fires all of its own events on its base -- in this case, a `Batman.Model` instance. The batman.js source for `Model` shows the different state and transition names, and `Batman.StateMachine` shows how these names translate to events.
