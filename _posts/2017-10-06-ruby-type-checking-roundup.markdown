---
layout: post
title: "Ruby Type Checking Roundup"
date: 2017-10-06 09:00
categories:
- Ruby
- Programming
- Type Checking
---

This fall, several people presented their work on Ruby type checkers. So let's take a look: what's the big deal, and what have they been up to?

<!-- more -->

## Why Type Check?

Part of Ruby's appeal is to be _free_ of the cruft of its predecessors. So why is there so much interest in _adding_ types to Ruby?

- Large, sprawling projects are becoming more common. At Ruby's inception, there were no 10-year-old Rails apps which people struggled to maintain, only greenfield Ruby scripts for toy projects.
- Programmers have experienced excellent type systems in other languages, and want those benefits in Ruby.
- _Optional_, gradual type systems have been introduced to Python and JavaScript and they're big successes.

What are the benefits?

- **Correctness**: Type checking, like testing, is a way to be confident that your codebase is functioning properly. Employing a type checker can help you find bugs during development and prevent those bugs from going to production.
- **Confidence**: Since an incorrect program won't pass type checking, developers can refactor with more confidence. Common errors such as typos and argument errors can be caught by the type checker.
- **Design**: The type system gives you a way to think about the program. Specifically, types document and define the _boundaries_ between parts of code, like methods, classes and modules.

