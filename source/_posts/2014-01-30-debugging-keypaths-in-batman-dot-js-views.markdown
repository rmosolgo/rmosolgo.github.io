---
layout: post
title: "Debugging keypaths in batman.js views"
date: 2014-01-30 09:23
comments: true
categories:
  - Batman.js
  - JavaScript
  - CoffeeScript
---

Debugging can be tedious, especially when `cntl-R` is your only resort for trying new options. Instead, use batman.js's `$context` function to access the context of a specific node.

<!-- more -->

As I'm working with batman.js views, I use this technique for debugging in the browser: In Chrome, you can right-click, "Inspect element", which makes the highlighted node available as `$0` in the console. Then, pass `$0` to `$context` (which is a secret function created by batman.js) and it will return the batman.js view context for that node.

For example:

```javascript
// right-click an element, select "Inspect Element"
ctx = $context($0)           // => the view where $0 was rendered
ctx.get('node')              // => DOM node for the view
ctx.get('superview')         // => superview for this view (helpful for iteration/iterator views)
ctx.get('controller')        // => controller that rendered the view
ctx.get('controller.posts')  // => values set on the controller
```

Now, isn't that better!
