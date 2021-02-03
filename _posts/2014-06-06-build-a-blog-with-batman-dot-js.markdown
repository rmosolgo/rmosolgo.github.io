---
layout: post
title: "Build a Blog with Batman.js"
date: 2014-06-06 08:38
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
  - Firebase
---

In this whirlwind tutorial, we'll build a blog with [batman.js](http://batmanjs.org) and [Firebase](http://firebase.com).

<!-- more -->

To get a feel for batman.js, let's build an blog where:

- People may sign in (with Github)
- The owner may create, edit and destroy posts
- Other signed-in users may leave comments and delete their own comments
- The owner may destroy comments

If you run into any problems on the way, just let me know in the comments section at the bottom of this page! Also, the [completed source of this tutorial is available on Github](https://github.com/rmosolgo/batmanjs-blog).

# Preface: Batman.js Objects and Properties

If you're brand new to batman.js, here's the quick-and-dirty:

`Batman.Object` is the superclass of (almost) all objects in batman.js. Properties of `Batman.Object`s are also called [__accessors__](http://batmanjs.org/docs/api/batman.object_accessors.html), becuase they're _always_ defined with `@accessor` in the class definition.


There are 2 possible syntaxes:

- __Read and write__ accessors:

```coffeescript
class App.Comment extends Batman.Model
  @accessor 'mood',
    get: (key)        -> # getter function
    set: (key, value) -> # setter function
```

- __Read-only__ accessors:

```coffeescript
  @accessor 'isPositive', (key) -> # getter function only
```

`@accessor` is your friend. Use `@accessor` whenever you can (it can often replace functions, too). Accessors are [automatically tracked](http://rmosolgo.github.io/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/) by batman.js, so view bindings and other accessors are automatically updated. You can defined accessors in your `Batman.Model`, `Batman.Controller` and `Batman.View` subclasses.

Accessors are _always_ __accessed via `get` and `set`__:

```coffeescript
myComment.set("mood", "pensive")
myComment.get("mood")
```

These property names are also called _keypaths_ and maybe be "deep", chained with `.`:

```coffeescript
myComment.get('post.name') # equivalent to myComment.get('post').get('name')
```

Under the hood, accessors power batman.js's [automatic source tracking](http://rmosolgo.github.io/blog/2014/04/20/automatic-source-tracking-in-batman-dot-js/) and view bindings. Now, back to your regularly scheduled programming!

# Setup

To build this blog, you'll need:

- A [Github account](http://github.com)
- [node.js](http://nodejs.org/)
- A [Firebase account](http://firebase.com)

Also, you'll need a copy of [rmosolgo/batmanjs-starter](http://github.com/rmosolgo/batmanjs-starter), which can be installed with:

```bash
cd ~/code # or wherever you keep it
git clone git@github.com:rmosolgo/batman-starter.git batmanjs_blog
cd batmanjs_blog
npm install
```

You can make sure it's all ready-to-go with:

```
npm install -g gulp
gulp
```

Then visit [localhost:9000](http://localhost:9000). If you see `Welcome to batman.js!`, then you're all set!

# Storage and Authentication

We don't have a server for this app, but we do have to set up Firebase!


### Set Up Firebase

First, open [Firebase](http://firebase.com) and click `Login` and click the Github logo. Then, create a new app. Any name will work, for example `rm-batmanjs-blog`. Ok, you have a firebase!

### Register Your App with Github

Then, in another tab, sign into [Github](http://github.com), and click: `Account Settings` (top right) > `Applications` (in the sidebar) > `Register New Application`. Add this information:

- Application name: firebase name (eg, `rm-batmanjs-blog`)
- Application URL: `http://#{firebase name}.firebaseapp.com` (eg, `http://rm-batmanjs-blog.firebaseapp.com`)
- Callback URL: `https://auth.firebase.com/auth/github/callback` ([provided by Firebase](https://www.firebase.com/docs/security/simple-login-github.html))

Click `Register Application`. Ok, you have your Client ID and Client Secret!

Now, provide the Client ID and Client Secret to Firebase. In your Firebase app manangement tab, click `Manage App` > `Simple Login` > `Github`:

- Check `Enabled`
- Paste in Client ID and Client Secret

(Firebase automatically saves your input.)

### Configure Your Batman.js App

Now, configure your app to use your firebase. Open `app.coffee`, then replace the `@syncsWithFirebase` name and add `@authorizesWithFirebase()`. For example, it should look like:

```coffeescript
  @syncsWithFirebase "rm-batmanjs-blog"
  @authorizesWithFirebase()
```

Also in `app.coffee`, make a app accessor `isAdmin`, looking up your github ID from `https://api.github.com/users/#{yourUserId}`:

```coffeescript
  @classAccessor 'isAdmin', -> @get('currentUser.uid') is "github:{yourGitHubId}"
```

To show the `Log In`/`Log Out` buttons, remove the `<!-- requires @authorizesWithFirebase` / `-->` comment wrapper in `index.html`.

Now, you will see the `Log In` button, and it will log you in with Github!

_At the end of this post, we'll use Firebase Security Rules to provide "server-side" authentication, which is a must-have!_

# Posts

To add posts to our blog, we will:

- define the `App.Post` model
- define `App.PostsController` and make routes to it
- write some HTML for the controller to render

## Post Model

In a batman.js project, models go in the `models/` directory. In the starter package, you'll find the `App.Greeting` model in `greeting.coffee`. Remove it. Then, add `post.coffee`. Here's the `Post` model:

```coffeescript
class App.Post extends Batman.Model
  @resourceName: 'post'
  @persist BatFire.Storage
  @encode 'title', 'content'

  @validate 'title', presence: true
  @validate 'content', minLength: 25
  @belongsToCurrentUser(ownership: true)
  @encodesTimestamps()

  @accessor 'createdAtFormatted', ->
    @get('created_at')?.toDateString()
```

Let's break that down:

### Class Definition

```coffeescript
class App.Post extends Batman.Model
```

In a batman.js app, all models are children of [`Batman.Model`](http://batmanjs.org/docs/api/batman.model.html). Since we're using CoffeeScript's `extend`, you can extend your own models, too -- the inheritance hierarchy will be maintained.

### Persistence

```coffeescript
  @resourceName: 'post'
  @persist BatFire.Storage
  @encode 'title', 'content'
```

These define how the model is persisted:

- `@resourceName` is a minification-safe model name. It may also define "where" to save the model (for example, a URL segment).
- `@persist` says which [`Batman.StorageAdapter`](http://batmanjs.org/docs/api/batman.storageadapter.html) will connect this model to a storage backend. We're using a Firebase adapter, but batman.js also ships with `Batman.LocalStorage` and `Batman.RestStorage`. `Batman.RailsStorage` is in the `batman.rails` extra.
- `@encode` tells batman.js which attributes will be persisted with the storage adapter.


### Validations

```coffeescript
  @validate 'title', presence: true
  @validate 'content', minLength: 25
```

Batman.js models may validate their attributes. See the docs for [all supported validators](http://batmanjs.org/docs/api/batman.model_validations.html) and the custom validation API.

### Special BatFire.Storage Functions

```coffeescript
  @belongsToCurrentUser(ownership: true)
  @encodesTimestamps()
```

These are provided by [`BatFire.Storage`](http://github.com/rmosolgo/batfire) as conveniences.

- `@belongsToCurrentUser(ownership: true)` adds `created_by_uid` to our model and provides client-side validation that only the creator may alter any persisted records
- `@encodesTimestamps()` defines and encodes `created_at` and `updated_at` attributues.


### Accessors

```coffeescript
  @accessor 'createdAtFormatted', ->
    @get('created_at')?.toDateString()
```

This shows how you can define properties on your models. Now, `post.get('createdAtFormatted')` will return a (slightly) prettier version of the `created_at` date string. Since it's a [`Batman.Object` accessor](http://batmanjs.org/docs/api/batman.object_accessors.html), if `created_at` somehow changed, `createdAtFormatted` would also be updated.

## PostsController

`Batman.Controller` is modeled after Rails controllers. It has actions that are invoked by routes and are responsible for rendering views. They belong in `controllers/`, so create `controllers/posts_controller.coffee`. Let's define a controller to render our posts:

```coffeescript
class App.PostsController extends App.ApplicationController
  routingKey: 'posts'
  index: ->
    @set 'posts', App.Post.get('all.sortedByDescending.created_at')

  new: ->
    @set 'post', new App.Post

  show: (params) ->
    App.Post.find params.id, (err, record) =>
      throw err if err?
      @set 'post', record

  edit: (params) ->
    App.Post.find params.id, (err, record) =>
      throw err if err?
      @set 'post', record.transaction()

  savePost: (post) ->
    post.save (err, record) =>
      if err
        if !(err instanceof Batman.ErrorsSet)
          throw err
      else
        @redirect(action: "index")

  destroyPost: (post) ->
    post.destroy (err, record) =>
      @redirect(action: "index")
```

Here, you can see:

- `App.PostsController extends App.ApplicationController`: all controllers extends a base controller. In big apps, `ApplicationController` is home to things like [error handling](http://batmanjs.org/docs/api/batman.controller.html#error_handling) and [dialog render helpers](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/controller#sec-render_into_modal).
- Controllers must have a `routingKey`. This is a [minification-safe name](http://batmanjs.org/docs/api/batman.controller.html#routingkey_and_minification) which is used by the router.
- Controllers have [__actions__](http://batmanjs.org/docs/api/batman.controller.html#actions) which fetch data and render views. In `PostsController`, the _actions_ are `index`, `new`, `show`, and `edit`.
- `savePost` and `destroyPost` will be invoked by user input (described in the HTML section, next)

Let's also add routes for this controller. In `app.coffee`, remove any `@root` or `@resources` declarations and add:

```coffeescript
  @root 'posts#index'
  @resources 'posts'
```

This sets up `/` to dispatch `PostsController`'s `index` action and sets up [resource-based routes](http://batmanjs.org/docs/api/batman.app_routing.html#class_function_resources) for `PostsController`.

There are a few other things to point out:

- We didn't call `@render` in any of our actions. This is because batman.js _automatically renders_ after any controller actions that didn't explicitly render. This is called the _implicit render_ and may be overriden, for example, if you want to [wait for data to load before rendering views](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/controller#sec-defer_render).
- _Actions_ and _event handlers_ are both functions on the controller. This is possible because the controller is in the binding context of the view (see "Render Context" in the [bindings guide](http://batmanjs.org/docs/bindings.html)).

Also, since we have routes, let's update the navbar `<ul>` in `index.html` to look like this:

```html
<ul class="nav navbar-nav">
  <li><a data-route='routes.posts'>Blog Posts</a></li>
  <li data-showif='isAdmin'><a data-route='routes.posts.new'>New Post</a></li>
</ul>
```

(More about those `data-` attributes to follow...)

## Posts HTML

We need HTML to be rendered in by our controller. _HTML templates_ are distinct from _views_, but may be used together. This is described in detail below. For now, let's add some HTML. In a batman.js project, HTML for a controller action belongs in `html/#{routingKey}/#{action}.html`.

### show.html

Let's define `html/posts/show.html`. It will be loaded by `posts#show` to display a post instance:

```html
<div class='row'>
  <div class='col-sm-12'>
    <h1 class='page-header'>
      <span data-bind='post.title'></span>
      <small data-bind='post.createdAtFormatted'></small>
    </h1>
  </div>
</div>

<div class='row'>
  <p class='col-sm-12' data-bind='post.content'></p>
</div>
```

Besides the [bootstrap boilerplate](http://getbootstrap.com), you might notice `data-bind` on some of these HTML tags. `data-*` attributes is how batman.js binds data to the DOM. Those attributes are called __[data bindings](http://batmanjs.org/docs/bindings.html)__.

The [`data-bind` binding](http://batmanjs.org/docs/api/batman.view_bindings.html#data-bind) is the simplest data binding: it simply connects the node to the property which is passed to it.

When combining data and text, it's common to use `<span data-bind="..."></span>`, as in the `<h1/>` above.

### index.html

Let's define `html/posts/index.html`:

```html
<div class='row'>
  <h1 class='col-sm-12'>
    <span data-bind='"Post" | pluralize posts.length'></span>
  </h1>
</div>
<ul class='list-unstyled'>
  <li data-foreach-post='posts'>
    <div class='row'>
      <a data-route='routes.posts[post]'>
        <p class='lead col-sm-4' data-bind='post.title'></p>
      </a>
      <div class='col-sm-2'>
        <a data-showif='post.isOwnedByCurrentUser' class='btn btn-warning pull-right' data-route='routes.posts[post].edit'>Edit</a>
      </div>
      <div class='col-sm-2'>
        <a data-showif='post.isOwnedByCurrentUser' class='btn btn-danger pull-right' data-event-click='destroyPost | withArguments post'>Delete</a>
      </div>
      <span class='text-muted col-sm-4'>
        Posted on
        <span data-bind="post.createdAtFormatted"></span>
      </span>
    </div>
    <div class='row'>
      <p class='col-sm-12' data-bind='post.content | truncate 100'></p>
    </div>
  </li>
</ul>
<div class='row' data-showif='isAdmin'>
  <div class='col-sm-2'>
    <a class='btn btn-default' data-route='routes.posts.new'>New Post</a>
  </div>
</div>
```

Let's look at some interesting parts:

#### View Filters

```html
<span data-bind='"Post" | pluralize posts.length'></span>
```

This will output things like `3 Posts`. It takes a plain string, then passes it to the <a href="http://batmanjs.org/docs/api/batman.view_filters.html#pluralize(value%2C_count)_%3A_string">pluralize view filter</a>, with `posts.length` as an argument. Since it's bound to `posts.length`, it will automatically update whenever the number of `Post`s change.

There are quite a lot of batman.js view filters, be sure to [check out the documentation](http://batmanjs.org/docs/api/batman.view_filters.html).

#### Iterator Binding

```html
<ul class='list-unstyled'>
  <li data-foreach-post='posts'>
    <!-- ... -->
  </li>
</ul>
```

The [`data-foreach-#{item}="collection"` binding](http://batmanjs.org/docs/api/batman.view_bindings.html#data-foreach) is how you bind to a collection. The `<li />` is called the "prototype node", and one will be rendered for each item in the collection. As long as `"collection"` is a batman.js data structure (ie, not a plain JS array), the binding will be automatically updated when items are added and removed. (Unless you explicitly make arrays yourself, you don't have to worry; batman.js always uses observable data structures like [Batman.Set](http://batmanjs.org/docs/api/batman.set.html) and [Batman.Hash](http://batmanjs.org/docs/api/batman.hash.html).)

#### Named Routes

```html
<a data-route='routes.posts[post]'>
  <!-- ... -->
</a>
```

The [`data-route` binding](http://batmanjs.org/docs/api/batman.view_bindings.html#data-route) is how you link to other routes in your app. The "route query" passed to the binding is based on your declared routes. Here are a few other valid routes:

```
data-route="routes.posts"               # => goes to `posts#index`
data-route="routes.posts.new"           # => goes to `posts#new`
data-route="routes.posts[myPost]"       # => goes to `posts#show` for a post instance `myPost`
data-route="routes.posts[myPost].edit"  # => goes to `posts#edit` for a post instance `myPost`
```

In the binding above, `post` refers to a post instance, so the `<a/>` will point to that post's `show` page.

#### Showif / Event

```html
<a data-showif='post.isOwnedByCurrentUser' class='btn btn-danger pull-right' data-event-click='destroyPost | withArguments post'>Delete</a>
```

This has two bindings:

- `data-showif` shows the node if the keypath returns truthy. `isOwnedByCurrentUser` is provided by `BatFire.Storage`.
- `data-event-click` points to a function to call when the node is clicked, in this case `AppPostsController::destroyPost`, which we defined above

### new.html

For `new.html`, let's plan ahead: we'll make `new.html` include a reusable form, `form.html`. So, `new.html` is very simple:

```html
<div class='row'>
  <h1 class='col-sm-12'>
    New Post
  </h1>
</div>

<div data-partial='posts/form'></div>
```

#### Partial

```html
<div data-partial='posts/form'></div>
```
This will render `html/posts/form.html` inside that node.

Let's add `form.html`:

```html
<form data-formfor-post='post' data-event-submit='savePost | withArguments post'>
  <div class='errors alert alert-warning' data-showif='post.errors.length'>
  </div>
  <div class='form-group'>
    <label>Title</label>
    <input type='text' class='form-control' data-bind='post.title' />
  </div>
  <div class='form-group'>
    <label>Content</label>
    <textarea class='form-control' data-bind='post.content'></textarea>
  </div>
  <div class='form-group'>
    <input type='submit' class='btn btn-primary' value='Save' />
    <a class='btn btn-danger' data-route='routes.posts'>Cancel</a>
  </div>
</form>
```

Let's examine some of the details:

#### Form Binding

```
<form data-formfor-post='post' data-event-submit='savePost | withArguments post'>
  <!-- ... -->
</form>
```

The [`data-formfor-#{formName}="item"` binding](http://batmanjs.org/docs/api/batman.view_bindings.html#data-formfor) will automatically bind validation errors to the element matching `.errors`:

```
  <div class='errors alert alert-warning' data-showif='post.errors.length'>
```

Also, the `data-event-submit` will invoke `App.PostsController::savePost` when the form is submitted.

#### Input Bindings

```
<input type='text' class='form-control' data-bind='post.title' />
```

When you use `data-bind` on an `<input />` (or `<select />`, etc), you create a two-way binding. Any changes to the input will change the attribute of the model.
You can [bind to all different kinds of inputs](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/html#sec-input_bindings).

### edit.html

In `edit.html`, let's reuse our `form.html` partial:

```html
<div class='row'>
  <h1 class='col-sm-12'>
    Edit Post
  </h1>
</div>
<div data-partial='posts/form'>
</div>
```

## Where were the views?

In batman.js, _views_ are CoffeeScript classes that render templates and maintain bindings. They're intantiated and destroyed when controller actions are rendered. It's a bit like this:

```

ROUTER                      -->  CONTROLLER        -->  VIEW                      -->  HTML TEMPLATE
- responds to URL change         - executes action      - parses bindings from HTML    - copied into views
- dispatches controller action   - renders view         - inserts HTML into DOM        - just sits there
                                                        - maintains bindings

```
You might have noticed that we made a _controller_ and a _template_, but no `Batman.View`. Why not?

This is because `Batman.Controller` will use a vanilla `Batman.View` to render your HTML unless you define one by hand. Custom views a great for a ton of things:

- Rendering [specialized UI components](http://rmosolgo.github.io/blog/2013/11/23/dynamic-navigation-view-with-batman-dot-js/)
- Integrating other librarires, like [jQuery plugins](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/view#sec-jquery_initialization) or [leaflet.js](http://rmosolgo.github.io/blog/2014/04/30/integrate-batman-dot-js-and-leaflet-with-a-custom-view/)
- [Animating page changes](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/view#sec-view_transitions)

But we didn't need one, so we didn't make one!

(PS: Learn more about [controllers' default views](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/controller#sec-default_views) or [custom views](http://batmanjs.org/docs/views.html).)

# Comments

Let's allow other signed-in users to comment on our blog posts. We'll need to:

- define the model, `App.Comment`
- associate it to `App.Post`
- add a comment form to `posts/show`

## App.Comment

Open up `models/comment.coffee` and define `App.Comment`:

```coffeescript
class App.Comment extends Batman.Model
  @resourceName: 'comment'
  @persist BatFire.Storage
  @encode 'content'
  @belongsTo 'post'
  @validate 'content', presence: true
  @belongsToCurrentUser()
  @encodesTimestamps()

  @accessor 'createdAtFormatted', ->
    @get('created_at')?.toDateString()

  @accessor 'canBeDeleted', ->
    @get('isOwnedByCurrentUser') || App.get('isAdmin')
```

Most of this looks familiar: persistence, encoding, validations, accessors. There is one new thing:

### Model Association

```
@belongsTo 'post'
```

This defines a [model association](http://batmanjs.org/docs/api/batman.model_associations.html) between `Comment` and `Post`. In this case, we defined a `belongsTo` association, so:

- A `Comment` has a `post` attribute:

```coffeescript
  myComment.get('post') # => <Post instance>
```

- A `Comment` will encode `post_id`, which is the `id` of its associated `Post`.

We also need to add this concern to our `Post`-related code. Open `models/post.coffee`, and after your `@encode` call, add:

```coffeescript
class App.Post extends Batman.Model
  # ...
  @hasMany 'comments', inverseOf: 'post'`
```

We have defined a `hasMany` relation from Post to Comment. So, a Post has a `comments` attribute, which returns a `Batman.Set` full of Comments:

```coffeescript
myPost.get('comments') # => <Batman.Set [Comment, Comment...]>
```

Since `Post` and `Comment` are associated, we have to make sure that a `Post`'s `Comment`s are destroyed when the `Post` is destroyed. So, update `App.PostsController::destroyPost`:

```coffeescript
  destroyPost: (post) ->
    post.get('comments').forEach (c) -> c.destroy()
    post.destroy (err, record) =>
      @redirect(action: "index")
```

Now, whenever you destroy a `Post`, you'll also destroy its comments, so you don't end up with orphaned comments. We used `Batman.Set::forEach` -- see [this blog post](http://rmosolgo.github.io/blog/2014/04/30/getting-to-know-batman-dot-set/) for an introduction to `Batman.Set`!

## Comment Form

Let's add comment form to `posts/show` so that users can log in. Append each of these blocks of HTML to the bottom of `html/posts/show.html`.


### Heading

```html
<div class='row'>
  <div class='col-sm-12'>
    <h3> Comments </h3>
  </div>
</div>
```

Nothing to see here, move along ...

### List of Comments

This will render existing comments for a post:

```html
<div class='row'>
  <ul class='list-unstyled'>
    <!-- render comments: -->
    <li data-foreach-comment='post.comments' >
      <p class='col-sm-4'>
        <strong class='pull-right'>
          On <span data-bind='comment.createdAtFormatted'></span>, <span data-bind='comment.created_by_username'></span> said:
        </strong>
      </p>
      <p class='col-sm-6' data-bind='comment.content'></p>
      <div class='col-sm-2' data-showif='comment.canBeDeleted'>
        <a class='btn btn-danger btn-xs' data-event-click='destroyComment | withArguments comment'> Delete </a>
      </div>
    </li>
    <!-- "design" for empty state -->
    <li class='col-sm-12' data-showif='post.comments.isEmpty'>
      <p class='text-muted'>No comments yet!</p>
    </li>
  </ul>
</div>
```

A few things of note:

- There's a `data-foreach` binding with a `<li/>` prototype node. I included another `<li/>` with `data-showif='post.comments.isEmpty'`, just in case there aren't any comments yet.
- `data-showif='comment.canBeDeleted'` is using the accessor we defined in the model definition.
- We're using `data-event-click='destroyComment | withArguments comment'` but we haven't defined `destroyComment` yet. We'll do that next!

### Comment Form

Notice that there are actually two parts of the HTML: one to show if `loggedOut`, the other to show if `loggedIn`:

```html
<div class='row' data-showif='loggedOut'>
  <div class='col-sm-12'>
    <div class='well'>
      <p>You must be <a data-event-click='login'>logged in</a> to leave a comment!</p>
    </div>
  </div>
</div>

<div class='row' data-showif='loggedIn'>
  <div class='col-sm-12'>
    <form data-formfor-comment='newComment' data-event-submit='saveComment | withArguments newComment'>
      <div class='form-group'>
        <label>New Comment:</label>
        <textarea
          class='form-control'
          data-bind='newComment.content'
          data-bind-placeholder='"Leave a comment as " | append currentUser.username | append "..."'
          >
        </textarea>
      </div>
      <input type='submit' class='btn btn-primary' value='Leave a comment' />
    </form>
  </div>
</div>
```

#### Conditionals in HTML

```html
<div data-showif='loggedOut'>
  <!-- show this to logged-out users -->
</div>
<div data-showif='loggedIn'>
  <!-- show this to logged-in users -->
</div>
```

Using multiple `data-showif`/`data-hideif` bindings is a common way of expressing conditional logic in batman.js templates.


#### Binding to Attributes

```html
<textarea data-bind-placeholder='"Leave a comment as " | append currentUser.username | append "..."' ></textarea>
```

Here, we have bound data to the `<textarea />`'s `placeholder` attribute. You can use `data-bind-#{attr}` to bind to any HTML attribute.

## Use a Custom View

[Views](http://batmanjs.org/docs/views.html) inject new accessors and functions into the render context. They also have [lifecycle hooks](http://batmanjs.org/docs/api/batman.view_lifecycle.html) that can be used for initialization, etc.

To handle some actions with the comment form, we'll [implement the default view](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/controller#sec-default_views) for the `posts#show` action. Open `views/posts/posts_show_view.coffee` and add:

```coffeescript
class App.PostsShowView extends Batman.View
  viewWillAppear: ->
    @_resetComment()

  saveComment: (comment) ->
    # set up the association:
    comment.set 'post', @get('controller.post')
    comment.save (err, record) =>
      throw err if err?
      @_resetComment()

  _resetComment: ->
    @set('newComment', new App.Comment)

  destroyComment: (comment) ->
    comment.destroy (err, r) ->
      throw err if err?
```

Because our view is named `App.PostsShowView`, it will automatically be used by the `posts#new` controller action. It's called the "default view" of `posts#show`.

Notably:

- `data-event` handlers may be on controllers _or_ views; both of them are in the "render context".
- we used a lifecycle hook, `viewWillAppear`, to initialize our empty form.
- we set the comment's `post` during `saveComment` because it might not have loaded yet when the view is rendered. You can also avoid this problem by [waiting until data is loaded to render the view](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook/controller#sec-defer_render).


# Firebase Security Rules

You __always__ need server-side validation to accompany client-side validations. Otherwise, a mean-spirited user could wreck your data from the JS console.

It's beyond the scope of this post to explain [Firebase security rules](https://www.firebase.com/docs/security/security-rules.html), but here are some to go with this app (be sure to insert your Github ID instead of mine!) :

```javascript
/* These rules are provided for imformational purposes only :) */
{
  "rules": {
    /* All items are namespaced by `BatFire` */
    "BatFire" : {
      /* Make `@syncs` accessors read-only */
      "syncs" : {
        ".read" : true,
        ".write" : false
      },
      /* All records namespaced by `records` */
      "records" : {
        "scoped" : {
          /* "Server-side" validation for @belongsToCurrentUser(scoped: true) */
          "$uid" : {
            ".write" : "$uid == auth.uid",
            ".read" : "$uid == auth.uid"
          }
        },
        "posts" : {
          ".read" : true,
          ".write" : "'github:2231765' == auth.uid " /* that's me */
        },
        "comments" : {
          ".read" : true,
          "$recordId" : {
            /* can be deleted by creator or by admin ... me */
            ".write" :  "!data.exists() || auth.uid == data.child('created_by_uid').val() || 'github:2231765' == auth.uid"
          }
        },
        "$resourceName" : {
          /* "Server-side" validation for @belongsToCurrentUser(ownership: true) */
          "$recordId" : {
            /* Allows non-belongsToCurrentUser records to be written but protect owned ones */
            ".write" : "!data.hasChild('has_user_ownership') || data.child('created_by_uid').val() == auth.uid"
          },
          ".read" : true
          /* nothing gets written here -- everything gets an ID _before_ create */
        }
      }
    },
    /* Everything else is fair game */
    "$other" : {
      ".read" : true,
      ".write" : true
    }
  }
}
```

# Wrap Up

Congratulations, you have a beautiful new blog! You can let the whole world see it by deploying it to Firebase:

- update `firebase.json` to have your Firebase name (eg, `"rm-batmanjs-blog"`)
- `npm install -g firebase-tools`
- `firebase deploy`
- `firebase open`

And you're live!

I hope you have enjoyed this tour of batman.js! For more information:

- check out the [batman.js website](http://batmanjs.org) or the [Batman.js MVC Cookbook](https://www.softcover.io/read/b5c051f3/batmanjs_mvc_cookbook)
- join the [mailing list](https://groups.google.com/forum/#!forum/batmanjs)
- drop by the IRC channel (#batmanjs)
- leave a comment here or open an issue on the [github repo](http://github.com/batmanjs/batman)
