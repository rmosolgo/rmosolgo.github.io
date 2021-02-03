---
layout: post
title: "Prototyping a GraphQL Schema From Definition With Ruby"
date: 2017-03-17 15:49
categories:
- Ruby
- GraphQL
---

GraphQL 1.5.0 includes a new way to define a schema: from a GraphQL definition.

<!-- more -->

In fact, loading a schema this way has been supported for while, but 1.5.0 adds the ability to specify field resolution behavior.

## GraphQL IDL

Besides queries, GraphQL has an _interface definition language_ (IDL) for expressing a schema’s structure. For example:

```ruby
schema {
  query: Query
}

type Query {
  post(id: ID!): Post
}

type Post {
  title: String!
  comments: [Comment!]
}
```

You can turn a definition into a schema with `Schema.from_definition`:

```ruby
schema_defn = "..."
schema = GraphQL::Schema.from_definition(schema_defn)
```

(By the way, the IDL is technically in [RFC stage](https://github.com/facebook/graphql/pull/90).)

## Resolvers

`Schema.from_definition` also accepts `default_resolve:` argument. It expects one of two inputs:

- A nested hash of type `Hash<String => Hash<String => #call(obj, args, ctx)>>`; or
- An object that responds to `#call(type, field, obj, args, ctx)`

#### Resolving with a Hash

When you’re using a hash:

- The first key is a _type name_
- The second key is a _field name_
- The last value is a _resolve function_ (`#call(obj, args, ctx)`)

To get started, you can write the hash manually:

```ruby
{
  "Query" => {
    "post" => ->(obj, args, ctx) { Post.find(args[:id]) },
  },
  "Post" => {
    "title" => ->(obj, args, ctx) { obj.title },
    "body" => ->(obj, args, ctx) { obj.body },
    "comments" => ->(obj, args, ctx) { obj.comments },
  },
}
```

But you can also reduce a lot of boilerplate by using a hash with default values:

```ruby
# This hash will fall back to default implementation if another value isn't provided:
type_hash = Hash.new do |h, type_name|
  # Each type gets a hash of fields:
  h[type_name] = Hash.new do |h2, field_name|
    # Default resolve behavior is `obj.public_send(field_name, args, ctx)`
    h2[field_name] = ->(obj, args, ctx) { obj.public_send(field_name, args, ctx) }
  end
end

type_hash["Query"]["post"] = ->(obj, args, ctx) { Post.find(args[:id]) }

schema = GraphQL::Schema.from_definition(schema_defn, default_resolve: type_hash)
```

Isn’t that a nice way to set up a simple schema?

#### Resolving with a Single Function

You can provide a single callable that responds to `#call(type, field, obj, args, ctx)`. What a mouthful!

The _advantage_ of that hefty method signature is that it’s enough to specify any resolution behavior you can imagine. For example, you could create a system where type modules were found by name, then methods were called by name:

```ruby
module ExecuteGraphQLByConvention
  module_function
  # Find a Ruby module corresponding to `type`,
  # then call its method corresponding to `field`.
  def call(type, field, obj, args, ctx)
    type_module = Object.const_get(type.name)
    type_module.public_send(field.name, obj, args, ctx)
  end
end

schema = GraphQL::Schema.from_definition(schema_defn, default_resolve: ExecuteGraphQLByConvention)
```

So, a single function combined with Ruby’s flexibility and power opens a lot of doors!

Doesn’t it remind you a bit of method dispatch? The arguments are:

GraphQL Field Resolution | Method Dispatch
-------|--------
`type` | class
`field` | method
`obj` | receiver
`args` | method arguments
`ctx` | runtime state (cf [`mrb_state`](https://github.com/mruby/mruby/blob/master/include/mruby.h#L257), [`RedisModuleCtx`](https://github.com/antirez/redis/blob/unstable/src/modules/INTRO.md), or [`ErlNifEnv`](http://erlang.org/doc/tutorial/nif.html))


## Special Configurations

Some schemas need other configurations in order to run:

- `resolve_type` to support union and interface types
- schema plugins like [monitoring](https://rmosolgo.github.io/graphql-ruby/pro/monitoring) or custom [instrumentation](https://rmosolgo.github.io/graphql-ruby/schema/instrumentation)

To add these to a schema, use `.redefine`:
```ruby
# Extend the schema with new definitions:
schema = schema.redefine {
  resolve_type ->(obj, ctx) { ... }
  monitoring :appsignal
}
```

## What’s Next?

Rails has proven that “Convention over Configuration” can be a very productive way to start new projects, so I’m interested in exploring convention-based APIs on top of this feature.

In the future, I’d like to add support for schema annotations in the form of directives, for example:

```ruby
type Post {
  comments: [Comment!] @relation(hasMany: "comments")
}
```


These could be used to customize resolution behavior. Cool!
