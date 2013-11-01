---
layout: post
title: "Use Batman.View to slim down your controllers rein in your display logic"
date: 2013-10-21 15:16
comments: true
published: false
categories:
  - Ruby
  - Rails
  - JavaScript
  - CoffeeScript
  - Batman.js
---

[Batman.js](http://batmanjs.org/)'s [view bindings](http://batmanjs.org/docs/api/batman.view_bindings.html) provide a powerful link between your app and the DOM, but how do you take full advantage of them? Extend [Batman.View] to hold view-specific helpers (à la [Model presenters or decorators](http://stackoverflow.com/questions/7860301/rails-patterns-decorator-vs-presenter)) and set up callbacks for the view's lifecycle events.

<!-- more -->

_For the purposes of this blog post, [batman_cupcakes]() ([source]()), a little Batman app serves as
a storefront for a hip, in-demand cupcakery. The baker is putting a new type of cupcake online every 30s,
but the limited supply is depleted at almost the same pace!_

