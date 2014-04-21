---
layout: post
title: "Adding Batman.js to an Existing Rails App"
date: 2013-10-19 22:08
comments: true
categories:
  - Ruby
  - Rails
  - Javascript
  - CoffeeScript
  - Batman.js
---

I had an existing app, but I wanted to take the front end to the next level. [Batman.js](http://batmanjs.org/) is a full-featured, developer-friendly, Rails-inclined CoffeeScript (or JavaScript) framework with powerful [Rails integration](https://github.com/batmanjs/batman-rails).

<!-- more -->


### Installing Batman.js

I was already using [ActiveModel::Serializer](https://github.com/rails-api/active_model_serializers) to serve JSON from my app. To get Batman on the scene, I included
`batman-rails` in my Gemfile and installed it:

```ruby Gemfile.rb
    require 'batman-rails', '~> 0.15'
```

```bash
  $ bundle install
```

The [batman-rails gem](https://github.com/batmanjs/batman-rails) comes with a generator to get everything in order.
I ran it and restarted my Rails server:

```bash
  $ rails g batman:app # that's not _your_ app name, it's just "app"
  $ powder restart # restart your Rails server one way or another
```

I visited my app's `root_url` and found Batman-rails landing page. How'd it get there!? Sure enough, the Batman generator had added a punchy line to the top of my routes file:

```ruby config/routes.rb
  get "(*redirect_path)", to: "batman#index", constraints: lambda { |request| request.format == "text/html" }
```

It captures all `text/html` requests and passes them to `BatmanController`, which was also created by the generator:

```ruby app/controllers/batman_controller
  class BatmanController < ApplicationController
    def index
      render nothing: true, layout: 'batman'
    end
  end
```

Along with that, there was a new file in my `app/views/layouts` folder, and then of course, `app/assets/batman`.

### My first view

I didn't want the Batman landing page at my `root_url`, I wanted a list of sounds! So, I ran a Batman generator, beefed up the model and controller, created the index html, and redefined the route:

```
  $ rails g batman:scaffold Sounds
```


```coffeescript app/assets/batman/models/sound.js.coffee
    class Lang.Sound extends Batman.Model
      @resourceName: 'sounds'
      @storageKey: 'sounds'

      @persist Batman.RailsStorage

      # Use @encode to tell batman.js which properties Rails will send back with its JSON.
      @encode 'letter'
      @encodeTimestamps()
```


```coffeescript app/assets/batman/controllers/sounds_controller.js.coffee
    class Lang.SoundsController extends Lang.ApplicationController
      routingKey: 'sounds'
      index: (params) ->
        @set("sounds", Lang.Sound.get('all'))
```

```haml app/assets/batman/html/sounds/index.html
    <ul>
      <li data-foreach-sound="sounds">
        <span data-bind="sound.letter" />
      </li>
    </ul>
```


_your filename will be your app name:_
```coffeescript app/assets/batman/lang.js.coffee
    class Lang extends Batman.App
      @root "sounds#index"
```

And now I had my own landing page!

