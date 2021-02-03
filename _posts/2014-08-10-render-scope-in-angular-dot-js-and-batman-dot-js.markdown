---
layout: post
title: "Render Scope in AngularJS and Batman.js"
date: 2014-08-10 18:45
categories:
  - Batman.js
  - Angular.js
  - Framework Comparison
---

[Batman.js](http://batmanjs.org) and [AngularJS](http://angularjs.org) both create hierarchical view scopes, but their implementations are very different.

<!-- more -->

_(please forgive my inconsistent rendering of AngularJS/Angular/Angular.js/angular, I don't know which one is right!)_

In batman.js and Angular, there is a view scope _hierarchy_ which mirrors the DOM. In this heirarchy, objects may:


- add values into the render scope
- access _their own_ values
- belong to a _parent object_
- access values from _their parents_
- have _child objects_ of their own

Consider a page like this:

[![Batman.js view hierarchy](/images/batmanjs_nested_views.png)](/images/batmanjs_nested_views.png)

The `HouseholdView` has many child views. The `PersonView`s belong to their parent, `HouseholdView`. They may access values from `HouseholdView` (such as the shared `householdName`).

_Note: The batman.js view hierarchy includes a few other objects as well -- see below._

# Finding Values in the Hierarchy

To answer the question "how can child views access data from their parents", Batman.js and Angular take different approaches.

### $scope & Prototypal Inheritance

In Angular, data bindings are evaluated against a __magical `$scope` object__. The scope object has key-value pairs which correspond to values in the data bindings. When `$scope`s are created, Angular massages (tampers with?) the prototypal inheritance chain so that a child scope's prototype _is_ its parent scope.

(Usually, an object's prototype is another "pristine" object of its same type. It's generally treated as the "perfect instance" of the type. Other instances delegate to the prototype for properties that aren't defined explicitly on themselves.)

In this case, a child `$scope`'s prototype is not a "pristine instance", but instead it's the parent `$scope` object. That way, if a value isn't found in a child scope, it is looked up in the prototype chain. This is __brilliant__. Angular delegates value lookup to built-in JavaScript features. (There is one gotcha described below.)

When a parent `$scope` has many children, all children have the same parent `$scope` object as their prototype.

### Batman.View & View::lookupKeypath

Batman.js builds a __tree of `Batman.View` objects__. The root of the tree is called the `LayoutView` and it is created automatically by batman.js. Each view keeps track of its children in its `subviews`, which is a `Batman.Set` containing views that are rendered inside it. Each view also keeps track of its `superview`, which is its parent `Batman.View`.

To evaluate data bindings, batman.js uses `lookupKeypath` on the view in question. This function climbs the "view hierarchy", which actually includes a few extra objects:

- The `Batman.Controller` instance which rendered the view
- `Batman.currentApp`, which is the `Batman.App` subclass that you defined (the clas, not an instance)
- `Batman.container`, which is usually `window`

Here's the whole view hierarchy from the previous example:

[![The whole batman.js view hierarchy](/images/batmanjs_nested_views_whole_tree.png)](/images/batmanjs_nested_views_whole_tree.png)

Since `Batman.currentApp` is in the view hierarchy, any `@classAccessor`s you define there are accessible in view bindings, akin to global scope in JavaScript.

# Automatically-Created Scopes

In batman.js and Angular, there are data bindings that create child scopes of their own. For example, `ng-repeat` and `data-foreach` both create a collection of child scopes with the same parent.

Angular does this by creating many child `$scopes` with the same parent `$scope` as their prototype.

Batman.js does this by automatically adding nodes to the view hierarchy. One downside of batman.js is that creating lots and lots of new views is CPU-intensive. I don't know whether the same is true for creating `$scope`s.

# How Does It Know Which Scope to Bind To?

When I was reading about `$scope`, I learned that some new Angular users hit a snag when they try to set values on a _parent scope_ from within a _child scope_. As JavaScript should, it updates the child `$scope` with the new value, not the parent `$scope`, which is the child's prototype.

That's how prototypal inheritance works: It looks up missing values on the prototype, but it sets _new_ values on the instance. Then, it stops "falling back" to the prototype for the property that was set on the instance.

To work around this, it's recommended to "always use a `.` in your `ng-model`s". (`ng-model` is a binding that creates a child scope.)

Batman.js doesn't have this problem because, when uses `lookupKeypath`, it remembers which `View` object was the target for that keypath, then updates _that object_ whenever the keypath changes.

However, Batman.js is prone to a different gotcha. If you leave an accessor unset (ie, returns `undefined`), then set it _after_ a view has rendered, it's possible that `View::lookupKeypath` won't find it correctly. To avoid this, set defaults (or `null`) before bindings are evaluated:

- before `@render` in controller actions
- in the `constructor` for view instances

Or, make sure `@accessor`s return `null` instead of `undefined`.

Batman.js treats `undefined` as the signal that an object doesn't have an accessor for a keypath, so be careful when setting keys `undefined`!

# How Does It Know When to Update the DOM?

When these scope objects (`View` or `$scope`) change, the framework must update the DOM accordingly.

Angular has a "digest cycle" where it checks for changes in the `$scope` since last run, then updates the DOM if necessary. It automatically tracks any values that are put into templates. You can also watch other keys on `$scope` with `$scope.$watch`. If you modify `$scope` from _outside_ Angular.js code, you must manually trigger the digest cycle with `$scope.$apply`.

`Batman.View` uses the [`Batman.Property`](http://rmosolgo.github.io/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/) system to automatically track dependencies and changes. Any keypath that is passed to a `data-` binding is automatically observed. DOM updates are triggered when:

- A keypath is updated with `set`. Doesn't matter whether it's inside batman.js code or inside an AJAX callback -- batman.js will recognize the update either way.
- A property's dependencies change. When you declare a computed property with `@accessor` and bind it to a view, the view will update the DOM whenever that property's dependencies cause it to change.

(In fact, those two cases are the heart of observability in batman.js: assign a value with `set` or delegate to batman.js's source tracking.)

To force an update, use `set` to update a bound property or one of its dependencies.

# Other Random Points

- Angular's "evalute an expression" is like batman.js's "lookup a keypath"
- `Batman.View::propagateToSubviews` is like `$scope.$broadcast`: it sends messages down the view tree.
- As of batman.js almost-v0.17, there is no analog for `$scope.$emit` (which sends events _up_ the view chain)
- batman.js exports global function `$context($0)` which is just like `angular.element($0).scope()` (where `$0` is the highlighted element in the Chrome inspector).

# My Opinion

I think Angular's `$scope` is brilliant. I imagine it's performant as well, although I don't know (and I'm currently writing without internet access). It introduces few gotchas. In general, it seems like it Just Works<sup>TM</sup>.

I'm in the market to improve the performance of `Batman.View`, but I'm not sure I can take anything from `$scope`. All of batman.js depends on playing by the observability rules. I don't see any way I can get native JS prototypal inheritance to participate in that.

I also like sticking with the "It's just batman.js" in the view layer. If you can write good `@accessor`s, then you've mastered `Batman.View`, too.
