---
layout: post
title: "Batman.js Controller Testing with Jasmine"
date: 2014-04-22 08:30
comments: true
categories:
  - Batman.js
---

You can use [jasmine](http://jasmine.github.io/) to test [batman.js](http://batmanjs.org) controllers by looking them up from the controller directory, then executing actions with `executeAction`.

<!-- more -->



## Setup

To set up,

- make sure the app is [running](http://batmanjs.org/docs/api/batman.app.html#class_function_run) (so that the [layout](http://batmanjs.org/docs/api/batman.app.html#class_property_layout) view will be present)
- get the controller you want from [`App.controllers`](http://batmanjs.org/docs/api/batman.app.html#class_accessor_controllers) (a [ControllerDirectory](http://batmanjs.org/docs/api/controllerdirectory.html) )

```coffeescript
describe 'PeopleController', ->
  @beforeEach ->
    App.run()
    @peopleController = App.get('controllers.people')

  it 'is present', ->
    expect(@peopleController.constructor).toBe(App.PeopleController)

```
In our tests, we'll use [`Batman.Controller::executeAction`](http://batmanjs.org/docs/api/batman.controller.html#prototype_function_executeaction) to fire controller actions. This way, before-actions and after-actions will be run, too.

## Functions Are Called on Records

Use Jasmine `spyOn(...).andCallThrough()` to make sure functions have been called

```coffeescript
  describe 'edit', ->
    # This action is invoked from a view binding, not a route
    # so it takes `person`, not `params`....
    it 'calls transaction on the person', ->
      person = new App.Person(id: 1)
      spyOn(person, 'transaction').andCallThrough()
      @peopleController.executeAction('edit', person)
      expect(person.transaction).toHaveBeenCalled()
```

## Options Passed to Render

Get the most recent render arguments from jasmine's `mostRecentCall`. It will be the options passed to `@render`.

```coffeescript
    it 'renders into the dialog', ->
      person = new App.Person(id: 1)
      spyOn(@peopleController, 'render').andCallThrough()
      @peopleController.executeAction('edit', person)
      lastRenderArgs = @peopleController.render.mostRecentCall.args[0]
      lastYield = lastRenderArgs["into"]
      expect(lastYield).toEqual("modal")
```

## Functions Called on Model Classes

Checking class to `get` is tough becuase there are a lot of them! I just iterate through and make sure nothing jumps out as wrong:

```coffeescript
  describe 'index', ->
    it 'gets loaded people, not all people', ->
      spyOn(App.Person, 'get').andCallThrough()
      @peopleController.executeAction('index')
      # there are a lot of calls to App.Person.get, just make sure
      # that "all" wasn't requested!
      loadedCalls = 0
      for call in App.Person.get.calls
        getArg = call.args[0]
        expect(getArg).not.toMatch(/all/)
        if getArg.match(/loaded/)
          loadedCalls += 1
      expect(loadedCalls).toBeGreaterThan(0)
```

## Renders a Specific View

Rendering into the default yield is easy enough -- just check `layout.subviews` for an instance of the desired view.

```coffeescript
    it 'renders the PeopleIndexView', ->
      @peopleController.executeAction('index')
      hasPeopleIndexView = App.get('layout.subviews').some (view) -> view instanceof App.PeopleIndexView
      expect(hasPeopleIndexView).toBe(true)
```