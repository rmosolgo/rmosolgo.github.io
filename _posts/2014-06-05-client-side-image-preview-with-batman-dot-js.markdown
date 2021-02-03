---
layout: post
title: "Client-Side Image Preview with Batman.js"
date: 2014-06-05 07:26
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
  - HTML5
---

Implementing image preview is breeze thanks to [batman.js](http://batmanjs.org) observers and JavaScript APIs.

<!-- more -->

__The goal__ is to have a user add an image to a file input and _immediately_ preview that image. To accomplish this, we'll turn the uploaded file into a data URI, then set that to the `src` of our `<img/>`.

First, set up the observer in the model:

```coffeescript
class App.ModelWithImage extends Batman.Model
  @encode 'imageDataURI'

  constructor: ->
    super
    @observe 'imageFile', (newVal, oldVal) ->
      if newVal?
        @_setImageDataURIFromFile()
      else
        @set 'imageDataURI', ""
```

This says: "whenever `imageFile` changes, if there is a new value, use it to set the data URI, otherwise, set the data URI to `""`."

Now, implement `_setImageDataURIFromFile`:

```coffeescript
  _setImageDataURIFromFile: ->
    file = @get('imageFile')
    reader = new FileReader
    reader.onload = (e) =>
      dataURI = e.target.result
      @set 'imageDataURI', dataURI
    reader.readAsDataURL(file)
```

You can use it in a template like this:

```html
  <img data-bind-src='component.imageDataURI' />
  <input type='file' data-bind='component.imageFile' />
```

When a user uploads a file, the `<img>` will be automatically updated!
