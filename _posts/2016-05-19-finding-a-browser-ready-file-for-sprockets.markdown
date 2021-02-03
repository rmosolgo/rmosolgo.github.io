---
layout: post
title: "Finding a Browser-Ready File for Sprockets"
date: 2016-05-19 22:00
categories:
- Sprockets
- JavaScript
- Rails
---

I like using Sprockets, but sometimes it's hard to find a file to include in the asset pipeline. Here are some methods I use to find browser-ready JavaScript files.

<!-- more -->

There are a few good options for getting browser-ready files for JavaScript libraries:

- Download a file from the project's website
- Download a file from the project's source code repository
- Download a file from a CDN (npmcdn is great for cases where files are only "compiled" for releases)
- Build the file yourself, following the project's documentation

__Don't__ get a minified version. Sprockets will minify it for us later. In the meantime, the unminified version will help us during development.

### From a Website

This is the good ol' way of getting JavaScript files. Because we still use browsers, you can still download these files.

Here are some examples:

<p><img src="/assets/images/sprockets/website_download_d3.png" width="300" /></p>

<p><img src="/assets/images/sprockets/website_download_react.png" width="500" /></p>

<p><img src="/assets/images/sprockets/website_download_moment.png" width="300" /></p>

### From the Repo

Many projects maintain a browser build in the project's source. You may have to poke around a bit, but likely places are the project's root folder, the `dist/` folder, or the `build/` folder.

As you explore the repo, remember to examine a stable ref, such as a release or a stable branch.

Here are some examples:

<p><img src="/assets/images/sprockets/repo_download_c3.png" width="300" /></p>

<p><img src="/assets/images/sprockets/repo_download_immutable.png" width="300" /></p>

<p><img src="/assets/images/sprockets/repo_download_three.png" width="300" /></p>


### From a CDN


[CDNJS](https://cdnjs.com/libraries) hosts browser-ready files for many libraries.

Sometimes, an author only compiles browser-ready files for releases to NPM. You can get these files from [npmcdn](https://npmcdn.com/).

Since npmcdn is serving NodeJS projects, employ a similar technique to searching the project repo for a file:

- Check the "main" file
- Check the "dist" or "build" directories

### Build it from Source

If a pre-built, browser-ready file is not available, you may have to build it yourself! The project's readme will contain instructions to do so. If it doesn't ... you may want to reconsider adding this dependency! (Even if it's well-maintained, it's not a good match for this asset bundling approach.)

## Summary

Hopefully these will work well for you!

You may have to learn a bit of RequireJS, jspm, Grunt, Browserify, Gulp, Webpack or Rollup along the way. (Ok, probably not Rollup, sadly.) But at least you don't have to use them day-in and day-out!
