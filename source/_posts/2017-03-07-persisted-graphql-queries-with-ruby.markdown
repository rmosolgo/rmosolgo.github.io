---
layout: post
title: "Persisted GraphQL Queries with Ruby"
date: 2017-03-07 7:55
comments: true
published: false
categories:
- Ruby
- GraphQL
---

<a href="http://graphql.pro" target="_blank">GraphQL Pro</a> 1.3.0 adds [support for server-defined queries via `GraphQL::Pro::Repository`](http://rmosolgo.github.io/graphql-ruby/pro/persisted_queries). In this approach, GraphQL operations are stored on the server and clients invoke them by name.

<!-- more -->

This provides several benefits:

- You can completely close the door to client-provided query strings. This removes an attack vector for a malicious client who might try to swamp your system with expensive queries.
- Static queries (in `.graphql` files) are easier to review and more available tooling (eg, code generation or analysis).
- Operation names improve [GraphQL server monitoring](http://rmosolgo.github.io/graphql-ruby/pro/monitoring) by serving as the primary unit of analysis.

## What's a "repository?"

A `GraphQL::Pro::Repository` works like a single, large GraphQL document with many different operations (ie, queries, mutations, or subscriptions) and fragments inside it. These operations are validated and analyzed as a single unit, as if they came in a single query string.

From a client's perspective, the server has a fixed set of operations it can perform. Each one can be executed by sending its [operation name](http://graphql.org/learn/queries/#operation-name).

The repository approach allows us to use pre-existing GraphQL concepts:

- __[Document](https://facebook.github.io/graphql/#sec-Language.Query-Document)__: A GraphQL document is a set of operations and fragments. The semantics of a valid document are [well-specified](https://facebook.github.io/graphql/#sec-Validation) and broadly implemented. A repository is an extension of this concept.
- [__Operation name__](http://graphql.org/learn/queries/#operation-name): GraphQL includes a way to specify which operation to run in a document. Repositories build on this by separating the set of operations (which lives on the server) from the identifier (which comes from the client).

By employing these concepts, we make full use of the battle-tested [graphql-ruby](https://github.com/rmosolgo/graphql-ruby) runtime without deviating from the spec.

## A Quick Example

First, add a `.graphql` file with a named operation:

```
# app/graphql/documents/GetItems.graphql
query GetItems {
  # Your GraphQL here:
  items {
    name
  }
}
```

Then, define a repository with that path:

```ruby
MyAppRepository = GraphQL::Pro::Repository.define do
  schema MyAppSchema
  path Rails.root.join("app/graphql/documents")
end
```

Next, update your controller to execute queries with the repository instead of the schema:

```diff
# app/controllers/graphql_controller.rb
- MyAppSchema.execute(
-   query_string,
+ MyAppRepository.execute(
+   operation_name: params[:operationName]
    context: context,
    variables: variables,
  )
```

Finally, execute the operation by sending a request with the `operationName`:

```js
$.post("/graphql", { operationName: "GetItems" }, function(response) {
  console.log(response.data)
})

// {
//   items: [
//     { name: "Item 1" },
//     ...
//    ]
// }
```

🎉 We served a GraphQL response by name!

## Naming Files

A straightforward approach is to name `.graphql` files after the operations they contain, so this operation:

```text
mutation UpdateComment($id: Int!, $body: String!) {
  updateComment(id: $id, body: $body) {
    # ...
  }
}
```

would go in:

```
app/graphql/documents/UpdateComment.graphql
```

This way, a reader can skim the `app/graphql/documents` directory to take a quick inventory of operations. Also, this one-to-one mapping mimics the Ruby convention of putting constants in identically-named files.

In the end, `GraphQL::Pro::Repository` will accept files with any name, as long as they match `#{path}/**/*.graphql`.

## Sharing Fragments

Since a repository functions as one big GraphQL document, [fragments](http://graphql.org/learn/queries/#fragments) are shared by default.

You can put fragments in their own files, then reference them from each operation that needs them. This way, operations with common data responsibilities can share code, ensuring that they stay in sync.

For example, consider a list of comments with a box to create a new comment. We'd make three `.graphql` files:

```text
app/graphql/documents/
  ListComments.graphql
  CreateComment.graphql
  CommentFields.graphql
```

First, specify the operation to load the list of comments:

```text
# app/graphql/documents/ListComments.graphql
query ListComments($postId: ID!) {
  post(id: $id) {
    comments {
      author {
        name
      }
      body
      createdAt
      updatedAt
    }
  }
}
```

Then, specify the operation to create a new comment:

```text
# app/graphql/documents/CreateComment.graphql
query CreateComment($postId: ID!, $body: String!) {
  createComment(postId: $postId, body: $body) {
    # ??
  }
}
```

After creating a comment, you want to update the list of comments to include the new member. To express this shared need for data, create a fragment with the required fields:

```text
# app/graphql/documents/CommentFields.graphql
fragment CommentFields on Comment {
  author {
    name
  }
  body
  createdAt
  updatedAt
}
```

Then, apply the fragment to `ListComments` and `CreateComment`:

```diff
# app/graphql/documents/ListComments.graphql
  query ListComments($postId: ID!) {
    post(id: $id) {
      comments {
+       ...CommentFields
-       author {
-         name
-       }
-       body
-       createdAt
-       updatedAt
      }
    }
  }
```

```diff
  # app/graphql/documents/CreateComment.graphql
  query CreateComment($postId: ID!, $body: String!) {
    createComment(postId: $postId, body: $body) {
-     # ??
+     ...CommentFields
    }
  }
```

This way:

- A reader can see that these operations are linked
- If the list view ever requires more data, the create operation will load that data, too

## Next Steps

- Repositories can also [accept dynamic inputs](http://rmosolgo.github.io/graphql-ruby/pro/persisted_queries#arbitrary-input). This allows you to use GraphiQL during development or continue serving old clients while you transition to server-defined queries.
- On Rails, repositories watch their files and reload as needed. If you're using another framework, you can [reload repositories](http://rmosolgo.github.io/graphql-ruby/pro/persisted_queries#watching-files) as needed.
- You can use a repository to find [unused fields](http://rmosolgo.github.io/graphql-ruby/pro/persisted_queries#analysis) in your schema.

For me, I'm hoping to improve client support (eg, Apollo Client) and server tooling (eg, query diffing) to make repositories even more useful!
