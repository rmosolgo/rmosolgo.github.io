---
layout: post
title: "GraphQL Query as a State Machine"
date: 2016-11-12 13:07
comments: true
categories:
- Ruby
- GraphQL
---

State machines are applied to a wide variety of programming problems. I found it useful to think of a GraphQL query as a state machine.

<!-- more -->

## Part 0: Introduction to State Machines

Practically speaking, a state machine is a unit of code with these properties:

- It has a set of _states_
- It is in one state at a time
- _Transitions_ connect one state to another
- Transitions can be triggered by outside activity and/or make changes to code on the "outside"
- One state is the _starting_ state
- One or more states may be valid _ending_ states

State machines are also called "finite automata".

To see why code like this is useful, let's examine a couple of applications of _state machines_:

- Some __ORM__s use a state machine to track the lifecycle of persisted objects. For example, the set of states may be: `new`, `persisted` and `destroyed`. A new object begins in the `new` state. Calling `save()` initiates a transition to the  `persisted` state. Calling `destroy()` moves the machine to the the `destroyed` state. Moving from `destroyed` to `new` is impossible; there is no transition between these states.
- __Regular expressions__ are often implemented with state machines. The regular expression's various patterns are transformed into states. While the expression is tested against a string, matching characters cause transitions from one valid state to another. Non-matching characters case a transition to the "failed" state. After the string has been completely tested, the regular expression tests itself: if it's in a valid _ending_ state, then the string was a match. If it isn't, then the string was _not_ a match.

In summary, state machines provide a model for well-defined progression through a many-stepped process.

## Determinism and Non-Determinism

Let's examine a regular expression as a state machine. Here's `/^abc$/` (matches `"abc"` only):

```
+-------+          +-----+          +-----+          +-----+          +-----+
| start | - "a" -> | MS1 | - "b" -> | MS2 | - "c" -> | MS3 | - EOS -> | end |
+-------+          +-----+          +-----+          +-----+          +-----+

* MS: "Matching State"
* EOS: "End of string"
```

In the diagram above, each state is represented by a box. Between states, transitions are represented by arrows. Since this is a regular expression, the transitions are named after the strings which they match. For example, if the machine is in the `start` state and it observes an `"a"`, it moves to Matching State 1 (`MS1`). As the regular expression matches the string `"abc"`, it progresses through the states, finally reaching `end`.

Let's see another regular expression, `/^abc?$/`. It matches two strings: `"ab"` and `"abc"`. Here's the state machine:

```
|                                      +-----+
|                             . "b" -> | MS2 | --- EOS ----------.
| +-------+          +-----+ /         +-----+                    `-----> +-----+
| | start | - "a" -> | MS1 |                                              | end |
| +-------+          +-----+ \         +-----+          +-----+       .-> +-----+
|                              `"b" -> | MS3 | - "c" -> | MS4 | - EOS
|                                      +-----+          +-----+
```

Contrasting this machine to the previous one, we can see a difference: this machine has a _branch_. To make matters "worse", the branch is _ambiguous_: from `MS1`, when a `"b"` appears in the string, should the machine move to `MS2` or `MS3`? It can only tell by looking _ahead_, and possibly backtracking, which is inefficient.

This difference is called _deterministic_ vs _non-deterministic_. The first machine is deterministic: for each state, each input character can lead to _exactly_ one state (`failed` state is not pictured). The second machine is _non_-deterministic: for some states, an input character may lead to _multiple_ states.

## Solving Non-Determinism

It turns out, you can _transform_ a non-deterministic machine into a deterministic machine. The process works like this:

- Inspect the non-deterministic machine:
- For each state, gather the possible inputs for that state.
- For each possible input, find the one-or-more destination states which it leads to.
- Take those destination states a create a _new_ state in deterministic machine
  - For a set of destination states `S`, the new state represents "any of `S`"
  - Repeat the process from this new state (find possible inputs, derive a new state for its possible destinations)

The result is a deterministic machine, some of whose states represent a _set_ of states in the non-deterministic machine.

Let's apply the transformation to the non-deterministic machine above:


```
|                                                     .--- EOS ----------.
| +-------+          +-----+          +------------+ /                    `---> +-----+
| | start | - "a" -> | MS1 | - "b" -> | MS2 or MS3 |                            | end |
| +-------+          +-----+          +------------+ \         +-----+       .-> +-----+
|                                                      `"c" -> | MS4 | - EOS
|                                                              +-----+          
```

