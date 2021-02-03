---
layout: post
title: "Using Command-Line Tools for Backends on Google App Engine"
date: 2013-08-07 19:17
categories:
  - Google App Engine
---

It took me quite a while to realize that my [GAE](https://cloud.google.com/products/app-engine) [backend](https://developers.google.com/appengine/docs/python/backends/) wasn't working because I had to use [appcfg](https://developers.google.com/appengine/docs/python/gettingstartedpython27/uploading), not the [App Engine Launcher](https://developers.google.com/appengine/downloads) to deploy it. App Engine Launcher's "deploy" button wouldn't do it.

<!-- more -->

Looks like I wasn't the only one who took a while to figure it out:

> [Y]ou can't use the ... AppEngineLauncher to use backends. So if you want to use backends ... you will need to use the command-line version of the tools. Obviously this is a minor thing, but it took me quite a while to realize that was why backends were not working for me.


- [Brett Cannon, Coder Who Says Py, "Working with App Engine Backends"](http://sayspy.blogspot.com/2012/01/working-with-app-engine-backends.html)

(and this guy used to work for Google ... _on the App Engine team!_) Anyways, now I'm straightened out:

```

$ appcfg backends ./ update datacrawler

```
