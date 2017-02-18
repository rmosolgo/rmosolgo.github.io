---
layout: post
title: "Using GraphQL without Relay"
date: 2016-03-03 10:01
comments: true
categories:
  - GraphQL
  - JavaScript
---

Although [Relay](http://facebook.github.io/relay/) made [GraphQL](facebook.github.io/graphql) famous, GraphQL was in use at Facebook for years before Relay took the scene. You can use plain AJAX requests to interact with a GraphQL server, too.

<!-- more -->

__Update 18 Feb 2017:__ For a zero-dependency improvement of this concept, see [f/graphql-js](https://github.com/f/graphql.js).

GraphQL servers like [`express-graphql`](https://github.com/graphql/express-graphql) or [`graphql-ruby` on Rails](https://github.com/rmosolgo/graphql-ruby-demo) expose a single endpoint which responds to queries.

The endpoint accepts a few parameters:

- `query`: The GraphQL query string to execute
- `variables`: Runtime values for variables in the GraphQL query
- `operationName`: if `query` contains multiple operations, you must tell the server which _one_ to execute

Given this interface, you can even use jQuery as a GraphQL client! Here's how you would use `$.post` to interact with the server.

## 1. Build and send query strings

In your JavaScript, you could dynamically build a GraphQL query, then post it to the server.

For example, if you were searching users by name, you might use this function to build a query string:

```javascript
function usersByNameQuery(searchTerm) {
  // GraphQL requires double-quoted strings in the query:
  return '{ users(search: "' + searchTerm + '") { name, id }  }'
}

usersByNameQuery("bob")
// "{ users(search: "bob") { name, id }  }"
```

Then, you can post the query with `$.post`:

```javascript
var query = usersByNameQuery("bob")
$.post("/graphql", {query: query}, function(response) {
  if (response.errors) {
    // handle errors
  } else {
    // use response.data
  }
})
```

In the callback, you can check for errors and use the response's `data`.

## 2. Send query _and_ variables

Often, we know our data requirements ahead of time. That is, we know what values we need to render our UI. In this case, we can _separate_ the query structure and runtime values into `query` and `variables`.

Here's how we could adapt our previous example to separate the query from its values:

```javascript
// ES6 backtick-quoted string
var searchByNameQuery = `
query searchByName($searchTerm: String!) {
  users(search: $searchTerm) {
    name
    id
  }
}`

function fetchUsersByName(searchTerm) {
  var payload = {
    query: searchByNameQuery,
    variables: {
      // This will be used as `$searchTerm` by the server:
      searchTerm: searchTerm,
    }
  }

  $.post("/graphql", payload, function(response) {
    if (response.errors) {
      // handle errors ...
    } else {
      // use response.data
    }
  })
}
```

In this case, we always send the _same_ query string, but we change the `variables` for each request.

This setup is easier to maintain because the query string is so easy to read. Any changes to it will be easy to see in a pull request.

# 3. (future) Store query strings on the server

Maybe you noticed an optimization waiting to happen: since we always send the same query string, why send it at all? We could store it on the server ahead of time, then call it by name at runtime.

I heard that Facebook's GraphQL server had this behavior, but I don't know that any of the open implementations have it yet. I'm [considering it for `graphql-ruby`](https://github.com/rmosolgo/graphql-ruby/pull/76).
