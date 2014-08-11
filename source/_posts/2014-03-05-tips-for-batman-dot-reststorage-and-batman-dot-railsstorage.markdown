---
layout: post
title: "Tips for Batman.RestStorage and Batman.RailsStorage"
date: 2014-03-05 13:52
comments: true
categories:
  - Batman.js
---

Just a few things I've picked up about `Batman.RestStorage` and `Batman.RailsStorage`.

<!-- more -->

## Use `Model.url` for hooking up to your API

You can set the URL for a model:

```coffeescript
class App.SomeModel extends Batman.Model
  @persist Batman.RestStorage  # or Batman.RailsStorage
  @resourceName: "some_model"
  @url: "/api/v1/some_models"  # will be used for REST actions (instead of plain `/some_models`)
```

or for an instance:

```coffeescript
parent.url = "/api/v1/some_models/somewhere_special"
parent.url.load ->
  console.log("I loaded from a special place!")
```

## Use `autoload` carefully

Say you have an association:

```coffeescript
class App.Parent extends Batman.Model
  @hasMany 'children', autoload: trueOrFalse, saveInline: trueOrFalse
```

If `autoload` is true, `parent.get('children')` will send a request to get children items. By default this is `/children.json?parent_id=#{parentId}`.

You can do a nested url with:

```coffeescript
class App.Child extends Batman.Model
  @persist Batman.RestStorage
  @belongsTo 'parent'
  @urlNestsUnder 'parent' # will request /parents/:parent_id/children/:id/
```

## `saveInline` and `accepts_nested_nested_attributes_for`

`saveInline` goes nicely with Rails [`accepts_nested_attributes_for`](http://api.rubyonrails.org/v4.0.1/classes/ActiveRecord/NestedAttributes/ClassMethods.html), except that Rails expects a parameter called `children_attributes`, but batman.js sends `children`.  You can work around it in a couple ways:

```coffeescript
class App.Parent extends Batman.Model
  @hasMany 'children', saveInline: true, encoderKey: 'children_attributes' # this expects children_attributes in JSON from the server, too
```

And I confess I have done this:

```coffeescript
class App.Parent extends Batman.Model
  @hasMany 'children', saveInline: true

  toJSON: ->
    builtJSON = super
    builtJSON.children_attributes = builtJSON.children
    delete builtJSON.children
    builtJSON
```

## Take advantage of Rails Validation Errors

When Rails responds with `422` and a JSON object with `{ "errors" : { ... } }`, they'll be added to your model's errors. [`data-formfor`](http://batmanjs.org/docs/api/batman.view_bindings.html#data-formfor) has a built-in thing for that, so make sure you have an errors div in your form:

```html
<form data-formfor-somemodel='currentSomeModel' data-event-submit='saveSomeModel'>
  <div class='errors'><!-- will be automatically populated --></div>
</form>
```

