---
layout: post
title: "Tracking Schema Changes with GraphQL-Ruby"
date: 2017-03-16 20:16
comments: true
categories:
- Ruby
- GraphQL
---

One way to keep an eye on your GraphQL schema is to check the definition into source control.

<!-- more -->

When modifying shared code or reconfiguring, it can be hard to tell how the schema will _really_ change. To help with this, set up a __snapshot test__ for your GraphQL schema! This way:

- Changes will be clearly visible in GraphQL IDL
- You can keep the IDL up-to-date by adding a test to your suite

You can even track the schema from different contexts if you're using [`GraphQL::Pro`'s authorization framework](https://rmosolgo.github.io/graphql-ruby/pro/authorization).

This approach was first described in [GraphQL at Shopify](https://www.youtube.com/watch?v=Wlu_PWCjc6Y).

## Check It In

Write a __Rake task__ to get your schema's definition and write it to a file:

```ruby
# lib/tasks/graphql.rake
rake dump_schema: :environment do
  # Get a string containing the definition in GraphQL IDL:
  schema_defn = MyAppSchema.to_definition
  # Choose a place to write the schema dump:
  schema_path = "app/graphql/schema.graphql"
  # Write the schema dump to that file:
  File.write(Rails.root.join(schema_path), schema_defn)
  puts "Updated #{schema_path}"
end
```

You can run it from terminal:

```sh
$ bundle exec rake dump_schema
Updated app/graphql/schema.graphql
```

This updates the file in your repo. Go ahead and __check it in__!

```sh
$ git add app/graphql/schema.graphql
$ git commit -m "Add GraphQL schema dump"
```

## Keep It Up to Date

Any changes to the Ruby schema code must be reflected in the `.graphql` file. You can give yourself a reminder by adding a __test case__ which asserts that the GraphQL definition is up-to-date:

```ruby
# test/graphql/my_app_schema_test.rb
require "test_helper"

class MyAppSchemaTest < ActiveSupport::TestCase
  def test_printout_is_up_to_date
    current_defn = MyAppSchema.to_definition
    printout_defn = File.read(Rails.root.join("app/graphql/schema.graphql"))
    assert_equal(current_defn, printout_defn, "Update the printed schema with `bundle exec rake dump_schema`")
  end
end
```

If the definition is stale, you'll get a failed test:

{% img  /images/tracking_schema/test_failure.png 500 %}

This reminder is helpful in development and _essential_ during code review!

## Review It

Now that your schema definition is versioned along with your code, you can see changes during __code review__:

{% img  /images/tracking_schema/code_review.png 600 %}

## Multiple Schema Dumps

If your schema looks different to different users, you can track _multiple_ schema dumps. This is helpful if:

- You're using the `:view` configuration of [`GraphQL::Pro`'s authorization](https://rmosolgo.github.io/graphql-ruby/pro/authorization)
- You're using `only:`/ `except:` to manually filter your schema

Just provide the `context:` argument to `Schema.to_definition` as if you were running a query. (Also provide `only:`/`except:` if you use them.)

Print with a filter from the Rake task:

```ruby
# lib/tasks/graphql.rake
task dump_schema: :environment do
  # ...
  admin_user = OpenStruct.new(admin?: true)
  admin_schema_dump = MyAppSchema.to_definition(context: { current_user: admin_user })
  admin_schema_path = "app/graphql/admin_schema.graphql"
  File.write(Rails.root.join(admin_schema_path), admin_schema_dump)
end
```

Test with a filter from the test case:

```ruby
def test_printout_is_up_to_date
  # ...
  admin_user = OpenStruct.new(admin?: true)
  current_admin_defn = MyAppSchema.to_definition(context: { current_user: admin_user })
  printout_admin_defn = File.read(Rails.root.join("app/graphql/admin_schema.graphql"))
  assert_equal(current_admin_defn, printout_admin_defn, "Update the printed schema with `bundle exec rake dump_schema`")
end
```

Now you can keep an eye on the schema from several perspectives!
