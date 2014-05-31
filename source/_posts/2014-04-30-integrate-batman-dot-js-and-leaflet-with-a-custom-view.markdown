---
layout: post
title: "Integrate Batman.js and Leaflet with a Custom View"
date: 2014-04-30 23:33
comments: true
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
---

[batman.js](http://batmanjs.org) views are one of the best ways to integrate other JS libraries with batman.js data structures like `Batman.Object` and `Batman.Set`. For example, you can use a custom view to display `Batman.Model`s with [leaflet.js](http://leafletjs.com)

<!-- more -->

I've always wanted to try batman.js + leaflet. I had to:

- Use `@option` to define view APIs
- Initialize the custom view, controlling for async loading of data & map
- Observe `Batman.Object`s to keep leaflet up-to-date.
- Listen to leaflet to keep batman.js up to date

I ended up making an abstract `LeafletView`, implemented by `LeafletPointView` and `LeafletCollectionPointView`.

Be sure to check out the [live example](http://bl.ocks.org/rmosolgo/11443841) and source code ([custom views](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/coffee/leaflet_view.coffee), [index html](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/html/monuments/index.jade#L19), [edit html](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/html/monuments/edit.jade#L19))!

## `@option` in Custom Views

`@option` allows you to pass values explicitly into your custom view. That way, you can eliminate the guesswork of climbing the view tree or looking up to the controller for some value.

It provides a view binding _and_ an accessor for your custom view. In my case, I used:

```coffeescript
class App.LeafletView extends Batman.View
  @option 'draggable'
```

To provide in my HTML:

```html
<div data-view='App.LeafletView' data-view-draggable='true'></div>
```

And in my view code:

```coffeescript
@get('draggable') # => returns the value passed to the binding
```

This also works for objects, as in `@option 'item'`:

```html
<div data-view='App.LeafletPointView' data-view-item='monument'></div>
```

Then I have easy access to my record:

```coffeescript
@get('item')
```

## Initializing Custom Views

Initializing custom batman.js views is tough because:

- Views are constructed before they're added to the DOM
- Bindings are initialized without values (and their objects may not be loaded from the server yet)
- Lifecycle events may fire more than once

So, you have to be prepared for undefined values and for `viewDidAppear` to be fired more than once.

- [__Use `observeOnce`__](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/coffee/leaflet_view.coffee#L38) to fire on change from `undefined` to some value. My case was different because I had to wait for the binding _and_ for the map to load, hence the `leafletReady` event.
- [__Check for initialization__ in `viewDidAppear` handlers](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/coffee/leaflet_view.coffee#L52)

## Keeping Other Libraries up to Date

Integrating batman.js with other JavaScript libraries usually means setting up event handlers so that events pass from an outside proxy of a `Batman.Object` to the object itself.

For example, to update a leaflet marker when a `Batman.Object` is changed, you have to observe the `Batman.Object` so that [whenever `latitude` or `longitude` changes, you update the marker](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/coffee/leaflet_view.coffee#L149):

```coffeescript
# From App.LeafletPointView, @get('item') returns the object
@observe 'item.latitude', (nv, ov) ->
  @updateMarker(@get('item'), centerOnItem: true) if nv?
@observe 'item.longitude', (nv, ov) ->
  @updateMarker(@get('item'), centerOnItem: true) if nv?
```

You have to link the other way too. To update a record when its marker is updated (by dragging), [create a handler](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/coffee/leaflet_view.coffee#L85):

```coffeescript
# from App.LeafletView
marker.on 'dragend', =>
  # ...
  # get values from leaflet and update batman.js
  latLng = marker.getLatLng()
  item.set 'latitude', latLng.lat
  item.set 'longitude', latLng.lng
  # ...
```

`App.LeafletCollectionPointView` uses [`Batman.SetObserver`](http://batmanjs.org/docs/api/batman.setobserver.html) to [track adding, removing and modifying items](https://github.com/rmosolgo/batmanjs-leaflet-example/blob/master/coffee/leaflet_view.coffee#L174) (just like `Batman.SetSort`).