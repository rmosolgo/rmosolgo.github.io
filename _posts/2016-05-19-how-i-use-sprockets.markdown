---
layout: post
title: "How I Use Sprockets"
date: 2016-05-19 08:44
comments: true
categories:
- Ruby
- Rails
- Sprockets
---

When reviewing issues for `react-rails`, I see many questions about how to gather JavaScript dependencies with Sprockets. Here is how I use Sprockets to manage JavaScript dependencies.

<!-- more -->

I'm looking for a few things in a JavaScript bundler:

- Stability: I don't want any changes to my dependencies unless I explicitly make them.
- Clarity: I want to be able to quickly tell what dependencies I have (library and version).
- Insulation: I don't want to rely on external services during development, deployment or runtime (except for downloading _new_ dependencies, of course)
- Feature-completeness: I want to concatenate and minify my assets and serve them with cache headers

## Using Sprockets

To __add a new dependency__:

1. Find a non-minified, browser-ready version of your dependency
1. Add it to `app/assets/javascripts/vendor/{library-name}-v{version-number}.js` (for example, `app/assets/javascripts/moment-v2.13.0.js`)
1. Require it in `application.js` with `//= require ./vendor/moment-v2.13.0`
1. Access the global variable as needed in your app (eg `moment`)

To __update__ a dependency:

1. Find a non-minified, browser-ready version of the updated dependency
1. Add it to `app/assets/javascripts/vendor/{library-name}-v{version-number}.js` and remove the _old_ version from that directory
1. Update the `//= require` directive with the new version number
1. Check the dependency's changelog and update your app as needed. (Search your project for the global variable to find usages, eg `moment`.)

To __remove__ a dependency:

1. Remove its file (`app/assets/javascripts/vendor/{library-name}-v{version-number}.js`)
1. Remove the `//= require` directive
1. Search your project for the global variable and remove all usages

## Finding a browser-ready file

This got its own page: [Finding a browser-ready file](/blog/2016/05/19/finding-a-browser-ready-file-for-sprockets/).

## Adding the file to `vendor/`

Use an __unminified__ version of the library. It will help in debugging development and viewing diffs when you update the dependency. Have no fear, Sprockets will minify it for you for production.

Include the __version number__ in the file name. This will give you more confidence in updating the library, since you'll know what version you're coming from.

## Integrating with Sprockets

The `//= require ./vendor/{library}-v{version}` directive is your friend. Like an entry in `package.json`, it tells the reader what dependency you have.

Now, your library will be accessible by its global name, such as `React`, `d3` or `Immutable`.

Consuming a library via global variable is not ideal. But it _does_ help you remember that, at the end of the day, the browser is one giant, mutable namespace, so you must be a good citizen! At least global variables can be grepped like any other dependency.

Consider isolating your dependency. For example, you could wrap `Pusher` in an application-specific event emitter. This way, when you update Pusher, you only have to check one file for its usages. (Some libraries are poor candidates for isolation. My app will never be isolated from React!)

## Caveats

There are some things Sprockets doesn't provide for me, which I wish it did:

- Named imports: I wish there was a good alternative to global namespacing with Sprockets, but not yet. (It's not a deal breaker -- it doesn't hurt to be familiar with this constraint because it's the reality of the browser, anyways.)
- Tree shaking: It wish I could only transmit the parts of Underscore.js I actually used!

Perhaps I should read up on Sprockets and submit a patch 😎

Also, there's one case where copy-pasting isn't a great solution. Some libraries (like React.js) have _separate_ "development" and "production" builds. The production build has fewer runtime checks than the development build, making it smaller and faster. There are a few solutions to this problem:

- Use a gem which provides the proper file for each environment (like `react-rails`)
- Add environment-specific folders to the asset pipeline (like `react-rails` does, I can write more on this if need be)
- Use the development build in productiosn (weigh the costs first: what's the difference in behavior, performance and file size?)
