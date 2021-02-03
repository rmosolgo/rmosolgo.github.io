---
layout: post
title: "Is Batman.js Just for Ruby on Rails?"
date: 2014-04-15 22:39
categories:
  - Batman.js
---

You can use [batman.js](http://batmanjs.org) with any backend!

<!-- more -->

Batman.js is _not_ just for Ruby on Rails! Here are batman.js's dependencies:

- A RESTful JSON API
- A way to compile the CoffeeScript app (may I recommend [gulp.js](/blog/2014/03/22/using-gulp-dot-js-to-build-batman-dot-js-without-rails/)?)
- A way to provide HTML templates (again, gulp.js worked nicely for me!)

As long as you can meet those requirements, you can use batman.js with any backend: Node, Ruby, Python, Java, Go, Rust, Erlang, PHP ... you get the drift.

## Why Is Batman.js Associated with Rails?

A few reasons:

- A lot of batman.js's syntax and features are designed with Rails in mind
- Batman.js was extracted from Shopify, which is a Ruby on Rails application
- Rails meets all of the above requirements out of the box

Also, there are a few batman.js goodies for Rails devs: the `batman.rails` CoffeeScript extra and the `batman-rails` Ruby gem.
