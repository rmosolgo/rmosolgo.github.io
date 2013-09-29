---
layout: post
title: "Rspec should_receive stubs methods"
date: 2013-09-28 20:59
comments: true
categories:
  - Ruby
  - Rspec
---

I learned this the hard way, so I thought I'd share.

<!-- more !-->

A great feature of Rspec is its `should_receive` method, which checks if a message was sent to an object
sometime during that spec. For example, this test would pass:

```ruby
  class Fish
    def initialize
      @swishes = 0
    end

    attr_reader :swishes

    def swim!
      swish_tail!
    end

    private
      def swish_tail!
        @swishes += 1
      end
  end
```
```ruby
  describe Fish do
    it "swims by swishing its tail" do
      swimming_fish = Fish.new
      swimming_fish.should_receive :swish_tail!
      swimming_fish.swim!
    end
  end
```

However, `should_receive` also stubs the method, so if it is sent, its body isn't executed. This spec
won't pass:

```ruby
  describe Fish do
    it "swims by swishing its tail" do
      swimming_fish = Fish.new
      swimming_fish.should_receive :swish_tail!
      swimming_fish.swim!
      swimming_fish.swishes.should == 1 # OOPS, FAILS! it's still 0.
    end
  end
```




