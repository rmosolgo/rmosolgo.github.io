---
layout: post
title: "High-Performance Parsing in Ruby with Ragel and Racc"
date: 2016-08-24 09:49
published: false
categories:
- Ruby
- Language Implementation
---

When it comes to parsing with Ruby, [Parslet](http://kschiess.github.io/parslet/) is the best way to get up and running quickly. But when you need more speed, [Ragel](http://www.colm.net/open-source/ragel/) and [Racc](https://github.com/tenderlove/racc) combine to make a powerful solution.

<!-- more -->

I learned about this approach from [whitequark's Ruby parser](https://github.com/whitequark/parser) and applied it to [`graphql-ruby`](https://github.com/rmosolgo/graphql-ruby/pull/119). The resulting parser was _almost_ as fast a parser in C!

```
~/projects/graphql $ ruby -Ilib parse_benchmark.rb
Parse INTROSPECTION_QUERY 100 times:
                           user     system      total        real
Parslet                5.820000   0.040000   5.860000 (  5.874497)
Racc + Ragel           0.330000   0.010000   0.340000 (  0.328350)
Libgraphqlparser       0.040000   0.000000   0.040000 (  0.052346)
```

## The tools: Ragel and Racc

Ragel and Racc are both _compilers_; you give them a configuration file and they output Ruby code.

__Ragel__ is for building a _lexer_. A lexer's job is to separate an input string into a stream of meaningful _tokens_. For example, let's tokenize a mathematical expression:

```ruby
# Raw string:
expr = "1 + 2 = 3"

tokens = tokenize(expr)

# Stream of tokens:
p tokens
[
  [:int, "1"],
  [:op,  "+"],
  [:int, "2"],
  [:op,  "="],
  [:int, "3"],
]
```

Each token as a _type_, like `:int` or `:op`, which gives its meaning, as well as its _value_, like `"1"` or `"+"`.

__Racc__ is for building a _parser_. The parser takes tokens as inputs and connects them into larger entities. The result is a tree, called the _abstract syntax tree_ (AST). Let's parse the mathematical expression from above:

```ruby
expr = "1 + 2 = 3"
tokens = tokenize(expr)
# Send tokens to be parsed:
ast = parse(tokens)

# The result is a tree:
p ast.inspect
#
#           EqualityExpression
#           /                \
#      Expression      IntLiteral(3)
#          |
#    BinaryExpression
#    /     |       \
#   /      |        \
#  |  IntLiteral(1)  IntLiteral(2)
#  |
# Operator(+)
```

The AST is the end result. It adds _content_ and _structure_ to the input string. It is ready to be processed by the rest of the program.

## Lexer with Ragel and Ruby

As mentioned above, Ragel is a lexer _generator_, which means you give it some specifications, and it returns a lexer which implements your specifications. In light of that, there are three steps to using Ragel:

- Prepare your specifications
- Give your specifications to Ragel and store the resulting Ruby code
- Integrate the Ragel-generated Ruby code with your application

### Prepare your specifications

Your input to Ragel is a `.rl` file. The file contains:

- Ruby code, which you already know and love
- Ragel instructions, which are plain text, prefixed by `%%`

- __List the Ragel instructions__
- __Give a minimal example__

### Transform your specifications to Ruby

Ragel itself is a program with a command-line interface. When you invoke it, you give it an input file and `-R`, which tells it to output Ruby code. (In fact, Ragel can generate lexers in several languages, but we want Ruby!)

When Ragel finishes, it writes a new `.rb` file, created according to your specifications.

For example, here's a how we call Ragel in `graphql-ruby`:

```sh
ragel -R lib/graphql/language/lexer.rl
# creates lib/graphql/language/lexer.rb
```

### Integrate the lexer

Now, you have some plain-Ruby code that can take a string as input and generate a list of tokens as output.

That stream of tokens is the input for your _parser_, which we'll discuss below.

## Parser with Racc and Ruby

Ruby ships with a parser generator named __Racc__. The name is a spin on the venerable tool _Yacc_ -- Racc is _Ruby-Yacc_. Like Ragel, Racc is a _generator_: you give it some specifications and it returns some Ruby code.

### Racc grammar

### Adding the lexer

### Building the parser

##
