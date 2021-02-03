---
layout: post
title: "Authorization in GraphQL"
date: 2015-08-04 10:19
categories:
  - GraphQL
  - Ruby
---

A [GraphQL](http://facebook.github.io/graphql/) system works differently from a "traditional" RESTful JSON API. Instead of authenticating during controller actions, you can authenticate users with "query context."

<!-- more -->

__UPDATE 23 Jan 2017:__ For more resources on authorization with [graphql-ruby](https://github.com/rmosolgo/graphql-ruby), see:

- [Authorization guide](http://rmosolgo.github.io/graphql-ruby/queries/authorization)
- [GraphQL::Pro](http://graphql.pro/) [authorization guide](http://rmosolgo.github.io/graphql-ruby/pro/authorization) for integration with Pundit, CanCan or custom auth schemes.

## Query Context

GraphQL execution systems should allow the consumer to pass some arbitrary data "through" the query, so it is accessible at any time during execution. For example, you could take some information from an HTTP request, pass it into the query, then use that information during field resolution.

You can see this idea at work in [graphql-js 0.2.4](https://github.com/graphql/graphql-js/tree/v0.2.4):

- An arbitrary value enters the `execute` function [as `rootValue`](https://github.com/graphql/graphql-js/blob/v0.2.4/src/execution/execute.js#L108) and is [built into `context`](https://github.com/graphql/graphql-js/blob/v0.2.4/src/execution/execute.js#L119)
- Execution context is [passed to `executeFields`](https://github.com/graphql/graphql-js/blob/v0.2.4/src/execution/execute.js#L203-L206)
- `rootValue` is [drawn back out and passed](https://github.com/graphql/graphql-js/blob/v0.2.4/src/execution/execute.js#L489) to fields' resolve functions, where it is the [third argument](https://github.com/graphql/graphql-js/blob/v0.2.4/src/execution/execute.js#L663)

This way, any value that you pass to `execute` is passed along to any field resolution.

[graphql-ruby](https://github.com/rmosolgo/graphql-ruby) also implements this idea:

- `Query#new` accepts [a `context:` keyword](https://github.com/rmosolgo/graphql-ruby/blob/adcf3c8ee83ba06232d71df1a2360bc985caf4d3/lib/graph_ql/query.rb#L15)
- That value is [accessible through `Query::Context`](https://github.com/rmosolgo/graphql-ruby/blob/adcf3c8ee83ba06232d71df1a2360bc985caf4d3/lib/graph_ql/query.rb#L74),
which is [passed to field resolution methods](https://github.com/rmosolgo/graphql-ruby/blob/adcf3c8ee83ba06232d71df1a2360bc985caf4d3/lib/graph_ql/field.rb#L54)

## Using Query Context for Authorization

To implement authorization in GraphQL, you could use query context.
There are roughly two approaches:

#### Pass a permission indicator into the query.

Before executing the query, determine the permission level of the current user, then pass that into the query as context. That way, each field can test the permission level to determine how to resolve.

For example, in Ruby:

```ruby
# pass the permission level in the context hash
permission = current_user.permission
query = GraphQL::Query.new(MySchema, query_string, context: {permission: permission})
query.result
```

Inside a field, you could access `context[:permission]`, for example:

```ruby
GraphQL::Field.new do |f|
  # ...
  f.resolve -> (obj, args, context) do
    # Check the permission level which was passed as context
    if context[:permission] == "admin"
      object.secret_info
    else
      nil
    end
  end
end
```

This allows you to access permission information without abusing the global scope.

#### Pass the user object into the query.

If your authentication scheme is more complex, you can pass the user object in to the query context.

For example, in Ruby:

```ruby
# Pass `current_user` in the context hash
query = GraphQL::Query.new(MySchema, query_string, context: {user: current_user})
query.result
```

That way, fields can access the user object at resolve-time:

```ruby
GraphQL::Field.new do |f|
  # ...
  f.resolve -> (object, args, context) {
    # Check the user which was passed as context
    if context[:user].can?(:read, object)
      objects.secret_info
    else
      nil
    end
  }
end
```

If you pass the user object into query context, you can use fine-grained authentication when resolving fields.
