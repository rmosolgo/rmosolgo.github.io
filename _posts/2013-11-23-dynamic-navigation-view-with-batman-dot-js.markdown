---
layout: post
title: "Dynamic Navigation View with Batman.js"
date: 2013-11-23 14:50
categories:
  - Batman.js
---

Creating a dynamic, context-based navigation menu is a breeze with [batman.js](http://batmanjs.org/) and [batman-rails](https://github.com/batmanjs/batman-rails) thanks to Batman's [data-route](http://batmanjs.org/docs/api/batman.view_bindings.html#data-route) view binding and the [object[key]](http://batmanjs.org/docs/api/batman.view_filters.html#value%5Bkey%5D_%3A_value) view filter. Here's how I did it.

<!-- more -->

I have Rails/Batman app generated with [batman-rails](https://github.com/batmanjs/batman-rails) generators. I'm using Slim-assets for my Batman HTML. Source of the app is [here](https://github.com/rmosolgo/batman-rails-example-crepes).

# Models

My app allows users to design crepes, and so far it has two models, Crepes and Ingredients:

```coffeescript /app/assets/javascripts/batman/models/crepe.js.coffee
class Creperie.Crepe extends Creperie.ApplicationModel
  # ... stuff
  toString: ->
    "#{@get('name')} ($#{@get('price')})"
```

```coffeescript /app/assets/javascripts/batman/models/ingredient.js.coffee
class Creperie.Ingredient extends Creperie.ApplicationModel
  # ... stuff
  toString: ->
    "#{@get('name')} (#{@get('category')})"
```

I defined `toString` on both of the models because when a JS object instance is rendered as text, `toString` is called automatically.

# Layout

My app defines `/crepes` and `/ingredients`, and I want each of those pages to show a side-bar nav that lists all items and provides a link to create a new item. So, I added a `nav` to my Rails layout where I will render my `Creperie.ContextNavView`. I attach the `Batman.View` with the [`data-view` view binding](http://batmanjs.org/docs/api/batman.view_bindings.html#data-view):

```ruby /app/views/layouts/batman.html.slim
doctype html
html
  head
    title data-bind='Title | default "Home" | prepend "Creperie | "'
    = stylesheet_link_tag    "application", :media => "all"
    = javascript_include_tag "creperie"
    = csrf_meta_tags
  body
    header
      section
        h1 Creperie!
      nav data-view='NavBarView'

    / here is my context view:
    nav data-view='ContextNavView'

    section#main data-yield='main'

  script type="text/javascript"
    | Creperie.run();
```

# View

Then, I defined a custom [Batman.View](http://batmanjs.org/docs/views.html) called `ContextNavView`.


I defined the prototype's source attribute to point to the HTML template which I will create next. That way, Batman knows where to find the HTML for this view. This is the same as passing the source to the constructor, eg, `new Creperie.ContextNavView(source: 'layouts/context_nav')`.


I also defined the `viewDidAppear` hook for this view. You can define hooks for any point in a [`Batman.View`'s lifecycle](http://batmanjs.org/docs/views.html). I set up an [observer](http://batmanjs.org/docs/api/batman.object.html#prototype_function_observe) on my app's `currentRoute.controller`.

```coffeescript /app/assets/javascripts/batman/views/context_nav_view.js.coffee
class Creperie.ContextNavView extends Creperie.ApplicationView
  source: 'layouts/context_nav' # my HTML template

  viewDidAppear: ->
    Creperie.observe "currentRoute.controller", (newValue, oldValue) ->
      currentController = newValue
      itemClassName = Batman.helpers.singularize(
          Batman.helpers.camelize(currentController)
        ) # camelize and singularize the controller name
      itemClass = Creperie[itemClassName]
      if itemClass?
        @set 'itemClass', itemClass
        @set 'itemRoute', currentController
```

This is made possible because Batman (v 0.15.0) keeps track of the current route at `MyApp.currentRoute` (which you can access in your code or in the console as `MyApp.get('currentRoute')`). Since my controllers are all defined with Rails-style names, I can count on the controller names matching the model that I want to display.

# Template

Last, I defined the template which `ContextNavView` uses as its source:

```ruby /app/assets/javascripts/batman/html/layouts/context_nav.html.slim
ul.items
  li.item data-foreach-item='itemClass.all'
    a data-route='routes[itemRoute][item]'
      span data-bind='item'
    a.edit data-route='routes[itemRoute][item].edit' edit
  li.new-item
    a data-route='routes[itemRoute].new'
      span New&nbsp;
      span data-bind='itemClass.name'
```

The big win here was sending strings to `App.routes` with `[]` in the keypath. That way, I could meta-program my routes -- I didn't have to make them explicit.

# So what?

- Use `MyApp.currentRoute` to get information about the current page.
- Subclass `Batman.View` to provide site-wide navs (or other views).
- Meta-program your routes (or other parts of the nav) by using `[]` in your keypaths.
