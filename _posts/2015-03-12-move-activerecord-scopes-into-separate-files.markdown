---
layout: post
title: "Move ActiveRecord Scopes into Separate Files"
date: 2015-03-12 08:14
comments: true
categories:
  - Rails
  - Programming
---

Ruby on Rails models tend to grow and grow. When refactoring scopes, it turns out you _can_ move them into their own classes.

<!-- more -->

## The Problem

Rails models can get out of hand. Over time they get more associations, more methods, more everything. The resulting huge API and visual clutter makes those classes hard to maintain.

Consider these scopes:

```ruby
class CheckIn < ActiveRecord::Base
  scope :normal, -> { where(kind: "Regular") }
  scope :guest, -> { where(kind: "Guest") }
  scope :volunteer, -> { where(kind: "Volunteer") }
  scope :first_time, -> {
    joins(%{
      INNER JOIN person_events
        ON  person_events.person_id =         check_ins.person_id
        AND person_events.event_id =          check_ins.event_id
        AND person_events.first_check_in_id = check_ins.id
        })
  }
end
```

## How do we usually address this?

For me, refactoring often means finding related methods & values that deserve their own class, then moving code out of the model and into the new class. For example:

- moving complex validations into [validator classes](http://api.rubyonrails.org/classes/ActiveModel/Validator.html)
- moving complex serialization into serializer classes (I do this with serialization to _English_, too, not just JSON)
- moving complex calculations into value classes.

Whenever I'm trying to move code out of a model, I visit Code Climate's [great post on the topic](http://blog.codeclimate.com/blog/2012/10/17/7-ways-to-decompose-fat-activerecord-models/).

However, _scopes_ are never on the list. What can we do with those?

## Digging In

I poked around Rails source a bit to see if there were any other options available to me.

I found that the `body` passed to `ActiveRecord::Base.scope` just has to [respond to `:call`](https://github.com/rails/rails/blob/5e0b555b453ea2ca36986c111512627d806101e7/activerecord/lib/active_record/scoping/named.rb#L149). I guess that's why lambdas are a shoo-in for that purpose: they respond to `:call` and aren't picky about arguments.

The other thing I found is that the lambdas you usually pass to `scope` _aren't magical_. I always assumed that they were `instance_eval`'d against other objects at whatever other times, but as far as I can tell, they aren't magical. `self` is always the model class (from lexical scope), just like any other lambda.

Instead, the magic is a combination of Rails' [thread-aware `ScopeRegistry`](https://github.com/rails/rails/blob/5e0b555b453ea2ca36986c111512627d806101e7/activerecord/lib/active_record/scoping.rb#L57) which tracks the scope for a given class, combined with [`Association#scoping`](https://github.com/rails/rails/blob/ce32ff462f3ba89c87f337f9150b3976d23220e8/activerecord/lib/active_record/relation.rb#L319), which I don't understand. :)

## Moving Scopes from Lambda to Class

You can make a class that complies to the required API. Make calls on the model class (`CheckIn`, in my case), which is usually `self` in a `scope` lambda.

```ruby
# app/models/check_in/scopes/latest.rb
class CheckIn::Scopes::Latest
  def call
    CheckIn.where("check_ins.id IN (SELECT max(id) FROM check_ins GROUP BY check_ins.person_id)")
  end
end
```

Then, hook up the scope in the model definition:

```ruby
class CheckIn < ActiveRecord::Base
  scope :latest, Scopes::Latest.new
end
```

Since it's just a plain ol' class, you can give it __other methods__ too:

```ruby
# app/models/check_in/scopes/latest.rb
class CheckIn::Scopes::Latest
  def call
    CheckIn.where(query_string)
  end

  private

  def query_string
    "check_ins.id IN (SELECT max(id) FROM check_ins GROUP BY check_ins.person_id)"
  end
end
```

You can also __initialize it__ with some data:

```ruby
class CheckIn < ActiveRecord::Base
  scope :normal,          Scopes::KindScope.new("Regular")
  scope :guest,           Scopes::KindScope.new("Guest")
  scope :volunteer,       Scopes::KindScope.new("Volunteer")
end
```


## Any Benefit?

Here's what I think:

__Pros:__

- Less visual noise.
- Your model still reads like a table of contents.
- Theoretically, you could test the scope in isolation (but I'm too lazy, if the existing tests still pass, that's good enough for me :P).

__Cons:__

- If the scope takes arguments, you can't tell right away.
- It doesn't _actually_ shrink the class's API: it's still a big ol' model.
- It's not a known Rails practice.




