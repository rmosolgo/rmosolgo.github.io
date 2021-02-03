---
layout: post
title: "Parameterized styles with React, Rails and Sprockets"
date: 2016-10-18 15:05
categories:
- Rails
- React.js
- CSS
---

[`css_modules`](https://github.com/rmosolgo/css_modules) provides an approach to styling UI components in a local-first way.

<!-- more -->

Let's say you have the same component to render in two contexts:

```html
<div className="resources">
  <DetailPane />
</div>
// later ...
<div className="rooms">
  <DetailPane />
</div>
```

To style `DetailPane`, you probably want:

- A set of shared styles to apply by default
- A way to customize styles for each context

How can we accomplish that? The [`css_modules`](https://github.com/rmosolgo/css_modules) gem provides a solution.

(This example uses React components, but see below for a brief analogy to Rails partials.)

## CSS Modules

Let's treat each context as a module in CSS:

```scss
// in views/resources.scss
:module(resources) {
  // ...
}

// in views/rooms.scss
:module(rooms) {
  // ...
}
```

Since each context has a `DetailPane`, let's define a mixin and share it between the two:

```scss
// in shared/detail_pane.scss
@mixin detail-pane {
  .detail-pane {
    margin: 5px;
    border-radius: 5px;
    border: 1px solid #777;

    .description {
      font-size: 1.2rem;
    }
  }
}

// in views/resources.css
:module(resources) {
  @include detail-pane;
}

// in views/rooms.css
:module(rooms) {
  @include detail-pane;
}
```

### Why a mixin?

Using a mixin makes it easier to track usage within the application: you only need to search for `@include`s, rather than class names.

It also enforces a clear separation from base styles and custom styles. Base styles are hard-coded in the mixins. Custom styles are implemented as _overrides_ within the module or as _parameters_ to the mixin (using `$`-variables).

### Applying Styles

To apply the modulized styles to a component, provide the component with a CSS module prop:

```js
var resourcesModule = CSSModules("resources")
<div className="resources">
  <DetailPane cssModule={resourcesModule}/>
</div>

// later ...

var roomsModule = CSSModules("rooms")
<div className="rooms">
  <DetailPane cssModule={roomsModule}/>
</div>
```

Then, update `DetailPane` so that it gets class names from `this.props.cssModule`:

```js
var DetailPane = React.createClass({
  propTypes: {
    cssModule: React.PropTypes.func.isRequired,
  },

  render: function() {
    var cssModule = this.props.cssModule
    return (
      <div className={cssModule("detail-pane")}>
        <p className={cssModule("description")} />
      </div>
    )
  },
})
```

Now, the two instances of `DetailPane` will _not_ share class names, but they will share common code from `@mixin detail-pane`.

The rendered output will contain "modulized" class names. The module is translated into an opaque prefix on the class name:

```html
<div class="resources_abc123_detail-pane">
  <p class="resources_abc123_description"></p>
</div>
<div class="rooms_xyz987_detail-pane">
  <p class="rooms_xyz987_description"></p>
</div>
```

### Customizing Styles

You can customize the styles with _overrides_ or _parameters_.

Apply overrides by "reopening" class names inside the module:

```scss
:module(resources) {
  @include detail-pane;
  .detail-pane {
    // needs extra space here:
    margin: 10px;
  }
}
```

This will _only_ affect `.detail-pane` within the `resources` module.

Alternatively, you can parameterize the mixin. Add a `$`-parameter to the mixin:

```scss
// in shared/detail_pane.scss
@mixin detail-pane($margin) {
  .detail-pane {
    margin: $margin;
  }
}
```

Then provide a value when including that mixin:

```scss
// in views/resources.scss
:module(resources) {
  @include detail-pane(10px);
  // .detail-pane will have 10px margin
}

// in views/rooms.scss
:module(rooms) {
  @include detail-pane(5px);
  // .detail-pane will have 5px margin
}
```

Sass also includes [default values and optional arguments](http://advancedsass.com/articles/default-mixin-arguments-for-easier-theming.html).

## Bare class names?

Perhaps you need to support bare class names (no module). For example, if you extra `@mixin detail-pane` but your app still contains bare  `.detail-pane` class names, you might apply the mixin to the global scope:

```scss
@mixin detail-pane {
  // ...
}

// Also style global .detail-pane
@include detail-pane;
```

To use bare class names in your `<DetailPane />` component, use a _null module_:

```js
// This module has no name, it renders bare selectors:
var nullModule = CSSModules(null)
nullModule("detail-pane")
// "detail-pane"
```

You can pass that in for the `cssModule` prop:

```html
<DetailPane cssModule={CSSModules(null)} />
```

Then, the rendered output will contain bare class names:

```html
<div class="detail-pane">
  <p class="description"></p>
</div>
```

## Use with Rails Partials

You can also parameterize the class names in Rails partials.

Get a module with the view helper, then pass it to a partial:

```erb
<% resources_module = css_module("resources") %>
<%= render partial: "detail_pane", locals: { style_module: resources_module } %>
<!-- later -->
<% rooms_module = css_module("rooms") %>
<%= render partial: "detail_pane", locals: { style_module: rooms_module } %>
```
s that w
Then, use the `style_module` in the partial:

```erb
<div class="<%= style_module.selector("detail-pane") %>">
  <p class="<%= style_module.selector("description") %>"></p>
</div>
```

Rails can also generate a null module by providing `nil` as the module name:

```ruby
null_style_module = css_module(nil)
null_style_module.selector("detail-pane")
# => "detail-pane"
```

This allows you to parameterize the class names in your partials.
