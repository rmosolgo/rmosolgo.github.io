---
layout: post
title: '"Vertical" Complexity vs. "Horizontal" Complexity'
date: 2015-03-11 13:27
comments: true
categories:
  - Programming
---

While adding a big feature to [PCO Check-Ins](http://get.planningcenteronline.com/check-ins), I was struck with this way of describing my approach to adding complexity to the system.

<!-- more -->

Suppose you're given the task: "Our system only handles data of type _X_, it also needs to handle data of type _Y_. Everywhere." All over the program, you need to check what kind of data you have, then choose to handle it the old way or handle it the new way.

Your program has one entry point and renders views outputs:

```
     +     
     |     
     |     
+----+----+
|    |    |
|    |    |
+    +    +
A    B    C
```

## Vertical Complexity

One way to address this problem is to find everywhere you handle data type _X_, then extend it to handle type _Y_:

```ruby
if data.type_X?
  # handle data type X
else
  # handle data type Y
end
```

Your code paths now look like this:

```
         +     
         |     
         | 
  +------+------+
  |      |      |
  |      |      |
+-+-+  +-+-+  +-+-+  <- check for type X or type Y
|   |  |   |  |   |
+   +  +   +  +   +
A1  A2 B1  B2 C1  C2
```

Your program has grown "vertically": the tree is "deeper" than it was.

## Horizontal Complexity

Another approach would be to implement a parallel set of views for rendering the new data. Your existing views don't change. Instead you add three new views:

```
         +
         |
         |
+--+--+--+--+--+--+
|  |  |     |  |  |
|  |  |     |  |  |
+  +  +     +  +  +
A  B  C     D  E  F
```

Your program has grown "horizontally". It has more objects, but each one is doing a small job.

This way, your existing views stay simple. The new views can be equally simple. Hopefully, recycled code can be shared between views!

## In Rails

Rather than adding `if`s in controller actions, add a new controller. Maybe it renders the same kind of objects as the existing controller -- that's OK! It's worth it to add the extra controllers & actions to keep the code paths simple.




