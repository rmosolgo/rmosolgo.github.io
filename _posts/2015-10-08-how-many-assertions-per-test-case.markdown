---
layout: post
title: "How many assertions per test case?"
date: 2015-10-08 21:12
comments: true
categories:
 - Programming
 - Testing
---

This question is too hard. Instead, ask, "how many behaviors per test case?" and answer, "one."

<!-- more -->

I presented at Full Stack about unit testing but what I really like is behavior-driven development.

## A Behavior

You can think of a code base as a collection of behaviors: given some inputs (data, events), it makes some outputs (more data, more events). In this perspective, the code itself is an implementation detail. As long as it takes the inputs and creates the outputs, it makes little difference what classes, methods, functions etc, implement that behavior.

This kind of thinking is recursive: each behavior is composed of smaller behaviors. For example, in a web application:

```
Behavior:
  - A request with a valid username & password is allowed to take Action X

    Is composed of:
      - The user info is stored in the session
      - The user's `last_logged_in_at` is updated
      - Value Y is written to the database
```

Each subsequent level of behavior may have an implementation of its own.

## Testing a behavior

In a web application, unauthorized requests:

- Return meaningful HTTP responses, including a status and a body; and
- do not execute the requested action

I would specify that as two _behaviors_:

```ruby
describe "an unauthorized request" do
  it "responds as not authorized" do
    http_response = make_create_request # makes a unauthorized_request
    assert_equal(403, http_response.status)
    assert_equal("Not Authorized", http_response.body)
  end

  it "doesn't write to the database" do
    http_response = make_create_request # makes a unauthorized_request
    assert_equal(0, Posts.count)
  end  
end
```

(using [minitest/spec](https://github.com/seattlerb/minitest#specs))

Notice that the first test made _two_ assertions. You could split that into three test cases but I don't think it's worth the trouble. What's the case where `403` and `"Not Authorized"` are not part of the same behavior?

## Multiple Assertions is a Code Smell

If your test case has many assertions, your code may be telling you that you're specifying multiple behaviors at once. Ask yourself:

- Is there a smaller unit of work to extract?
- Can I make this a two-step process, where step one's result is passed to step two?
- Can I break each test case (and its corresponding code) into a distinct [strategy](http://c2.com/cgi/wiki?StrategyPattern)?
- Am I testing business logic _and_ interaction with an external service (eg, your database or an HTTP service)? Can I separate the two actions?
- Am I transforming data, then acting based on the result? Can I separate those two?
- Are there assertions that are shared between multiple test cases? Is there an underlying behavior there?

## Other People on The Internet

Here's some more dignified reading on the topic:

- __["Introducing BDD," Dan North](http://dannorth.net/introducing-bdd/)__. I especially agree with his point that behavior-driving thinking helps you focus your design and implementation.
- __["Testing One Assertion Per Test," Jay Fields](http://blog.jayfields.com/2007/06/testing-one-assertion-per-test.html)__. I basically agree with him: "Tests that focus on one behavior of the system are almost always easier to write and to comprehend at a later date." But I disagree with his assumption that one behavior equals one assertion.
- __["Is it OK to have multiple asserts in a single unit test?", random Stack Overflow people](http://programmers.stackexchange.com/a/7829)__. "Yeah, but try not to."
