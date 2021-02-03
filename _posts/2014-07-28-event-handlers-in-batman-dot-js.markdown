---
layout: post
title: "Event Handlers in Batman.js"
date: 2014-07-28 13:23
categories:
  - Batman.js
---


In [batman.js](http://batmanjs.org), event handlers respond to user interactions like "click" and "submit". You can use them to modify application state in response to those interactions.

<!-- more -->

Let's look at:

- What event handlers are and where they're defined
- How you can connect handlers to DOM events
- How you can pass arguments to event handlers
- What `@` refers to inside event handlers

## What Are Event Handlers?

In short, an _event handler_ can be _any function inside the render context_.

Usually, this means it's a prototype function on a view:

```coffeescript
class MyApp.ItemsIndexView extends Batman.View
  myEventHandler: -> # handle some event
```

or, it's a prototype function on a controller:

```coffeescript
class MyApp.ItemsController extends MyApp.ApplicationController
  myEventHandler: -> # handle some event
```

Since the main `MyApp` is also inside the render context, you can also use class functions on the app as event handlers:

```coffeescript
class window.MyApp extends Batman.App
  @myEventHandler: -> # handle some event
```

__All__ of those functions are fair game to be wired up as event handlers.

## Hooking up Event Handlers

To connect a function to a DOM event, use the `data-event` binding. You can bind to pretty much any event (I don't know of one that you _can't_ bind to).

The binding takes the form:

```coffeescript
"data-bind-#{eventName}='#{handlerName}'"
```

For example, to bind a `click` event to `myEventHandler` on this `<button>`:

```html
<button data-event-click='myEventHandler'>Click Me</button>
```

You can also bind to the `submit` event of a `<form>`:

```html
<form data-event-submit='saveData'>
  <input type='submit'>Save</input>
</form>
```

## Arguments in Event Handlers

Event handlers have two sets of arguments:

- arguments that you pass in via `withArguments` filters
- arguments that are automatically passed in by batman.js

### Custom Arguments with "withArguments"

You can choose some values to pass in with a `withArguments` filter in your binding.

Consider this event handler:

```coffeescript
class MyApp.ItemsController extends MyApp.ApplicationContorller
  alertItemName: (item) ->
    itemName = item.get('name')
    alert(itemName)
```

I could call this with an `item` by using a `withArguments` filter:

```html
<h1 data-bind='item.name'></h1>
<button data-event-click='alertItemName | withArguments item'>Alert!</button>
```

You can pass multiple arguments with `withArgument` by separating them with commas.

For example, if I want more flexible alerts, I could redefine the event handler to take _two_ arguments:

```coffeescript
class MyApp.ItemsController extends MyApp.ApplicationContorller
  alertItemName: (item, punctuation) ->
    itemName = item.get('name')
    alert(itemName + punctuation)
```

Then, pass _two_ arguments into it, separated with `, `:

```html
<h1 data-bind='item.name'></h1>
<button data-event-click='alertItemName | withArguments item, "!" '>Alert!</button>
<button data-event-click='alertItemName | withArguments item, "?" '>Alert?</button>
<button data-event-click='alertItemName | withArguments item, "." '>Alert.</button>
```

__Note__ that you __must__ provide both arguments to the handler. If you don't, batman.js's automatic arguments will take the place of the missing argument!

### Automatic Arguments

When batman.js invokes an event handler, it __automatically passes in__ a few arguments. Here's a handler that uses the automatic arguments:

```coffeescript
class MyApp.ItemsController extends MyApp.ApplicationContorller
  myEventHandler: (node, event, view) ->
```

It's invoked with:

- `node`: the DOM node where the event was triggered. For example, a `<button>`. If you use the same event handler on different nodes, this value will be different.
- `event`: The event object for the event.  If you're using `batman.jquery`, it's the jQuery event object. It contains meta-information about the event.
- `view`: The nearest `Batman.View` instance to `node`.


### Combining Custom and Automatic Arguments

You can combine custom and automatic arguments. Simply define a handler whose __last three__ arguments are the batman.js automatic arguments:


```coffeescript
class MyApp.ItemsController extends MyApp.ApplicationContorller
  alertItemName: (item, punctuation, node, event, view) ->
    itemName = item.get('name')
    alert(itemName + punctuation)
```

And use `withArguments` to pass arguments to the function. You __must__ pass the __same number__ of arguments. For example:


```html
<h1 data-bind='item.name'></h1>
<button data-event-click='alertItemName | withArguments item, "!"'>Alert!</button>
<!-- note the empty string, "" -->
<button data-event-click='alertItemName | withArguments item, ""'>Alert</button>
```

When batman.js passes arguments to the function, it simply merges the `withArguments` array with its automatic array. So, if your `withArguments` array is too short, you won't get the same results.

## `@` in Event Handlers

When batman.js dispatches an event handler, it looks up the base object _where that handler is defined_. Then, it uses that object as `@` inside the handler.

For example, consider two event handlers. One is defined on a view:

```coffeescript
class MyApp.ItemsIndexView extends Batman.View
  eventHandlerOne: ->
    console.log(@) # => will be the ItemsIndexView instance
```

The other is defined on a controller:

```coffeescript
class MyApp.ItemsController extends App.ApplicationController
  eventHandlerTwo: ->
    console.log(@) # => will be the ItemsController instance
```

If you were to hook up those event handlers to buttons:

```html
<button data-event-click='eventHandlerOne'></button>
<button data-event-click='eventHandlerTwo'></button>
```

then click the buttons, you would see the `ItemsIndexView` object and the `ItemsController` object in your console:

```javascript
ItemsIndexView {bindings: Array[7], subviews: Set, _batman: _Batman, viewClass: function, source: "events/index"…}
ItemsController {redirect: function, handleError: function, errorHandler: function, _batman: _Batman, _actionFrames: Array[0]…}
```

Since batman.js looks up the base object, event handlers behave just like normal functions in the place you define them.
