---
layout: post
title: "Updating GitHub to GraphQL 1.8.0"
date: 2018-04-09 09:52
categories:
- Ruby
- GraphQL
---


GraphQL 1.8.0 was designed and built largely as a part of my work at GitHub. Besides designing the [new Schema definition API](http://graphql-ruby.org/schema/class_based_api), I migrated our codebase to use it. Here are some field notes from my migration.

<!-- more -->

If you want to know more about the motivations behind this work, check out this [previous post](/blog/2018/03/25/why-a-new-schema-definition-api/).

Below, I'll cover:

- The Process: in general, how I went about migrating our code
- The Upgrader: how to run it and roughly how it's organized
- Custom Transforms: extensions I made for the upgrader to work on GitHub-specific code
- Fixes By Hand: bits of code that needed more work (some of these could be automated, but aren't yet!)
- Porting Relay Types: using the class-based API for connections and edges
- Migrating DSL extensions: how to support custom GraphQL extension in the new API

## The Process

GitHub's type definitions are separated into folders by type, for example: `objects/`, `unions/`, `enums/` (and `mutations/`). I worked through them one folder at a time. The `objects/` folder was big, so I did it twenty or thirty files at a time.

I had to do `interfaces/` last because of the nature of the new class-based schema. Interfaces modules' methods can't be added to legacy-style GraphQL object types. So, by doing interfaces last, I didn't have to worry about this compatibility issue.

Now that I remember it, I did the schema _first_, and by hand. It was a pretty easy upgrade.

When I started each section, I created a base class by hand. (There is some automated support for this, but I didn't use it.) Then, I ran the upgrader on some files and tried to run the test suite. There were usually two kinds of errors:

- Parse- or load-time errors which prevented the app from booting
- Runtime errors which resulted in unexpected behavior or raised errors

More on these errors below.

After upgrading a section of the schema, I opened a PR for review from the team. This was crucial: since I was working at such a large scale, it was easy for me to miss the trees for the forest. My teammates caught a lot of things during the process!

After a review, the PR would be merged into master. Since GraphQL 1.8.0 supports incremental migration, I could work through the code in chunks without a long running branch or feature flags.

## About the Upgrader

Here's an overview of how the upgrader works. After reading the overview, if you want some specific examples, check out the [source code](https://github.com/rmosolgo/graphql-ruby/blob/master/lib/graphql/upgrader/member.rb).

### Running The Upgrader

The gem includes an auto-upgrader, spearheaded by the folks at [HackerOne](https://hackerone.com) and refined during my use of it. It's encapsulated in a class, `GraphQL::Upgrader::Member`.

To use the upgrader, I added a Ruby script to the code base called `graphql-update.rb`:

```ruby
# Usage:
#   ruby graphql-update.rb path/to/type_definition.rb
#
# Example:
#   # Upgrade `BlameRange`
#   ruby graphql-update.rb lib/platform/objects/blame_range.rb
#
#   # Upgrade based on a pattern (use quotes)
#   ruby graphql-update.rb "lib/platform/objects/blob_\*.rb"
#
#   # Upgrade one more file in this pattern (use quotes)
#   ruby graphql-update.rb 1 "lib/platform/objects/**.rb"

# Load the upgrader from local code, for easier trial-and-error development
# require "~/code/graphql-ruby/lib/graphql/upgrader/member"
# Load the upgrader from the Gem:
require "graphql/upgrader/member"

# Accept two arguments: next_files (optional), file_pattern (required)
file_pattern = ARGV[0]
if file_pattern =~ /\d+/
  next_files = file_pattern.to_i
  next_files_pattern = ARGV[1]
  "Upgrading #{next_files} more files in #{next_files_pattern}"
  filenames = Dir.glob(next_files_pattern)
else
  filenames = Dir.glob(file_pattern)
  next_files = nil
  puts "Upgrading #{filenames.join(", ")}"
end

# ...
# Lots of custom rules here, see below
# ...

CUSTOM_TRANSFORMS = {
  type_transforms: type_transforms,
  field_transforms: field_transforms,
  clean_up_transforms: clean_up_transforms,
  skip: CustomSkip,
}

upgraded = []
filenames.each do |filename|
  puts "Begin (#{filename})"
  # Read the file into a string
  original_text = File.read(filename)
  # Create an Upgrader with the set of custom transforms
  GraphQL::Upgrader::Member.new(original_text, **CUSTOM_TRANSFORMS)
  # Generate updated text
  transformed_text = upgrader.upgrade
  if transformed_text == original_text
    # No upgrade was performed
  else
    # If the upgrade was successful, update the source file
    File.write(filename, transformed_text)
    upgraded << filename
  end
  puts "Done (#{filename})"
  if next_files && upgraded.size >= next_files
    # We've upgraded as many as we said we would
    break
  end
end
puts "Upgraded #{upgraded.size} files: \n#{upgraded.join("\n")}"
```

This script has two basic parts:

- Using `GraphQL::Upgrader::Member` with a set of custom transformations
- Supporting code: accepting input, counting files, logging, etc

In your own script, you can write whatever supporting code you want. The key part from GraphQL-Ruby is:

```ruby
# Create an Upgrader with the set of custom transforms
GraphQL::Upgrader::Member.new(original_text, **CUSTOM_TRANSFORMS)
# Generate updated text
transformed_text = upgrader.upgrade
```

### The Pipeline

The upgrader is structured as a pipeline: each step accepts a big string of input and returns a big string of output. Sometimes, a step does nothing and so its returned string is the same as the input string. In general, the transforms consist of two steps:

- Check whether the transform applies to the given input
- If it does, copy the string and apply a find-and-replace to it (sometimes using RegExp, other times using the excellent `parser` gem.)

You have a few options for customizing the transformation pipeline:

- Write new transforms and add them to the pipeline
- Remove transforms from the pipeline
- Re-use the built-in transforms, but give them different parameters, then replace the built-in one with your custom instance

(The "pipeline" is just an array of instances or subclasses of `GraphQL::Upgrader::Transform`.)

We'll see cases of each below.

### Kinds of Transforms

The upgrader accepts several types of transform pipelines:

```ruby
CUSTOM_TRANSFORMS = {
  type_transforms: type_transforms,
  field_transforms: field_transforms,
  clean_up_transforms: clean_up_transforms,
  skip: CustomSkip,
}
```

- `type_transforms` are run first, on the _entire_ file.
- `field_transforms` are run second, but they receive _parts_ of the type definition. They receive calls to `field`, `connection`, `return_field`, `input_field`, and `argument`. Fine-grained changes to field definition or argument definition go here.
- `clean_up_transforms` are run last, on the _entire_ file. For example, there's a built-in `RemoveExcessWhitespaceTransform` which cleans up trailing spaces after other transforms have run.
- `skip:` has a special function: its `#skip?(input)` method is called and if it returns true, the text is not transformed at all. This allows the transformer to be idempotent: by default, if you run it on the same file over and over, it will update the file only _once_.

## Custom Transforms

Here are some custom transforms applied to our codebase.

### Handle a custom type-definition DSL

We had a wrapper around `ObjectType.define` which attached metadata, linking the object type to a specific Rails model. The helper was called `define_active_record_type`. I wanted to take this:

```ruby
module Platform
  module Objects
    Issue = define_active_record_type(-> { ::Issue }) do
      # ...
    end
  end
end
```

And make it this:

```ruby
module Platform
  module Objects
    class Issue < Platform::Objects::Base
      model_name "Issue"
      # ...
    end
  end
end
```

Fortunately, this can be done with a pretty straightforward regular expression substitution. Here's the transform:

```ruby
# Create a custom transform for our `define_active_record_type` factory:
class ActiveRecordTypeToClassTransform < GraphQL::Upgrader::Transform
  # Capture: leading whitespace, type name, model name
  FIND_PATTERN = /^( +)([a-zA-Z_0-9:]*) = define_active_record_type\(-> ?\{ ?:{0,2}([a-zA-Z_0-9:]*) ?\} ?\) do/
  # Restructure as a class, using the leading whitespace and adding the `model_name` DSL
  REPLACE_PATTERN = "\\1class \\2 < Platform::Objects::Base\n\\1  model_name \"\\3\""

  def apply(input_text)
    # It's safe to apply this transform to _all_ input,
    # since it's a no-op if `FIND_PATTERN` is missing.
    input_text.sub(FIND_PATTERN, REPLACE_PATTERN)
  end
end
```

Then, in `graphql-update.rb`, this transform was put _first_ in the list:

```ruby
# graphql-update.rb
type_transforms = GraphQL::Upgrader::Member::DEFAULT_TYPE_TRANSFORMS.dup
type_transforms.unshift(ActiveRecordTypeToClassTransform)
```

Also, for this to work, I added the `def self.model_name(name)` helper to the base class.

### Renaming a Custom Field Method

We have a helper for adding URL fields called `define_url_field`. I decided to rename this to `url_fields`, since these days it creates _two_ fields.

The arguments are the same, so it was a simple substitution:

```ruby
class UrlFieldTransform < GraphQL::Upgrader::Transform
  def apply(input_text)
    # Capture the leading whitespace and the rest of the line,
    # then insert the new name where the old name used to be
    input_text.gsub(/^( +)define_url_field( |\()/, "\\1url_fields\\2")
  end
end
```

This transform didn't interact with any other transforms, so I added it to `clean_up_transforms`, so it would run last:

```ruby
# Make a copy of the built-in arry
clean_up_transforms = GraphQL::Upgrader::Member::DEFAULT_CLEAN_UP_TRANSFORMS.dup
# Add my custom transform to the end of the array
clean_up_transforms.push(UrlFieldTransform)
```

### Moving DSL methods to keywords

We have a few DSL methods that, at the time, were easier to implement as keyword arguments. (Since then, the API has changed a bit. You can implement DSL methods on your fields by extending `GraphQL::Schema::Field` and setting that class as `field_class` on your base Object, Interface and Mutation classes.)

I wanted to transform:

```ruby
field :secretStuff, types.String do
  visibility :secret
end
```

To:

```ruby
field :secretStuff, types.String, visibility: :secret
```

(Later, a built-in upgrader would change `secretStuff` to `secret_stuff` and `types.String` to `String, null: true`.)

To accomplish this, I reused a built-in transform, `ConfigurationToKwargTransform`, adding it to `field_transforms`:

```ruby
# Make a copy of the built-in list of defaults
field_transforms = GraphQL::Upgrader::Member::DEFAULT_FIELD_TRANSFORMS.dup
# Put my custom transform at the beginning of the list
field_transforms.unshift(GraphQL::Upgrader::ConfigurationToKwargTransform.new(kwarg: "visibility"))
```

In fact, there were several configuration methods moved this way.

### Custom Skip

As I was working through the code, some files were tougher than others. So, I decided to skip them. I decided that a magic comment:

```ruby
# @skip-auto-upgrade
```

would cause a file to be skipped. To implement this, I made a custom skip class:

```ruby
class CustomSkip < GraphQL::Upgrader::SkipOnNullKeyword
  def skip?(input_text)
    super(input_text) || input_text.include?("@skip-auto-upgrade")
  end
end
```

And passed it as `skip:` to the upgrader. Then, later, I removed the comment and tried again. (Fortunately, my procrastination paid off because the upgrader was improved in the meantime!)

## Fixes by Hand

As I worked, I improved the upgrader to cover as many cases as I could, but there are still a few cases that I had to upgrade by hand. I'll list them here. If you're really dragged down by them, consider opening an issue on GraphQL-Ruby to talk about fixing them. I'm sure they _can_ be fixed, I just didn't get to it!

If you want to fix one of these issues, try to replicate the issue by adding to an example `spec/fixtures/upgrader` and then getting a failing test. Then, you could update the upgrader code to fix that broken test.

### Accessing Arguments By Method

Arguments could be accessed by method to avoid typos. However, now, since arguments are a Ruby keyword hash, they don't have methods corresponding to their keys.

Unfortunately, the upgrader doesn't do anything about this, it just leaves them there and you get a `NoMethodError` on `Hash`.

This could almost certainly be fixed by improving this find-and-replace in `ResolveProcToMethodTransform`:

```ruby
# Update Argument access to be underscore and symbols
# Update `args[...]` and `args.key?`
method_body = method_body.gsub(/#{args_arg_name}(?<method_begin>\.key\?\(?|\[)["':](?<arg_name>[a-zA-Z0-9_]+)["']?(?<method_end>\]|\))?/) do
 # ...
end
```

It only updates a few methods on `args`, but I bet a similar find-and-replace could replace _other_ method calls, too.

### Argument Usages Outside of Type Definitions

Sometimes, we take GraphQL arguments and pass them to helper methods:

```ruby
resolve ->(obj, args, ctx) {
  Some::Helper.call(obj, args)
}
```

However when this was transformed to:

```ruby
def do_stuff(**arguments)
  Some::Helper.call(@object, arguments)
end
```

It would break, because the new `arguments` value is a Ruby hash with underscored, symbol keys. So, if `Some::Helper` was using camelized strings to get values, it would stop working.

The upgrader can't really do anything there, since it's not analyzing the codebase. In my case, these were readily apparent because of failing tests, so I went and fixed them.

### context.add_error

We have some fields that add to the `"errors"` key _and_ return values, they used `ctx.add_error` to do so:

```ruby
resolve ->(obj, args, ctx) {
  begin
    obj.count_things
  rescue BackendIsBrokenError
    ctx.add_error(GraphQL::ExecutionError.new("Not working!"))
    0
  end
}
```

When upgraded, it doesn't work quite right:

```ruby
def count_things
  begin
    @object.count_things
  rescue BackendIsBrokenError
    @context.add_error(GraphQL::ExecutionError.new("Not working!"))
    0
  end
end
```

(If you don't have to return a value, use `raise` instead, then you can stop reading this part!)

The problem is that `@context` is not a _field-specific_ context anymore. Instead, it's the query-level context. (This is downside of the new API: we don't have a great way to pass in the field context anymore.)

To address this kind of issues, `field` accepts a keyword called `extras:`, which contains a array of symbols. In the case above, we could use `:execution_errors`:

```ruby
field :count_things, Integer, null: false, extras: [:execution_errors]
def count_things(execution_errors:)
  @object.count_things
rescue BackendIsBrokenError
  execution_errors.add("Not working!")
  0
end
```

So, `execution_errors` was injected into the field as a keyword. It _is_ field-level, so adding errors there works as before.

Other extras are `:irep_node`, `:parent`, `:ast_node`, and `:arguments`. It's a bit of a hack, but we need _something_ for this!

### Accessing Connection Arguments

By default, connection arguments (like `first`, `after`, `last`, `before`) are _not_ passed to the Ruby methods for implementing fields. This is because they're generally used by the automagical (😖) connection wrappers, not the resolve functions.

But, sometimes you just _need_ those old arguments!

If you use `extras: [:arguments]`, the legacy-style arguments will be injected as a keyword:

```ruby
# `arguments` is the legacy-style Query::Arguments instance
# `field_arguments` is a Ruby hash with symbol, underscored keys.
def things(arguments:, **field_arguments)
  arguments[:first] # => 5
  # ...
end
```

### Fancy String Descriptions

The upgrader does fine when the description is a `"..."` or `'...'` string. But in other cases, it was a bit wacky.

Strings built up with `+` or `\` always broke. I had to go back by hand and join them into one string.

Heredoc strings often _worked_, but only by chance. For example:

```ruby
field :stuff, types.Int do
  description <<~MD
    Here's the stuff
  MD
end
```

Would be transformed to:

```ruby
field :stuff, Integer, description: <<~MD, null: true
    Here's the stuff
  MD
```

This is valid Ruby, but a bit tricky. This could definitely be improved: since I started my project, GraphQL 1.8 was extended to support `description` as a _method_ as well as a keyword. So, the upgrader could be improved to leave descriptions in place if they're fancy strings.

### Removed Comments From the Start of Resolve Proc

I hacked around with the `parser` gem to transform `resolve` procs into instance methods, but there's a bug. A proc like this:

```ruby
resolve ->(obj, args, ctx) {
  # Do stuff
  obj.do_stuff { stuff }
}
```

Will be transformed to:

```ruby
def stuff
  @object.do_stuff { stuff }
end
```

Did you see how the comment was removed? I think I've somehow wrongly detected the start of the proc body, so that the comment was left out.

In my case, I re-added those comments by hand. But it could probably be fixed in `GraphQL::Upgrader::ResolveProcToMethodTransform`.

### Hash Reformating?

I'm not sure why, but sometimes a hash of arguments like:

```ruby
obj.do_stuff(
  a: 1,
  b: 2,
  c: 3,
  d: 4,
)
```

would be reorganized to

```ruby
obj.do_stuff(
  a: 1,
  b: 2, c: 3, d: 4,
)
```

I have no idea why, and I didn't look into it, I just fixed it by hand.

### Issues with Connection DSL

We have a DSL for making connections, like:

```ruby
Connections.define(Objects::Issue)
```

Sometimes, when this connection was inside a proc, it would be wrongly transformed to:

```ruby
field :issues, Connections.define(Objects::Issue) }, ,null: true
```

This was invalid Ruby, so the app wouldn't boot, and I would fix it by hand.

## Porting Relay Types

Generating connection and edge types with the `.connection_type`/`.define_connection` and `.edge_type`/`.define_edge` methods will work fine with the new API, but if you want to migrate them to classes, you can do it.

It's on my radar because I want to remove our DSL extensions, and that requires updating our custom connection edge types.

Long story, short, it Just Work™ed with the class-based API. The approach was:

- Add a base class inheriting from our `BaseObject`
- Use the new base class's `def self.inherited` hook to add connection- and edge-related behaviors
- Run the upgrader on edge and connection types, then go back and do some manual find-and-replaces to make them work right

So, I will share my base classes in case that helps. Sometime it will be nice to upstream this to GraphQL-Ruby, but I'm not sure how to do it now.

Base connection class:

```ruby
module Platform
  module Connections
    class Base < Platform::Objects::Base
      # For some reason, these are needed, they call through to the underlying connection wrapper.
      extend Forwardable
      def_delegators :@object, :cursor_from_node, :parent

      # When this class is extended, add the default connection behaviors.
      # This adds a new `graphql_name` and description, and searches
      # for a corresponding edge type.
      # See `.edge_type` for how the fields are added.
      def self.inherited(child_class)
        # We have a convention that connection classes _don't_ end in `Connection`, which
        # is a bit confusing and results in naming conflicts.
        # To avoid a GraphQL conflict, override `graphql_name` to end in `Connection`.
        type_name = child_class.name.split("::").last
        child_class.graphql_name("#{type_name}Connection")

        # Use `require_dependency` so that the types will be loaded, if they exist.
        # Otherwise, `const_get` may reach a top-level constant (eg, `::Issue` model instead of `Platform::Objects::Issue`).
        # That behavior is removed in Ruby 2.5, then we can remove these require_dependency calls too.
        begin
          # Look for a custom edge whose name matches this connection's name
          require_dependency "lib/platform/edges/#{type_name.underscore}"
          wrapped_edge_class = Platform::Edges.const_get(type_name)
          wrapped_node_class = wrapped_edge_class.fields["node"].type
        rescue LoadError => err
          # If the custom edge file doesn't exist, look for an object
          begin
            require_dependency "lib/platform/objects/#{type_name.underscore}"
            wrapped_node_class = Platform::Objects.const_get(type_name)
            wrapped_edge_class = wrapped_node_class.edge_type
          rescue LoadError => err
            # Assume that `edge_type` will be called later
          end
        end

        # If a default could be found using constant lookups, generate the fields for it.
        if wrapped_edge_class
          if wrapped_edge_class.is_a?(GraphQL::ObjectType) || (wrapped_edge_class.is_a?(Class) && wrapped_edge_class < Platform::Edges::Base)
            child_class.edge_type(wrapped_edge_class, node_type: wrapped_node_class)
          else
            raise TypeError, "Missed edge type lookup, didn't find a type definition: #{type_name.inspect} => #{wrapped_edge_class.inspect}"
          end
        end
      end

      # Configure this connection to return `edges` and `nodes` based on `edge_type_class`.
      #
      # This method will use the inputs to create:
      # - `edges` field
      # - `nodes` field
      # - description
      #
      # It's called when you subclass this base connection, trying to use the
      # class name to set defaults. You can call it again in the class definition
      # to override the default (or provide a value, if the default lookup failed).
      def self.edge_type(edge_type_class, edge_class: GraphQL::Relay::Edge, node_type: nil)
        # Add the edges field, can be overridden later
        field :edges, [edge_type_class, null: true],
          null: true,
          description: "A list of edges.",
          method: :edge_nodes,
          edge_class: edge_class

        # Try to figure out what the node type is, if it wasn't provided:
        if node_type.nil?
          if edge_type_class.is_a?(Class)
            node_type = edge_type_class.fields["node"].type
          elsif edge_type_class.is_a?(GraphQL::ObjectType)
            # This was created with `.edge_type`
            node_type = Platform::Objects.const_get(edge_type_class.name.sub("Edge", ""))
          else
            raise ArgumentError, "Can't get node type from edge type: #{edge_type_class}"
          end
        end

        # If it's a non-null type, remove the wrapper
        if node_type.respond_to?(:of_type)
          node_type = node_type.of_type
        end

        # Make the `nodes` shortcut field, which can be overridden later
        field :nodes, [node_type, null: true],
          null: true,
          description: "A list of nodes."

        # Make a nice description
        description("The connection type for #{node_type.graphql_name}.")
      end

      field :page_info, GraphQL::Relay::PageInfo, null: false, description: "Information to aid in pagination."

      # By default this calls through to the ConnectionWrapper's edge nodes method,
      # but sometimes you need to override it to support the `nodes` field
      def nodes
        @object.edge_nodes
      end
    end
  end
end
```

Base edge class:

```ruby
module Platform
  module Edges
    class Base < Platform::Objects::Base
      # A description which is inherited and may be overridden
      description "An edge in a connection."

      def self.inherited(child_class)
        # We have a convention that edge classes _don't_ end in `Edge`,
        # which is a little bit confusing, and would result in a naming conflict by default.
        # Avoid the naming conflict by overriding `graphql_name` to include `Edge`
        wrapped_type_name = child_class.name.split("::").last
        child_class.graphql_name("#{wrapped_type_name}Edge")
        # Add a default `node` field, assuming the object type name matches.
        # If it doesn't match, you can override this in subclasses
        child_class.field :node, "Platform::Objects::#{wrapped_type_name}", null: true, description: "The item at the end of the edge."
      end

      # A cursor field which is inherited
      field :cursor, String,
        null: false,
        description: "A cursor for use in pagination."
    end
  end
end
```

## Migrating DSL Extensions

We have several extensions to the GraphQL-Ruby `.define` DSL, for example, `visibility` controls who can see certain types and fields and `scopes` maps OAuth scopes to GraphQL types.

The difficulty in porting extensions comes from the implementation details of the new API. For now, definition classes are factories for legacy-style type instances. Each class has a `.to_graphql` method which is called _once_ to return a legacy-style definition. To maintain compatibility, you have to either:

- Modify the derived legacy-style definition to reflect configurations on the class-based definition; OR
- Update your runtime code to _stop_ checking for configurations on the legacy-style definition and _start_ checking for configurations on the class-based definition.

Eventually, legacy-style definitions will be phased out of GraphQL-Ruby, but for now, they both exist in this way in order to maintain backwards compatibility and gradual adoptability.

In the mean time, you can go between class-based and legacy-style definitions using `.graphql_defintion` and `.metadata[:type_class]`, for example:

```ruby
class Project < BaseObject
  # ...
end

legacy_type = Project.graphql_definition
# #<GraphQL::ObjectType> instance
legacy_type.metadata[:type_class]
# `Project` class
```

### The Easy Way: `.redefine`

The easiest way to retain compatibility is to:

- Add a class method to your base classes which accept some configuration and put it in instance variables
- Override `.to_graphql` to call super, and then pass the configuration to `defn.redefine(...)`, then return the redefined type.

After my work on our code, I extracted this into a [backport of `accepts_definition`](http://graphql-ruby.org/type_definitions/extensions.html#customization-compatibility)

You can take that approach for a try, for example:

```ruby
class BaseObject < GraphQL::Schema::Object
  # Add a configuration method
  def self.visibility(level)
    @visibility = level
  end

  # Re-apply the configuration
  def self.to_graphql
    type_defn = super
    # Call through to the old extension:
    type_defn = type_defn.redefine(visibilty: @visibility)
    # Return the redefined type:
    type_defn
  end
end

# Then, use it in type definitions:
class Post < BaseObject
  visibility(:secret)
end
```

### The Hard Way: `.metadata[:type_class]`

An approach I haven't tried yet, but I will soon, is to move the "source of truth" to the the class-based definition. The challenge here is that class-based definitions are not really used during validation and execution, so how can you reach configuration values on those classes?

The answer is that if a legacy-style type was derived from a class, that class is stored as `metadata[:type_class]`. For example:

```ruby
class Project < BaseObject
  # ...
end
legacy_defn = Project.graphql_definition # Instance of GraphQL::ObjectType, just like `.define`
legacy_defn.metadata[:type_class] # `Project` class from above
```

So, you could update runtime code to read configurations from `type_defn.metadata[:type_class]`.

Importantly, `metadata[:type_class]` will be `nil` if the type _wasn't_ derived from a class, so this approach is tough to use if some definitions are still using the `.define` API.

I haven't implemented this yet, but I will be doing it in the next few weeks so we can simplify our extensions and improve boot time.

## The End

I'm still wrapping up some loose ends in the codebase, but I thought I'd share these notes in case they help you in your upgrade. If you run into trouble on anything mentioned here, please [open an issue](https://github.com/rmosolgo/graphql-ruby/issues/new) on GraphQL-Ruby! I really want to support a smooth transition to this new API.
