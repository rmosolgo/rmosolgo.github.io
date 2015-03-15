---
layout: post
title: "Happy Refactoring by Keeping ApplicationController to a Minimum"
date: 2015-01-17 10:24
comments: true
categories:
  - Rails
---

Extending `ActionController::Base` _once_, in `ApplicationController`, is a great Ruby on Rails practice. However, if `ApplicationController` is your only abstract controller, it's likely to become a maintenance challenge. To avoid this, you should extend `ApplicationController` as needed and move as much code as possible into its subclasses.

<!-- more -->


## Feeling ApplicationController Pain

So, our app is live. We've dutily extended `ApplicationController` in all our other controllers, giving us an inheritance tree like this:

{% img /images/controller_inheritance_bad.png 500 500 %}

Fortunately, our app is a success and our customers want us to open an API. Let's use `API::BaseController` as the superclass of all our API controllers:

{% img /images/controller_inheritance_bad_with_api.png 500 500 %}

As our user base grows, we need a more robust permissions system. We tighten up restrictions:

```ruby
class ApplicationController < ActionController::Base
  before_action :authenticate!
end
```

Since some actions are public, we skip the restrictions:

```ruby
class ReportsController < ApplicationController
  skip_before_action :authenticate!
end
# ...
class ProfilesController < ApplicationController
  skip_before_action :authenticate!
end
```

We've forgotten about our API, and when we deploy, we'll be quickly reminded that `ApplicationController` is involved in those requests too. Since `ApplicationController` touches _every request_, it's hard to be sure about exactly what will be affected by changes there.

## ApplicationController Gains Weight

Left alone, `ApplicationController` can bloat for many reasons:

  - __Authentication logic__, perhaps with complex branching based on what the user is accessing, builds up little-by-little as the application is extended.
  - __Before-actions & helpers__ which are used _often_ but _not always_ tend to accrue in `ApplicationController`, since they're "used more than once."
  - __Oddball routes__ might be implemented in `ApplicationController` because no other existing controller seems like the right place.

In JavaScript development, filling the global namespace with application code is a no-no. Similarly, `ApplicationController` is a near-global namespace, so each addition to it should be considered very carefully. When we add to (and remove from) `ApplicationController`, we're potentially altering _every_ request that our application serves; how can we be sure we aren't breaking something?

## Isolating "Parts" of the App

Returning to the example above, I think this inheritance tree is better:

{% img /images/controller_inheritance_good.png 500 500 %}

We've introduced abstract classes for each "part" of the app. (I use quotes because I don't know a technical term for it!) Now, logged-in authentication would be handled by a subclass of `ApplicationController`, perhaps named `BaseController`. A logged-in controller would extend `BaseController`. For example:

```ruby
class ItemsController < BaseController
  # ...
end
```

Similarly, public controllers would be in a namespace of their own, with their own base controller. For example:

```ruby
class Public::ProfilesController < Public::BaseController
  # ...
end
```

This is good because:

- You can refactor with more confidence, since you only have to load _part_ of the app into memory when working on abstract controllers.
- Stable parts of the app are more likely to remain stable (since they won't be affected by other parts).


The corresponding file structure looks like this:

```bash
controllers/
  api/
    base_controller.rb
    items_controller.rb
    profiles_controller.rb

  public/
    base_controller.rb
    reports_controller.rb
    profiles_controller.rb

  staff/
    base_controller.rb
    stats_controller.rb

  application_controller.rb
  base_controller.rb
  items_controller.rb
  profiles_controller.rb
  reports_controller.rb
```

_(I've left some controllers in the root namespace. If you like, you could put logged-in actions in a namespace too!)_

And the routes might look like this:

```ruby
namespace :api do
  resources :items, :profiles
end

namespace :public do
  resources :profiles, :reports
end

namespace :staff do
  resources :stats
end

resources :items, :profiles, :reports
```

## When should we extend ApplicationController?

I'd say it's good to extend `ApplicationController` for each "part" of the app. It's a bit subjective, but here are some clues:

- Actions rendered with a __different layout__ (or lack thereof). Your webservice, administration and public views are distinct parts of your app.
- Actions using __different authentication__ strategies. Keep API endpoints, public pages, and staff-only actions in separate sections. If a staff member goes rogue, you'll be able to tighten up that part of the app confidently :)
- Actions with __different frequently-used helpers or before-actions__. If there's a before-action that's often skipped, Rails wants to tell you something: these controllers are different! Similarly, if you have controller-level helper methods, perhaps the controllers who depend on that helper should be in a "part" of their own.

I hope a pattern like this will give you more freedom & confidence when refactoring important parts of the request-response cycle!
