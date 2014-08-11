---
layout: post
title: "Batman.js testing with Karma and Jasmine"
date: 2014-01-18 14:38
comments: true
categories:
  - Batman.js
  - Rails
---

Here's how I set up [Karma](http://karma-runner.github.io/) & [Jasmine](http://pivotal.github.io/jasmine/) to test a [Batman.js](http://batmanjs.org/) app on Ruby on Rails.

<!-- more -->

(Actually, this is how we use it at [work](http://get.planningcenteronline.com/). Credit to [Dan](http://danott.co/), as this is modeled after his work and [blog post](http://danott.co/posts/rails-javascript-testing-using-karma.html))


_Warning:_ This is a bit hack-ish because it depends on your development server running while you run your tests. :)

# Set Up Karma

You'll need [`node`](http://nodejs.org/) and [`npm`](https://npmjs.org/) for this to work! Create the directory `/spec/karma` and put these files in it:

- `package.json`, which will tell `npm` what to install for you:

```json spec/karma/package.json
{
  "name": "your-app-name",
  "version": "0.0.1",
  "engines": {
    "node": ">= 0.10"
  },
  "dependencies": {
    "karma": ">= 0.10",
    "karma-chrome-launcher", "~0.1",
    "karma-coffee-preprocessor": "~0.1",
    "karma-jasmine", "~0.2" // Or something else, if you prefer
  }
}
```

- `unit.coffee`, the configs for Karma:

```coffeescript spec/karma/unit.coffee
module.exports = (config) ->
  config.set
    basePath: '../../'
    frameworks: ['jasmine'] # that's my weapon of choice, anyways.
    plugins: [
      'karma-coffee-preprocessor'
      'karma-chrome-launcher'
      'karma-jasmine'
    ]
    preprocessors: {
      '../spec/**/*.coffee': ['coffee']
    }
    files: [
      'http://your-app.dev/assets/your-app.js' # point it at the app file on your dev server
      # yours might look like 'http://localhost:3000/assets/application.js' or something like that.
      # Of course, you can list as many files as you want here.
      'spec/batman/**/*.coffee' # load your tests
    ]
    reporters: ['dots']
    port: 9876
    colors: true
    logLevel: config.LOG_INFO
    autoWatch: true
    browsers: ['Chrome']
    captureTimeout: 60000
    singleRun: false
```

- `run`, a bash script to start the runner easily:

```bash spec/karma/run
#!/bin/bash
BASE_DIR=`dirname $0`
$BASE_DIR/node_modules/karma/bin/karma start $BASE_DIR/unit.coffee
# from app root, just run `$ ./karma/run` to start the tests!
```

- Make `run` executable with `$ chmod +x spec/karma/run`.
- Add `spec/karma/node_modules` to `.gitignore` so you're not pushing around tons of Node modules with your project.
- Install Karma locally with `npm install spec/karma`.

You should be able to start the runner now with `$ spec/karma/run`. It will open a Chrome window if it's working.

# Write a Spec

I put my Batman.js specs in `spec/batman` with names corresponding to their location in `app/assets/batman`. You can do it however you want, but make sure you're loading the right files with `files` in `unit.coffee` above. Open up your first spec file, maybe `spec/batman/test_spec.coffee`, and put a jasmine spec in it:

```coffeescript spec/batman/test_spec.coffee
describe 'My test runner', ->
  it 'loaded Batman.js', ->
    expect(Batman).toBeDefined()
  it 'loaded my App', ->
    expect(App).toBeDefined() # <-- your app name!
  it 'loaded my Model', ->
    expect(App.Model).toBeDefined() # <-- your model name!
```
If those pass, you're in business!

# Using Batman.TestCase

Since `Batman.TestCase` is a Batman extra, you'll need to include it in your project yourself. An easy way to do that is to include the [`src/extras/` directory](https://github.com/batmanjs/batman/tree/master/src/extras) from Github in your Rails app. For example, in `/app/assets/batman/extras`. Now, in your development server, visit `/assets/extras/batman.test_case.js`. Do you see the code for `Batman.TestCase`?

Now, just add that path to `files` in `spec/karma/unit.coffee`:

```coffeescript spec/karma/unit.coffee
# ...
  files: [
    "http://my-app.dev/assets/my_app.js"
    "http://my-app.dev/assets/extras/batman.test_case.js"
    "spec/batman/**/*.coffee"
  ]
#...
```

And if you want, make sure it's loaded with a jasmine spec:

```coffeescript spec/batman/test_case_spec.coffee
describe "Batman.TestCase is loaded", ->
  it "is defined", ->
    expect(Batman.TestCase).toBeDefined()
```

# Not working?

- Did you make `run` executable by with `$ chmod +x spec/karma/run`?
- This is kind of a hacky setup -- it depends on your development server (either `$ rails server` or [Pow](http://pow.cx/)) running. Is it?
- In `unit.coffee`, `files` should list your tests, but it should also list compiled JS assets from your development server, including `http://` and so on. Check the paths there in your browser. Do they contain everything you expect them to contain? You might need to add files to that list _or_ add [sprockets](https://github.com/sstephenson/sprockets) directives to those files so that they `require` other files.



Ok, well it ain't perfect but it works. Hope it helps!

