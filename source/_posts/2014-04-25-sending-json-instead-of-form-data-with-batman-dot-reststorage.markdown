---
layout: post
title: "Sending JSON Instead of Form Data with Batman.RestStorage"
date: 2014-04-25 13:02
comments: true
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
---

By default, `Batman.Request` sends data as HTTP form data. However, you can override this with `Batman.RestStorage`.

<!-- more -->


Simply pass `serializeAsForm: false` to `@persist` in your model definition:

```coffeescript
class MyApp.Model extends Batman.Model
  @persist Batman.RestStorage, serializeAsForm: false
```

Now, it will work with any JSON endpoint!

In my case, I was trying out batman.js and Martini, and I was surprised to find that RestStorage sends form data. I guess you never notice with Rails, since it puts everything into the `params` hash.