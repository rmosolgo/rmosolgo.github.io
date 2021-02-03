---
layout: post
title: "Why (I Think) We're Leaving Batman.js"
date: 2014-09-07 20:19
categories:
  - Batman.js
  - React.js
---

Sadly, [PCO](http://get.planningcenteronline.com) is getting out of the batman.js game.

<!-- more -->

From where I sit, I think it boils down to:

- The framework never hit critical mass (and lost what it had)
- The framework's magic made some problems impossible to debug
- Client-side apps aren't good for business
- Rails, Turbolinks & React will do just fine

Batman.js is a great framework with some amazing, well-tested features and I'm sorry to see it go this way for us!

## No Critical Mass

Batman.js was an early entrant to the "Framework Wars". It was production-ready by early 2013, which made it appealing at that point. However,

- there was very little "evangelism" by its creators (almost no talks, very little documentation, no "media presence")
- early adopters were not "invited in" (unanswered github issues, for example)

When Shopify pulled out (around [fall 2013](https://github.com/batmanjs/batman/graphs/contributors)?), a ton of knowledge and resources were removed with no viable replacement.

## Magic Problems

Batman.js is loaded with awesome APIs that were fun to use and satisfying when they worked. However, when it _didn't work_, you were up a creek without a paddle. There was:

- no helpful error messages
- no support on github, stack overflow or IRC
- no documentation or information of any kind about the inner workings
- no debugging tools

I've seen a lot of batman.js users pull their hair out yelling, "Why doesn't this _work_?!" Indeed, that's what drove me to learn it from the source.

## Client-Side Issues

Making a whole app in JavaScript has a lot of sex appeal, but several things make it bad for real-life business:

- Bug-tracking tools (namely Bugsnag for JS) are not as good (especially when you throw CoffeeScript & minification in the mix)
- Browser environments are outside your control (I got a lot of bugsnags for peoples' browser extensions)
- State can get weird -- after having the app open for an hour, data can just get messed up! (Maybe this doesn't happen for better programmers.)

_Not my problem:_

<p><img src="/assets/images/extension_errors.png" width="500" /></p>

_No es mi problema:_

<p><img src="/assets/images/extension_errors2.png" width="900" /></p>

You just don't realize the luxury of reliable bugsnags until they're gone! So many Check-Ins bugsnags leave no trace of what actually went wrong.

## Other Options are OK, too

We have a solid data model, HTML templates and CSS to boot. It stinks to throw away all that code, but I forgot how amazingly fast it is to code Ruby on Rails.

JS MVC types will look down their noses at Turbolinks, but it _works_ and it has a lot of eyes on it. Combined with `react-rails`, it's a really strong option!

## What Now?

In short, Rails-rendered HTML, Turbolinks & `form_for ... remote: true`, and ReactJS for live-updates. There are a few things I am looking forward to:

- __RUBY BUGSNAGS__ with stack traces, request environments and everything!
- __Less state.__ Fewer things that can randomly affect other things in ways I didn't think about.
- __ReactJS.__ `Batman.View` is an amazing thing, but it makes me appreciate the dead-simple API of a React component. It can only get data from one place, no other objects can mess with it, its lifecycle is _very_ simple (and works as documented), etc etc. I write a lot more code to do a lot less with React, but I think it's going to be a lot more stable, and that's worth it.

We held on to Batman.js for a long time because it lended itself to _live-updating everything_. I think React is going to cover the a few key things there, and just _changing pages_ will do the rest. So far I've hooked up Pusher to Flux-style stores, then wrapped anything live-updating in a React component that observes that store. It's a lot more hands-on than Batman.js updates, but it has other advantages.
