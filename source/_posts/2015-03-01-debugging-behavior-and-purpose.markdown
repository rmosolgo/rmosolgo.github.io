---
layout: post
title: "Debugging: Behavior &amp; Purpose"
date: 2015-03-01 15:53
comments: true
categories:
  - Life
---

To resolve a bug, a developer must know the _behavior_ and the _purpose_ of the program at hand. I've been reading [Lesslie Newbingin](http://en.wikipedia.org/wiki/Lesslie_Newbigin) and it made me think of this.

<!-- more -->

There are at least two kinds of bugs:

- The program crashes
- The program does not crash, but it does not accomplish the desired result

In either case, the developer must draw on two important facts in order to fix the bug:

- What is the _current behavior_ of the program? How does it work?
- What is the _purpose_ of the program? Why does it exist?

### Debugging: Behavior

In some cases, a bug expresses itself by causing the program to crash. The fix  may be purely technical:

- don't enter an infinite loop
- rectify an off-by-one error
- fix a typo in the source code

### Debugging: Purpose

In other cases, a bug does _not_ cause the program to crash. In fact, the program runs fine, but there is still a bug. Here, _purpose_ is essential.

I often ask the product manager, "How should this program behave?" His response is dictated by the _design_ of the application: why does it exist? What was it made for? What should it accomplish?

No amount of technical information can answer that question.

### Software without Purpose?

Imagine error handling without purpose. Suppose an external web service returns `404 Not Found`. How should that be handled by our application? In a program whose design is unknown, the developer has no option but to hide the crash:

```ruby
begin
  # do something
rescue
  nil # who knows?
end
```

Sometimes, this is the norm for American culture. Bugs in society aren't _treated_ as much as _suppressed_. How could they be treated? We insist that discussions regarding the _purpose_ of humanity are a private matter and not to be addressed in a public way. "What's true for you might not be true for me."

### Product Manager of Product Managers

A key tenet of Christianity is that, in the life of Jesus of Nazareth, God communicated to humans their purpose. It has traditionally been summarized as  "The chief end of man is to worship God and enjoy him forever." This means we ought to live (individually and together) in light of God's supremacy and our togetherness as his children.

This opens the door to much more effective troubleshooting. When the system (human life, human society) fails, we can do more than apply technical bandages; we can refashion the system to better serve the purpose for which it was designed.

Nobody operates under a truly purposeless mindset. Indeed, even when we state a purpose, we find ourselves seeking to fulfill a different one. But we ought to ask: what design _should_ we try to fulfill?
