---
layout: post
title: Testing GraphQL with Insta
date: 2026-09-03
categories:
  - Ruby
  - GraphQL
  - Testing
---

Snapshot testing with [`insta`](https://github.com/marcoroth/insta-ruby) is a great fit for developing GraphQL APIs in Ruby. Here's how I've been using it lately.

<!-- more -->

### Snapshot Testing

I learned "snapshot testing" from [Jest](https://jestjs.io/docs/snapshot-testing). The idea is that, instead of writing _every single assertion_ for some method's return value, you assert that it _matches the snapshot_. The first time you run the test, the library produces a snapshot for you (as a `.snap` file in the project). During later runs, it compares the new value to the previously-created snapshot. If it matches, ✅ pass. If it doesn't match, ❌ fail. When it fails, the snapshot tool presents you with a diff of the existing snapshot and the newly-returned value. Then, it's up to you to decide: Is the new value wrong? If so, fix the code. Or, if the new value is _correct_, then tell the snapshot tool to update the snapshot to a new value. Then, the snapshot changes show up in code review, since the `.snap` file was modified.

At best, you get all the benefits of writing a long line of assertions about returned values without cluttering the test files.

Anyway, I learned to love it. I use Jest snapshots in the `graphql-ruby-client` test suite for things like

- Checking the output of code generators
- Checking expected log messages
- Checking a sequence of mocked function calls


I have also rolled my own snapshot helpers in different projects, including [Perfetto snapshots](https://github.com/rmosolgo/graphql-ruby/blob/d78a1b2c4706bcb30c2a238ceb99e7b0aaf5a2b0/spec/support/perfetto_snapshot.rb) in GraphQL-Ruby and PDF snapshots in [Aqualytics](https://aqualyticsreports.com).

### Insta

[`insta`](https://github.com/marcoroth/insta-ruby) is a new gem for snapshot testing in Ruby. I read about it in the [Ruby Weekly](https://rubyweekly.com/) newsletter and knew I had to try it out.

The timing was perfect: I was about to add a GraphQL API to a small Rails application. I decided I'd take `insta` for a spin while I did.

I quickly settled on a simple test helper for GraphQL:

```ruby
# Use this inside an `ActionDispatch::IntegrationTest`
# It requires the current user to be set before the call is made
def assert_graphql_snapshot(query_str, redact: nil, **other_params)
  post "/graphql", params: { query: query_str, **other_params }
  assert_snapshot(response.parsed_body, serializer: :json, redact:)
end
```

### Pattern 1: Does this type (or field) _work_?

The simplest kind of test just makes a GraphQL `query`:

```ruby
assert_graphql_snapshot <<~GRAPHQL
{
  viewer {
    accounts(first: 5) {
      nodes {
        id # see note about `id` below
        name
        address
        reports(first: 5) {
          nodes {
            title
            preparedOn
          }
        }
      }
    }
  }
}
GRAPHQL
```

That test will produce a snapshot on its first run, and it's up to you to make sure it's correct. After that, the snapshot is saved and it will keep an eye on correct behavior from now on.

Besides a simple query, you could create a complicated test scenario then check the API output. For example:

```ruby
def test_it_properly_filters_by_priority
  # Do some application set up:
  current_user.messages.create!(
    sender: current_user.boss,
    subject: "Meet me in the HR conference room",
  )
  # Then test the complicated GraphQL field:
  assert_graphql_snapshot <<~GRAPHQL
  query {
    viewer {
      messages(first: 10, priority: URGENT) {
        nodes {
          subject
        }
      }
    }
  }
  GRAPHQL
end
```

During the first run, you confirm that the `messages` are properly filtered and approve the snapshot; after that, `insta` will keep an eye on it.

There are a couple of possible complications:

- `id`: For fixtures, an object's `id` is stable. But for newly-created objects, the `id` will change from run to run
- `created_at`, `updated_at`, and other timestamps

These fields are volatile and will cause snapshots to fail even when the code is working properly. `insta` provides a few suggestions about dealing with these:

- [`redact:`](https://github.com/marcoroth/insta-ruby#redactions) Allows you to identify JSON keys and replace them with a dummy string. This way, they're forced to match in between runs.
- For timestamps, use [`Timecop`](https://github.com/travisjeffery/timecop) to set the clock for the test run and make timestamps stable between runs.

This setup is great because you can test a whole bunch of fields without hand-writing assertions. It's easy to get more test coverage without more developer burden.

### Pattern 2: Mutation side-effects

Since GraphQL `mutation`s also return a result, you can use `assert_graphql_snapshot` to confirm the outcome of a mutation. For example:


```ruby
assert_graphql_snapshot <<~GRAPHQL, variables: { id: report.id }
mutation($id: ID!) {
  updateReport(input: { id: $id, title: "May 2026 Service Report", preparedOn: "2026-05-01" }) {
    errors
    report {
      title
      preparedOn
    }
  }
}
```

In a single test, you run the side-effects and confirm the output.

There are some side-effects that aren't well-suited to snapshot testing:

- Enqueuing background jobs
- Sending emails (or other notification messages)
- Deleting objects

These side-effects don't modify an object that can be readily checked in a mutation response, so you'll still need other unit testing techniques for them.

### Pattern 3: Active Record Logs

Not GraphQL-specific, but I like to know what the database does to satisfy a GraphQL query. If it changes, I need to know, because it could cause performance problems.

To capture Active Record logs as an `insta` snapshot, I made another helper:

```ruby
# Wrap a block and assert that the SQL queries stay the same
def assert_active_record_log_snapshot(&block)
  # Capture the log into this StringIO
  previous_logger = ActiveRecord::Base.logger
  stringio = StringIO.new
  ActiveRecord::Base.logger = Logger.new(stringio)
  # Do the work
  result = block.call
  # Remove timestamps and noise
  ar_log = stringio.string
    .gsub(/ \(\d+\.\d+ms\)/, "")
    .gsub(/D, \[.*\]/, "")
  # Check the snapshot
  assert_snapshot(ar_log, name: "active_record_log")
  # Return the result of the block, just in case
  result
ensure
  # Put the old logger back
  ActiveRecord::Base.logger = previous_logger
end
```

This wraps GraphQL snapshots, for example:

```ruby
assert_active_record_log_snapshot do
  assert_graphql_snapshot <<~GRAPHQL
    { ... }
  GRAPHQL
end
```

It's a little bit annoying on the first run because _each_ snapshot has to be accepted before the run will finish, so it takes to `insta review`s to get the test passing.

When this snapshot fails, dig in to see whether the new SQL log is an improvement or a regression, and address it accordingly.

You could use this same approach with other client libraries that write to a `logger`, like .

### Next Steps with Insta

My first experience with `insta` has been great. I'm hoping to use it more and I have a couple of ideas for that:

- Adopt `insta` in the GraphQL-Ruby test suite. It could replace the hand-rolled `perfetto_snapshot` helpers, the existing ActiveRecord log helpers, and it could make a lot of unit tests easier.
- Could I make a `serializer: :pdf` for `insta`? It looks like [Serializers are pluggable](https://github.com/marcoroth/insta-ruby/tree/main/lib/insta/serializers), and that would be really handy for me in developing [Aqualytics](https://aqualyticsreports.com).
- In another app, I have a hand-rolled `assert_object_matches_snapshot ...` test helper that could be greatly improved by adopting `insta`.

Thanks [`@marcoroth`](https://github.com/marcoroth) for the great gem!
