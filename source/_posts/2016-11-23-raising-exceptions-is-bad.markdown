---
layout: post
title: "Raising Exceptions is Bad"
date: 2016-11-23 10:34
comments: true
categories:
- Ruby
- Programming
---

In general, [raising exceptions for control flow](http://wiki.c2.com/?DontUseExceptionsForFlowControl) makes code hard to understand. However, there are other cases when an exception is the right choice.

<!-- more -->

## Raise vs Return

`raise` is `return`'s evil twin.

They __both__ stop the execution of the current method. After a `return`, nothing else is executed. After a `raise`, nothing else is executed ... _maybe_. The method may have a `rescue` or `ensure` clause which is executed after the `raise`, so a reader must check for those.

They __both__ change flow of control. `return` gives control back to the caller. `raise` may give control _anywhere_ on the call stack, depending on the specific error and `rescue` clauses. If all you see is a `raise`, you can't guess where it will be rescued!

They __both__ send values to their new destination. `return` provides the given value to the caller, who may capture the return value in a local variable. `raise` provides the error object to the `rescue`-er. `return` can send any kind of value, but `raise` can only send error objects.

They __both__ create coupling across call stack frames. `return` couples two adjacent call stack frames: caller depends on the return value. `raise` → `rescue` couples far-removed stack frames: they may be adjacent, or they may be several frames removed from one another.

## Raise → Rescue is Unpredictable

Sending values through a program by calling methods and `return`-ing values is very predictable. If you return a different value, the caller will get a different value. To see where return values "go", simply search for calls to that method.

Finding where `raise`'d errors go is a bit more challenging. For example, this change:

```ruby
# From:
def do_something
  # ...
  raise "Something went wrong"
end

# To:
class MyCustomError < StandardError
end

def do_something
  # ...
  raise MyCustomError, "Oops!"
end
```

How can you tell if this is a safe refactor? Here are some considerations:

- Instead of looking for callers of this method, you have to find _entire call stacks_ which include this method, since any upstream calls may also have expectations about this error.
- When searching for `rescue`s, you have to keep the error's ancestry in mind, finding bare `rescue`s, superclass-tagged `rescue`s and class-tagged `rescue`s.
- Some `rescue`s may _consume_ the error object itself. For example, they may read its `#message` or other attached data. If you change any properties of the error object, you may break the assumptions of those `rescue`s.
- If you find that the new error will be `rescue`'d differently, you must also consider how execution flow will change in other methods. For example, some methods may be cut short because previously-`rescue`'d errors now propagate through them. Other methods which _used_ to be cut short may now continue running, since errors are rescued in child method calls.

If your `raise` is located in a Ruby gem, these problems are even harder, because `rescue` clauses may exist in your users' code.

If your error patterns are well documented, `༼ つ ◕_◕ ༽つ 🏆`. Bravo, just don't break your public API. Users might still make assumptions _beyond_ the documentation, such as error ancestry or message values. Additionally, they could be monkey-patching library methods and applying `rescue`-related assumptions to those patches.

If your error patterns aren't documented, `💩 ノ༼ ◕_◕ ノ ༽`. You have no idea what assumptions users make about those errors! You can't be sure your changes won't break their code.

## Use Return Instead

`raise` can be replaced by `return`. However, if you're using `raise` to traverse many levels of the call stack, the refactor will be intense. Take heart: previously you were hacking your way back up the call stack, now you're creating a predictable, explicit flow through your program!

It's worth repeating, [don't use exceptions for flow control](http://wiki.c2.com/?DontUseExceptionsForFlowControl).

Here are some techniques for expressing failures with `return`.

- __Return errors__ instead of raising them. Ruby errors are objects, like everything else. You can return them to the caller and let the caller check whether the returned value is an error or not.  For example, to return an error:

```ruby
def do_something
  calculation = SomeCalculation.new # ...

  if calculation.something_went_wrong?  
    # Let the caller handle this error
    MyCustomError.new("oops!")
  else
    # Return the result to the caller
    calculation.result
  end
end
```

- __Use success and failure objects__. Instead of returning a raw `StandardError` instance to the caller, use a `Failure` class to communicate failure. Additionally, use a `Success` class to communicate success. (This is similar to the "monad" technique, eg [`dry-monads` gem](http://dry-rb.org/gems/dry-monads/).)

```ruby
class ConvertSuccess
  attr_reader :old_file, :new_file
  def initialize(old_file:, new_file:)
    # ...
  end
end

class ConvertFailure
  attr_reader :old_file, :error
  def initialize(old_file:, error:)
    # ...
  end
end

# Try to convert this file, returning either a
# ConvertSuccess or ConvertFailure)
def convert_file(file)
  # ...
  if error_message.nil?
    ConvertSuccess.new(old_file: file, new_file: converted_file)
  else
    ConvertFailure.new(old_file: file, error: error_message)
  end
end

# Try to convert a file,
# then specify behavior
# for failure case & success case:
conversion = convert_file(File.read(file_path))

case conversion
when ConvertSuccess
  # Do something with the new file
when ConvertFailure
  # Notify the user of the failure
end   
```

- As a last resort, __return `nil`__. Using `nil` as an expression of failure has some downsides:

  - `nil` can't hold a message or any extra data
  - sometimes, `nil` is a valid value

  But, for simple operations, using `nil` may be sufficient. Since it will be communicated via `return`, refactoring it will be straightforward in the future!

## Sometimes, Raise is Okay

`raise` has its purposes.

`raise` is a great way to signal that the program has reached a completely unexpected state and that it should exit. For example, in the `convert_file` example above, we could use `raise` to assert that we don't receive an unexpected value from `convert_file`:

```ruby
conversion = convert_file(File.read(file_path))
case conversion
when ConvertSuccess
  # Do something with the new file
when ConvertFailure
  # Notify the user of the failure
else
  raise("convert_file didn't return a ConvertSuccess or ConvertFailure, it returned: #{conversion.inspect}")
end   
```

Now, if the method ever returns some unexpected value, we'll receive a loud failure. Some people use `fail` in this case, which is also fine. However, the need to disambiguate `raise` and `fail` is a code smell: stop using `raise` for non-emergencies!

`raise` is also helpful for re-raising other errors. For example, if your library needs to log something when an error happens, it might need to capture the error, then re-raise it. For example:

```ruby
# This method yields to a user-provided block, eg
# `handle_converted_file(old_file) { |f| push_to_s3(f) }`
def handle_converted_file(old_file)
  conversion = convert_file(old_file)
  if conversion.is_a?(ConvertSuccess)
    yield(conversion.new_file)
  end
rescue StandardError => err
  # Make a log entry for the library:
  logger.log("User error from handle_converted_file", err)
  # Let the user handle this error:
  raise(err)
end
```

This way, you can respond to the error without disrupting user code.

## raise SharpKnifeError

In my own work, I'm transitioning _away_ from raising errors and _towards_ communicating failure by return values. This pattern is ubiquitous in languages like Go and Elixir. In Node.js, callbacks communicate errors in a similar way (callback arguments). I think Ruby code can benefit from this practice as well.