The non-deterministic transitions on `"b"` have been replaced by a _single_ transition to a newly-created state. The new state represents `MS2` _or_ `MS3`, and it has transitions from _both_ of those states. It may transition on `EOS` _or_ it may transition on `"c"`.

The result is a deterministic machine: for each input, we have exactly one transition, so we never need to backtrack.

## What about GraphQL?

Consider a GraphQL query:

```
{
  parent {
    child {
      field1
      field2
      field3
    }
  }
}
```

Executing this query can be articulated in terms of a state machine:

- Each selection (`{ ... }`) is a state, which has a _type_ (a GraphQL type) and a _value_ (a value in the host language, eg, Ruby object)
- Fields are transitions: they move execution from one state to another (that is, from one selection to a child selection)
- When each field in a selection has been executed, the machine moves "back" to the parent state
- The _starting_ state is the root-level selection (eg, `query { ... }`)
- The _ending_ state is also the root-level selection, after traversing all selections in the query
- Some transitions are invalid: for example, if the value is `nil`, the machine can't move into a state whose type is non-null.

## Non-Determinism in GraphQL

Consider a query with three conditional fragments:

```
{
  node(id: $nodeId) {
    ... on Interface1 { child { field1 } }
    ... on Interface2 { child { field2 } }
    ... on Interface3 { child { field3 } }
  }
}
```

Depending on the runtime type of `node(id: $nodeId)`, 0, 1, 2, or 3 of those typed selections may be executed. This is a kind of non-determinism.

A simple solution for a GraphQL AST interpreter is:

- Test each condition and gather the selections which apply
- For each unique field in the set of selections, evaluate it
- Evaluate sub-selections for each field which matches that unique field

Concretely, that boils down to:

- Get the runtime type (`RT`) of the object (`O`) returned by `node(id: $nodeId)`
- For each interface type, if `RT` implements that interface, gather that selection
- Find uniquely-named fields in the set of selections (`child` is the only one)
- Resolve `child` field on `O`
- For each selection in the set, find fields named `child` and gather them up (a subset of `field1`, `field2`, `field3`)
- Repeat

This solution is not a good fit for [`graphql-ruby`](https://github.com/rmosolgo/graphql-ruby) because we have a pre-execution phase for analyzing incoming queries. This flow requires runtime types which are not available until fields are _actually_ executed.

## Solving Non-Determinism in GraphQL

To streamline execution, we can apply a similar transformation to a GraphQL query. Before executing, we can check each field:

- Identify each possible return type
- Identify each type condition
- Build a new "state" for each valid combination of return type and type conditions

The state contains a _set_ of selections. This machine can be the basis of _both_ pre-execution and execution, since all possible transitions have been identified. Execution will follow a subset of those transitions, depending on the runtime type of returned objects.

To visualize this transformation, consider a schema like this one:

```
type Query {
  node(id: ID!) : Node
}

union Node = TypeA | TypeB

type TypeA implements Interface1, Interface2 {
  # ...
}

type TypeB implements Interface2, Interface3 {
  # ...
}

interface Interface1 { ... }
interface Interface2 { ... }
interface Interface3 { ... }
```

Revisiting the previous query, we can do some ahead-of-time calculation about the possible execution paths:

- `node(id: $nodeId)` returns one of: `TypeA`, `TypeB`
- selections are conditioned by: `Interface1`, `Interface2`, `Inteface3`
- If `node(...)` returns `TypeA`, selections from `Interface1` and `Interface2` should be applied
- If `node(...)` returns `TypeB`, selections from `Interface2` and `Interface3` should be applied

This information allows us to "rewrite" the query above in a deterministic way:

```
{
  node(id: $nodeId) {
    ... on TypeA {
      child { field1, field2 }
    }
    ... on TypeB {
      child { field2, field3 }
    }
  }
}
```

Now, each runtime type transitions to _exactly_ one selection. This information simplifies pre-execution analysis and execution. Additionally, this computed state can cache field-level values like coerced arguments and field resolve functions.

In [graphql-ruby](https://github.com/rmosolgo/graphql-ruby), these transformations are implemented in `GraphQL::InternalRepresentation`.
