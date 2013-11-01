---
layout: post
title: "Load Batman Models from specific Urls"
date: 2013-10-28 10:19
comments: true
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
---

[Batman.js](http://batmanjs.org/)'s  [REST Storage Adapter](https://github.com/batmanjs/batman/blob/master/src/model/storage_adapters/rest_storage.coffee) provides a clean interface for operating on records with vanilla REST urls -- but what about when you need a lil' something more?

<!-- more -->

First of all, the magic happens in [Batman.RestStorage#UrlForRecord](https://github.com/batmanjs/batman/blob/master/src/model/storage_adapters/rest_storage.coffee#L90). For an already-persisted record, you have a few options:

## pass `recordUrl` to loadWithOptions/findWithOptions

__findWithOptions__ or __loadWithOptions__'s `options` can take a `recordUrl` param, which is used to retrieve the record. Use `findWithOptions` to load a new record:

```coffeescript
  model_id = 1 # you might get this from the request path or from another model's attributes
  model_url = "/some_models/#{model_id}?language=fr"
  MyApp.SomeModel.findWithOptions model_id, {recordUrl: model_url}, (err, model) ->
    # your model was loaded with the param language=fr!
```

or use `loadWithOptions` to reload an existing record:

```coffeescript
  # using model from above...
  model_url = "/some_models/#{model.get('id')}?language=es"
  model.loadWithOptions {recordUrl: model_url}, (err, model) ->
    # your model was loaded with the param language=es!
```

## Set `record.url`

If you're reloading an already-loaded model, you can set its (POJO) `url` attribute to the URL you want to use:

```coffeescript
  model.url = "/#{model.constructor.storageKey}/#{model.get('id')}?language=zh"
  model.load (err, model) ->
    # your model was loaded with the param language=zh!
```


## For a New Records or Collections?

I'm not sure yet. Check out [Batman.RestStorage#UrlForCollection](https://github.com/batmanjs/batman/blob/master/src/model/storage_adapters/rest_storage.coffee#L109)!