To experience a great type system in a Ruby-like language, I recommend [Crystal](https://crystal-lang.org/).

## Jeff Foster, StrangeLoop 2017

[Jeff Foster](http://www.cs.umd.edu/~jfoster/) is a professor at the [University of Maryland, College Park](http://www.umd.edu/) and works in the [programming languages group](http://www.cs.umd.edu/projects/PL/). Along with his students, he's been exploring Ruby type checkers for **nine years**! This year, he gave a presentation at StrangeLoop, [Type Checking Ruby](https://www.youtube.com/watch?v=buY54I7mEjA).

He described his various avenues of research over the years, and how they influenced one another, leading to a final question:

```ruby
class Talk < ActiveRecord::Base
  belongs_to :owner, class_name: "User"

  def owner?(other_user)
    # QUESTION
    # How to know the type of `#owner` method at this point?
    owner == other_user
  end
end
```

His early work revolved around _static_ type checking: annotations in the source code were given to a type checker, which used those annotations to assert that the Ruby code was correct.

This approach had a fundamental limitation: how can dynamically-created methods (like `Talk#owner` above) be statically annotated?

This drove him and his team to develop [RDL](https://github.com/plum-umd/rdl), a _dynamic_ type checker. In RDL, types are declared using _methods_ instead of annotations, for example:

```ruby
type '(Integer, Integer) -> Integer'
def multiply(x, y)
  x * y
end
```

By using methods, it handles metaprogramming in a straightforward way. It hooks into Rails' `.belongs_to` and adds annotations for the generated methods, for example:

```ruby
# Rails' belongs_to method
def belongs_to(name, options = {})
  # ...
  # define a reader method, like `Talk#owner` above
  type "() -> #{class_name}"
  define_method(name) do
    # ...
  end
end
```

(In reality, RDL uses [conditions](https://github.com/plum-umd/rdl#preconditions-and-postconditions), not monkey-patching, to achieve this.)

In this approach, type information is _gathered while the program runs_, but the typecheck is deferred until the method is called. At that point, RDL checks the source code (static information) using the runtime data (dynamic information). For this reason, RDL is called "Just-in-Time Static Type Checking."

You can learn more about RDL in several places:

- RDL on GitHub: https://github.com/plum-umd/rdl
- StrangeLoop 2017 talk: https://www.youtube.com/watch?v=buY54I7mEjA
- Academic papers from the folks behind RDL: https://github.com/plum-umd/rdl#bibliography

Personally, I can't wait to take RDL for a try. At the conference, Jeff mentioned that _type inference_ was on his radar. That would take RDL to the next level!

Not to read into it too far, but it looks like [Stripe is exploring RDL](https://github.com/plum-umd/rdl/issues/40#issuecomment-329135921) 😎.

## Soutaro Matsumoto, RubyKaigi 2017

Soutaro Matsumoto also has significant academic experience with type checking Ruby, and this year, he presented some of his work at RubyKaigi in [Type Checking Ruby Programs with Annotations](https://youtu.be/JExXdUux024).

He begins with an overview of type checking Ruby, and surveys the previous work in type inference. He also points out how requirements should be relaxed for Ruby:

- __~~Correctness~~ -> Forget correctness__ (Allow a mix of typed and untyped code, so that developers can work quickly when they don't want or need types.)
- __~~Static~~ -> Defer type checking to runtime__ (He mentions RDL in this context)
- __~~No annotations~~ -> Let programmers write types__ (_Completely_ inferring types is not possible, so accept some hints from the developers.)

Then, he introduces his recent project, [Steep](https://github.com/soutaro/steep).

Steep's approach is familiar, but new to Ruby. It has three steps:

- Write a `.rbi` file which describes the types in your program, using a special type language, for example:

```ruby
class Talk {
  def owner: (User) -> _Boolean
}
```

- Add annotations to your Ruby code to connect it to your types:

```ruby
class Talk < ActiveRecord::Base
  belongs_to :owner, class_name: "User"
  # @dynamic owner
end
```

  Some connections between Ruby source and the `.rbi` files can be made automatically; others require explicit annotations.

- Run the type checker:

  ```
  $ steep check app/models/talk.rb
  ```

It reminds me a bit of the `.h`/`.c` files in a C project.

Soutaro is also presenting his work at [this winter's RubyConf](http://rubyconf.org/program#session-233).

## Valentin Fondaratov, RubyKaigi 2017

Valentin works at JetBrains (creators of [RubyMine](https://www.jetbrains.com/ruby/)) and presented his work on type-checking based on _runtime_ data. His presentation, [Automated Type Contracts Generation for Ruby](https://www.youtube.com/watch?v=JS6m2gke0Ic), was really fascinating and offered a promising glimpse of what a Ruby type ecosystem could be.

Valentin started by covering RubyMine's current type checking system:

- RubyMine tries to resolve identifiers (eg, method names, constant names) to their implementations
- But this is hard: given `obj.execute`, what method does it call?
- Developers can provide hints with YARD documentation
- RubyMine uses this to support autocomplete, error prediction, and rename refactorings

He also pointed out that even code coverage is not enough: 100% code coverage does _not_ guarantee that all _possible_ codepaths were run. For example, any composition of `if` branches require a cross-product of codepaths, not only that each line is executed once. Besides that, code coverage does _not_ analyze the coverage of your dependencies' code (ie, RubyGems).

So, Valentin suggests getting _more_ from our unit tests: what if we _observed_ the running program, and kept notes about what values were passed around and how they were used? In this arrangement, that _runtime_ data could be accumulated, then used for type checking.

Impressively, he introduced the implementation of this, first using a [TracePoint](ruby-doc.org/core-2.4.0/TracePoint.html), then digging into the Ruby VM to get even more granular data.

However, the gathered data can be very complicated. For example, how can we understand the input type of `String#split`?

```ruby
# A lot of type checking data generated at runtime:
# call                                # Input type
"1,2,,3,4,,".split(",")               # (String, nil)
# => ["1", "2", "", "3", "4"]
"1,2,,3,4,,".split(",", 4)            # (String, Integer)
# => ["1", "2", "", "3,4,,"]
"1,2,,3,4,,".split(",", -4)           # (String, Integer)
# => ["1", "2", "", "3", "4", "", ""]
"1,2,,3,4,,".split(/\d/)              # (Regexp, nil)
# => ["", ",", ",,", ",", ",,"]
# ...
```

Valentin showed how a classic technique, finite automata, can be used to reduce this information to a useful data structure.

Then, this runtime data can be used to _generate_ type annotations (as YARD docs).

Finally, he imagines a type ecosystem for Ruby:

- Users contribute their (anonymized) runtime information for their RubyGem depenedencies
- This data is pooled into a shared database, merged by RubyGem & version
- Users can draw type data _from_ the shared database

Personally, I think this is a great future to pursue:

- Developers can _gain_ type checking without any annotations
- Annotations can become very robust because resources are shared
- _Real_ 100% coverage is possible via community collaboration

You can see the project on GitHub: https://github.com/JetBrains/ruby-type-inference

## Summary

There's a lot of technically-savvy and academically-informed work on type checking Ruby! Many of the techniques preserve Ruby's productivity and dynamism while improving the developer experience and confidence. What makes them unique is their use of _runtime_ data, to observe the program in action, then make assertions about the source code.
