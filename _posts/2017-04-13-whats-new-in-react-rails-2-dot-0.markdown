---
layout: post
title: "What's new in React-Rails 2.0?"
date: 2017-04-13 11:59
categories:
- Ruby
- Rails
- React.js
---

For [Planning Center](http://planning.center) free week, I cooked up [`react-rails`](https://github.com/reactjs/react-rails) 2.0 🎊.

<!-- more -->

Here are a few highlights. For the full list, see the [changelog](https://github.com/reactjs/react-rails/blob/master/CHANGELOG.md)!

## Webpacker support

[Webpacker](https://github.com/rails/webpacker) was great to work with. `react-rails` now supports webpacker for:

- Mounting components with `<%= react_component(...) %>` via `require`
- Server rendering from a webpacker pack (`server_rendering.js`)
- Loading the unobtrusive JavaScript (UJS)
- Installation and component generators

A nice advantage of using webpacker is that you can load React.js from NPM instead of the `react-rails` gem. This way, you aren't bound to the React.js version which is included with the Ruby gem. You can pick any version you want!

## UJS on npm

To support frontends built with Node.js, `react-rails`'s  UJS driver is available on NPM as [`react_ujs`](https://www.npmjs.com/package/react_ujs). It performs setup during `require`, so these two are equal:

```js
// Sprockets:
//= require react_ujs

// Node, etc:
require("react_ujs")
```

## Request-based prerender context

If you're prerendering your React components on the server, you can perform setup and teardown in your Rails controller. For example, you might use these hooks to populate a flux store.

First, add the `per_request_react_rails_prerenderer` helper to your controller:

```ruby
class PagesController < ApplicationController
  per_request_react_rails_prerenderer
  # ...
end
```

Then, you can access `react_rails_prerenderer` in the controller action:

```ruby
def show
  js_context = react_rails_prerenderer.context
  js_context.exec(js_setup_code)
  render :show
  js_context.exec(js_teardown_code)
end
```

That way, you can properly prepare & clean up a JS VM for server rendering.

## Re-detect events

Previously, `ReactRailsUJS` "automatically" detected which libraries you were using and hooked up to their events for rendering components.

It still checks for libraries during its initial load, but you can _also_ re-check as needed:

```js
// Check the global context for libraries like Turbolinks and hook up to them:
ReactRailsUJS.detectEvents()
```

This function removes previous event handlers, so it's safe to call anytime. (This was added in `2.0.2`.)

## Other Takeaways

See the [changelog](https://github.com/reactjs/react-rails/blob/master/CHANGELOG.md) for bug fixes and a new default server rendering configuration.

Webpacker is great! Setup was smooth and the APIs were clear and convenient. I'm looking forward to using it more.

🍻 Here's to another major version of `react-rails`!
