---
layout: post
title: "Watching files during Rails development"
date: 2017-04-12 14:09
categories:
- Ruby
- Rails
---

You can tell Ruby on Rails to respond to changes in certain files during development.

<!-- more -->

Rails knows to watch `config/routes.rb` for changes and reload them when the files change. You can use the same mechanism to watch other files and take action when they change.

I used this feature for [react-rails](https://github.com/reactjs/react-rails) server rendering and for [GraphQL::Pro](http://graphql.pro) static queries.

## app.reloader

Every Rails app has [a `@reloader`](https://github.com/rails/rails/blob/8f59a1dd878f56798f88369fa5b448f17a29679d/railties/lib/rails/application.rb#L135), which is a local subclass of [`ActiveSupport::Reloader`](http://api.rubyonrails.org/classes/ActiveSupport/Reloader.html). It's used whenever you call [`reload!` in the Rails console](https://github.com/rails/rails/blob/fe1f4b2ad56f010a4e9b93d547d63a15953d9dc2/railties/lib/rails/console/app.rb#L29-L34).


It's attached to a [rack middleware](https://github.com/rails/rails/blob/d3c9d808e3e242155a44fd2a89ef272cfade8fe8/railties/lib/rails/application/default_middleware_stack.rb#L51-L53) which [calls `#run!`](https://github.com/rails/rails/blob/d3c9d808e3e242155a44fd2a89ef272cfade8fe8/actionpack/lib/action_dispatch/middleware/executor.rb#L10) (which, in turn, [calls the reload blocks if it detects changes](https://github.com/rails/rails/blob/291a098c111ff419506094e14c0186389b0020ca/activesupport/lib/active_support/reloader.rb#L57-L63)).

## config.to_prepare

You can add custom preparation hooks with `config.to_prepare`:

```ruby
initializer :my_custom_preparation do |app|
  config.to_prepare do
    puts "Reloading now ..."
  end
end
```

When Rails detects a change, this block will be called. It's implemented by [registering the block with `app.reloader`](https://github.com/rails/rails/blob/ce97c79445f9ac4b056e34deaaaaf25cadc08b72/railties/lib/rails/application/finisher.rb#L53-L55).

## app.reloaders

To add _new conditions_ for which Rails should reload, you can add to the [`app.reloaders` array](https://github.com/rails/rails/blob/8f59a1dd878f56798f88369fa5b448f17a29679d/railties/lib/rails/application.rb#L126):

```ruby
# Object responds to `#updated?`
class MyWatcher
  def updated?
    # ...
  end
end

# ...

initializer :my_custom_watch_condition do |app|
  # Register custom reloader:
  app.reloaders << MyWatcher.new
end
```

The object's [`updated?` method will be called](https://github.com/rails/rails/blob/ce97c79445f9ac4b056e34deaaaaf25cadc08b72/railties/lib/rails/application/finisher.rb#L156-L158) by the reloader. If any reloader returns `true`, the middleware will run all `to_prepare` blocks (via the call to `@reloader.run!`).

## FileUpdateChecker

Rails includes a goodie for watching files. [`ActiveSupport::FileUpdateChecker`](http://api.rubyonrails.org/classes/ActiveSupport/FileUpdateChecker.html) is great for:

- Watching specific files for changes ([`config/routes.rb` is watched this way](https://github.com/rails/rails/blob/ce97c79445f9ac4b056e34deaaaaf25cadc08b72/railties/lib/rails/application/routes_reloader.rb#L41))
- Watching a directory of files for changes, additions and deletions ([`app/**/*.rb` is watched this way](https://github.com/rails/rails/blob/ce97c79445f9ac4b056e34deaaaaf25cadc08b72/railties/lib/rails/application/finisher.rb#L164))

You can create your own `FileUpdateChecker` and add it to `app.reloaders` to reload Rails when certain files change:

```ruby
# Watch specific files:
app.reloaders << ActiveSupport::FileUpdateChecker.new(["my_important_file.txt", "my_other_important_file.txt"])
# Watch directory-extension pairs, eg all `.txt` and `.md` files in `app/important_files` and subdirectories:
app.reloaders << ActiveSupport::FileUpdateChecker([], { "app/important_files" => [".txt", ".md"] })
```

Some filesystems support an evented file watcher implementation, [`ActiveSupport::EventedFileUpdateChecker`](http://api.rubyonrails.org/classes/ActiveSupport/EventedFileUpdateChecker.html). `app.config.file_watcher` will return the proper filewatcher class for the current context.

```ruby
app.reloaders << app.config.file_watcher(["my_important_file.txt", "my_other_important_file.txt"])
```

## All Together Now

`react-rails` maintains a pool of V8 instances for server rendering React components. These instances are initialized with a bunch of JavaScript code, and whenever a developer changes a JavaScript file, we need to reload them with the new code. This requires two steps:

- Adding a new watcher to `app.reloaders` to detect changes to JavaScript files
- Adding a `to_prepare` hook to reload the JS instances

It looks basically like this:

```ruby
initializer "react_rails.watch_js_files" do |app|
  # Watch for changes to javascript files:
  app.reloaders << app.config.file_watcher.new([], {
    # Watch the asset pipeline:
    Rails.root.join("app/assets/javascripts").to_s => ["jsx", "js"],
    # Watch webpacker:
    Rails.root.join("app/javascript").to_s => ["jsx", "js"]
  })

  config.to_prepare do
    React::ServerRendering.reset_pool
  end
end
```

The [full implementation](https://github.com/reactjs/react-rails/blob/bbb1ff10c787ca6a186e39df57fe5b228b37bd7e/lib/react/rails/railtie.rb#L26-L39) supports some customization. You can see similar (and more complicated) examples with [routes reloading](https://github.com/rails/rails/blob/ce97c79445f9ac4b056e34deaaaaf25cadc08b72/railties/lib/rails/application/finisher.rb#L126-L142), [i18n reloading](https://github.com/rails/rails/blob/e9abbb700acd8165a8994d8b2a700e507fb3b7ff/activesupport/lib/active_support/i18n_railtie.rb#L59-L74) and [`.rb` reloading](https://github.com/rails/rails/blob/ce97c79445f9ac4b056e34deaaaaf25cadc08b72/railties/lib/rails/application/finisher.rb#L163-L183).

Happy reloading!
