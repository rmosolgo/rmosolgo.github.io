---
layout: post
title: "Dynamically-Generated Headers for ActiveResource Requests"
date: 2014-02-05 15:47
categories:
- Rails
---

Need to add a header to an ActiveResource request? If you need to do it at dynamically at request-time, redefine `.headers`.

<!-- more -->

I needed to include header in my requests, but I didn't just want to set it in the class definition.

```ruby
class MyResource < ActiveResource::Base
  headers["My-Header"] = "Something-Useful" # boo hiss, I want it dynamically!
end
```

So, I overwrote `.headers` to be a method rather than just a pointer to a hash:

```ruby
class MyResource < ActiveResource::Base
  cattr_accessor :static_headers
  self.static_headers = headers

  def self.headers
    new_headers = static_headers.clone
    new_headers["My-header"] = MyClass.some_method # voila, evaluated at request-time
    new_headers
  end
end
```

Now, I can add whatever value to the headers I want, whenever I want!
