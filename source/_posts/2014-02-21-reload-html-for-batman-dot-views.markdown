---
layout: post
title: "Reload HTML for Batman.Views"
date: 2014-02-21 08:40
comments: true
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
---

When working on HTML for [`Batman.View`](http://batmanjs.org/docs/api/batman.view.html)s, it can be annoying to refresh and navigate back to wherever you were. Hacking into `Batman.HTMLStore` enables you to reload HTML without refreshing

<!-- more -->

# The Code

_You'll want to include all this code _after_ batman.js and _before_ your app._


```coffeescript
# alter `Batman.HTMLStore`'s default accessor so that it isn't `final` and has an `unset` action:
storeAccessor = Batman.HTMLStore::_batman.getFirst('defaultAccessor')
storeAccessor.final = false
storeAccessor.unset = (path) ->
  if !path.charAt(0) is "/"
    path = "/#{path}"
  @_requestedPaths.remove(path)
  @_htmlContents[path] = undefined

# returns the next superview with a defined source
Batman.View::superviewWithSource = ->
  if @get('source')?
    return @
  else
    return @superview.superviewWithSource()

# Unset the view's HTML, then reload it and re-initialize the view when it loads
Batman.View::refreshHTML = ->
  # climb the view tree to find a view with a defined `source`
  @sourceView ?= @superviewWithSource()
  sourceView = @sourceView
  sourceView.html = undefined
  path = sourceView.get('source')
  if path.charAt(0) isnt "/"
    path = "/#{path}"
  Batman.View.store.unset(path)
  sourceView._HTMLObserver ?= Batman.View.store.observe path, (nv, ov) =>
    sourceView.set('html', nv)
    sourceView.loadView()
    sourceView.initializeBindings()
```

Now, you can call `refreshHTML()` on a `Batman.View` to reload its HTML from the server.

# Do It

In Chrome:

- __right-click, "Inspect Element"__ on a HTML element. The element is now available at `$0` in your console
- __`$context($0).refreshHTML()`__ to get the view for the node and call `refreshHTML` on it.

Cha-ching!




