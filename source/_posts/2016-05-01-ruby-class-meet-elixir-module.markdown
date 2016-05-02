---
layout: post
title: "Ruby Class, meet Elixir Module"
date: 2016-05-01 11:10
comments: true
published: false
categories:
  - Ruby
  - Programming
---

Elixir modules offer some valuable insight into designing Ruby classes.

<!-- more -->

Ruby classes combine _data_ and _behavior_ in a typically object-oriented way:

- __data:__ instances of the class hold state in instance variables
- __behavior:__ methods on the class alter state.

Elixir modules also combine data and behavior:

- __data:__ the module's eponymous struct defines an immutable data structure
- __behavior:__ the module's functions define state transformations, often taking the struct as input

Perhaps we can combine these ideas to gain some functional-style benefits in Ruby!

## Data: Problem   

Ruby's mutable values open the door to errors caused by out-of-sight state changes. Here's a simple example:

```ruby
# mutate the passed-in array 😈
def cause_mayhem(array)
  array << nil
end

top_scores = [98, 95, 89]
cause_mayhem(top_scores)
top_scores.max # ArgumentError: comparison of Fixnum with nil failed
```

Unbeknownst to the user, `cause_mayhem` _altered_ the array. It wasn't equal to its original value anymore! This is possible with many common objects in Ruby programming , eg `String`, `Hash`, `ActiveRecord::Base`, `ActiveRecord::Relation` and `ActionController::Params`.

When you pass a value to another method, you have _no way_ to know how your value will be affected. Maybe it will be changed under your feet!

Elixir's immutable values offer a solution to this pitfall. When you pass a value to a function, your value won't be changed because it's _impossible_ to change it!

```elixir
cause_mayhem = fn(list) -> [99999 | list] end

top_scores = [98, 95, 89]
cause_mayhem.(top_scores) # => [99999, 98, 95, 89]
Enum.max(top_scores)      # => 98
```

Although `cause_mayhem` returned a _new_ list, it didn't alter the existing list. Changing the value of an existing item is impossible with Elixir! Because of this, you never have to worry about passing your value to another function. It _can't_ mess up existing code!

## Data: Solution

The Ruby solution is to write classes whose state is immutable.

A _mutable_ class is one whose instance variables change during its lifetime. An _immutable_ class is one whose instance variables _never_ change during its lifetime.

Here's an example of refactoring a mutable class to be immutable.


First, a mutable `Counter`:

```ruby
class MutableCounter
  attr_reader :count

  def initialize
    @count = 0
  end

  # Adds one to the internal value
  def increment
    @count += 1
  end
end
```

Now, here's the problem with this class. It leads to unpredictable code:

```ruby
counter = MutableCounter.new
counter.count         # => 0
counter.increment
counter.count         # => 1
cause_mayhem(counter)
counter.count         # => ????
```

It could be mutated by `cause_mayhem`... but we have no idea!

Next, an immutable `Counter` class

```ruby
class ImmutableCounter
  attr_reader :count

  def initialize(count: 0)
    @count = count
  end

  # Return a _new_ ImmutableCounter with an incremented count
  def increment
    self.class.new(count: @count + 1)
  end
end
```

No matter how you call methods on that object, its `@count` will not change after initialization.

Here's our problem code again:

```ruby
counter = ImmutableCounter.new
counter.count         # => 0
counter = counter.increment
counter.count         # => 1
cause_mayhem(counter)
counter.count         # => 1 🎊  
```

There's no way `cause_mayhem` could alter our counter!


__But,__ what if you _want_ to alter the value by some other method?

Easy: just make the method _return_ the value you want to use. Here's a modified example:

```ruby
# Increment the counter three times and return the new one
def modify_counter(counter)
  counter = counter.increment
  counter = counter.increment
  counter = counter.increment
  counter
end

# usage:

counter = ImmutableCounter.new
counter.count             # => 0
# store the old counter, just for example:
previous_counter = counter
# reassign the counter
counter = modify_counter(counter)
# counter has the new value:
counter.count           # => 3
# previous_counter was unchanged:
previous_counter.count  # => 0
```

In this case, the caller must _explicitly_ receive the new value from the function. This makes it obvious to the reader that the function returned a new, useful value!

## Behavior: Problem

In Ruby, classes express _behavior_ by exposing public methods. These methods may alter internal state (like `MutableCounter#increment`). Shared code may be DRYed up by being relocated to a private method.

Here's an example:

```ruby
class BaseballTeam
  # ...
  def add_player(player)
    @players << player
    # reset cached averages, etc:
    update_team_aggregates
  end
end
```

The problem is that state changes are scattered throughout the code. Some are visible inline, some are out-of-sight. This makes `BaseballTeam` harder to understand.

To learn the behavior of `add_player`, must also know the behavior of `update_team_aggregates`. _Any_ part of the `BaseballTeam`'s internal state could have been altered in any way! At the end of the method body, there's no guarantee that `@players` contains the same objects it at the start of the method body. 😢.

In Elixir, any behavior that _would_ mutate an object actually creates a _new_ object. The analogous code is:

```elixir
defmodule BaseballTeam do
  def add_player(team, player) do
    players = [player | team.players]
    [avg_batting_avg, avg_salary, avg_pitching_record] = calculate_aggregates(players)
    %{team | players: players, avg_batting_avg: avg_batting_avg, avg_salary: avg_salary, avg_pitching_record: avg_pitching_record}
  end
end
```

In this case, it's clear exactly which keys of the `BaseballTeam` struct are updated when a players is added. It's impossible for `calculate_aggregates` to alter any other part of the `team`!

## Behavior: Solution

The Ruby solution is to write methods as pure functions, that is, methods which use their arguments as their _only_ input (no accessing `self`) and provide a return value as their _only_ output (no side-effects).

Here's a rewritten Ruby example:

```ruby
class BaseballTeam
  # ...
  def add_player(player)
    @players << player
    @avg_batting_avg, @avg_salary, @avg_pitching_record = calculate_aggregates(@players)
  end
end
```

In this case, it's obvious which members of the `team`'s internal state will be modified by `add_player`. However, a developer _could_ break the purely functional contract of `calculate_aggregates`.

To avoid that, refactor `BaseballTeam` to be a composition of `@players` and `@aggregates`:

```ruby
class BaseballTeam
  class AggregateStats
    def initialize(players)
     # ...
    end
    # ...
  end
  # ...
  def add_player(player)
    @players << player
    @aggregates = AggregateStats.new(@players)
  end

  # Aggregate methods delegate to the AggregateStats object:
  def avg_salary
    @aggregates.avg_salary
  end
end  
```

Further defensive techniques could be taken, such as:

- Creating a _new_ `@players` array instead of mutating the existing one.
- Freezing `@players` to prevent other code from changing it

Those measures would guarantee correct state, but they may be "overkill" for some uses!

## Conclusion

I can't magically transform my Ruby app into an Elixir app, but I _can_ take some of the lessons learned from Elixir and apply them to Ruby code! Plus, Ruby gives us the ability to mutate state when necessary (for example, when performance is critical).
