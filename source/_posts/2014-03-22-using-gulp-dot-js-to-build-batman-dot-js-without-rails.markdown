---
layout: post
title: "Using Gulp.js to build Batman.js apps without Rails"
date: 2014-03-22 10:39
comments: true
categories:
  - Gulp.js
  - Batman.js
  - JavaScript
  - CoffeeScript
---

If the [batman-rails gem](https://github.com/batmanjs/batman-rails) isn't an option, [gulp.js](http://gulpjs.com) is a good candidate for compiling batman.js apps for production.

<!-- more -->


To prepare your app for production, you need to:

- compile your CoffeeScript files into a JavaScript file
- preload your HTML into `Batman.View.store`.

These can both be accomplished with gulp.js tasks.

## Setup

Let's assume your batman.js project has the folder structure:

```
my_app/
├── batman/
|   ├── my_app.coffee
|   ├── models/
|   |   └── my_model.coffee
|   ├── controllers/
|   |   └── my_models_controller.cofee
|   ├── views/
|   |   └── my_models/
|   |       └── my_models_show_view.coffee
|   └── html/
|       └── my_models/
|           ├── show.jade
|           └── index.jade
├── javascripts/
|   └── batman.js
└── Gulpfile.js
```

Notice that the `html` folder actually contains `.jade` files. We'll use gulp.js to compile those, but you can skip that step if you're using plain HTML.

__Install gulp__ with `npm install -g gulp`. All gulp plugins required below must also be installed "by hand" with `npm install <gulp-plugin>`

## Compiling your application code

Here's a gulp.js task that takes the `batman/` directory above and compiles it to one Javascript file, `javascripts/application.js`:

```javascript Gulpfile.js
var gulp = require('gulp');
var coffee = require('gulp-coffee');
var concat = require('gulp-concat');

// include top-level .coffee files (`my_app.coffee`) first:
var appSources = ["./batman/*.coffee", "./batman/*/*.coffee"]

gulp.task("build", function(){
  gulp.src(appSources)
    .pipe(concat("application.coffee")) // so CoffeeScript will compile all together
    .pipe(coffee())
    .pipe(concat("application.js"))
    .pipe(gulp.dest("./javascripts/"))
})
```

Now, you can run:

```
gulp build
```

## Preloading your templates

Batman.js's fetch-html-as-needed approach is great for develoment, but not for production. Here's a task that will load files from the `html/` directory, convert them from jade to HTML, then inline them as JavaScript code that preloads the app with the HTML it needs.

```javascript Gulpfile.js
var gulp = require('gulp');
var concat = require('gulp-concat');
var jade = require('gulp-jade');
var batmanTemplates = require("gulp-batman-templates")

gulp.task("html", function(){
  gulp.src(["./batman/html/**/*.jade"])
    .pipe(jade())
    .pipe(batmanTemplates())
    .pipe(concat('templates.js'))
    .pipe(gulp.dest("./javascripts/"))
})
```

## Finishing Up

Let's join the to javascript files together:

```javascript Gulpfile.js
gulp.task("finalize", function() {
  gulp.src(["./javascripts/application.js", "./javascripts/templates.js"])
    .pipe(concat("application.js"))
    .pipe(gulp.dest("./javascripts/"))
});
```

And make our `default` gulp task to watch the project and build whenever it changes:

```javascript Gulpfile.js
gulp.task('default', function(){
  gulp.watch('./batman/**/*', ["build", "html", "finalize"])
});
```

So now, all we need to do is:

```
gulp
```

And in the layout:

```html
  <script src='/javascripts/batman.js'></script>
  <script src='/javascripts/application.js'></script>
```

Voila! Your app is compiled and HTML will be preloaded!

