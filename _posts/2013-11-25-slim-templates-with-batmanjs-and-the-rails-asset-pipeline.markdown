---
layout: post
title: "Slim Templates with Batman.js and the Rails Asset Pipeline"
date: 2013-11-25 13:28
comments: true
categories:
  - Rails
  - Batman.js
  - Slim
---


You can use [Slim](http://slim-lang.com/) (or Haml) to serve your [Batman.js](http://batmanjs.org) templates in the Rails Asset Pipeline.

<!-- more -->

# 1. Include Slim in your gemfile

Add this line to your `Gemfile`:

```ruby Gemfile
gem "slim"
```

# 2. Register the Slim engine with Rails

Make a new initializer (eg, `config/initializers/slim_assets.rb`) and put this in it:

```ruby config/initializers/slim_assets.rb
Rails.application.assets.register_engine('.slim', Slim::Template)
```

Credit: [Dillon Buchanan](http://www.dillonbuchanan.com/programming/rails-slim-templates-in-the-asset-pipeline/)

### Update: Serving compiled Slim (or Haml) assets in production

When you deploy to production, if you have `config.initialize_on_precompile = false`, an initializer isn't going to work. You'll have to register the Sprockets engine another way. Add it to the application config in `config/application.rb`:

```ruby config/application.rb
module MyApp
  class Application < Rails::Application
    # ... config stuff ...
    config.before_initialize do |app|
      require 'sprockets'
      require 'slim'
      # require 'tilt' # for Haml
      Sprockets::Engines #force autoloading
      Sprockets.register_engine '.slim', Slim::Template
      # Sprockets.register_engine '.haml', Tilt::HamlTemplate # for Haml
    end
    # ... more config stuff ...
  end
end
```

Now, you'll have the Slim template engine available even if your app doesn't intialize, which is most notably the case for `bundle exec rake assets:precompile`. Nice!

# 3. Beef up your BatmanController

At time of writing, the `batman-rails`-generated BatmanController won't work right in production. There's an [outstanding PR](https://github.com/batmanjs/batman-rails/pull/46) with a fix. If that's closed, then we're good to go. In the mean time, Make your `app/controllers/batman_controller.rb` look like this:

```ruby app/controllers/batman_controller.rb
class BatmanController < ApplicationController
  def index
    if request.xhr?
      prefix_length = Rails.application.config.assets.prefix.length + 1
      path = request.path[prefix_length..-1]
      render :text => Rails.application.assets[path]
    else
      render nothing: true, layout: 'batman'
    end
  end
end
```


When this is done, any files ending in `.html.slim` in `assets` will be served as rendered HTML in response to XHR (Ajax) requests. Note that _all non-XHR_ requests will still receive the `batman` layout (but then Batman will respond to the request, so you're all good).
