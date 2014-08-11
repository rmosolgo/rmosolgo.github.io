---
layout: post
title: "Model Transactions in Batman.js"
date: 2014-07-19 09:15
comments: true
categories:
  - Batman.js
---

`Model::transaction` provides a deep-copied, "shadow-realm" version of a record which is great for rendering into edit forms. Any changes made to it can be saved (which updates the original record too), or just forgotten.

<!-- more -->

Here's the problem transactions exist to solve:

- You want your user to edit something
- You render a record into an edit form
- User edits the form
- User clicks back button
- User is surprised to see that the record's changes were "saved" (In fact, only the in-memory record was changed -- the change wasn't sent to the server)

`Model::transaction` solves this problem by returning a _deep copy_ of the record at hand which can be:

- __saved__, just like a normal record, in which case changes are applied to the original
- __forgotten__, by simply navigating away
- __applied__, which applies changes to the original, but doesn't update the server.

_The name "transaction" hearkens back to database transactions where changes aren't applied unless they're all successful. In the same way, changes to a `Batman.Transaction` aren't applied unless you explicitly `save` or `applyChanges`._

## Setting up a Transaction

To set up a transaction, call `transaction` on the record at hand:

```coffeescript
class MyApp.RaceHorsesController extends MyApp.ApplicationController
  edit: (params) ->
    MyApp.RaceHorse.find params.id, (err, record) ->
      deepCopy = record.transaction()
      @set 'raceHorse', deepCopy
```

## Transaction's Deep Copy

A transaction is actually an instance of the original model. It differs in 2 ways:

- It isn't added to the `loaded` set (aka "the memory map")
- It has `Batman.Transaction` mixed in, which defines some new functions and overrides `Model::save`

`Model::transaction` peforms a deep copy of a `Batman.Model` by
 iterating over the model's `attributes` hash. The `attributes` hash is where encoded properties are stored (and other properties, unless you define an accessor that says otherwise).

Batman.js copies the attributes hash into the transaction by handling each value:

- If the value is a `Batman.Model`, it's also copied with `Model::transaction`
- If the value is a `Batman.AssociationSet`, it's cloned into a `Batman.TransactionAssociationSet` and its members are copied with `Model::transaction`
- Otherwise, the value is set into the transaction's attributes.

Under the hood, batman.js tracks which objects it has already cloned. That way, it doesn't get thrown into an infinite loop.

If a mutable object is copied from the original to the transaction, batman.js issues a warning. This is because it can't isolate changes. The transaction and the original are both refering to the _same object_, so changes to one will also affect the other. Mutable objects include:

- Dates (although mutating dates is such a pain in JS, I doubt this will cause a problem)
- Arrays
- Batman.Set, Batman.Hash, etc
- any JavaScript object

## Saving a Transaction

To save a transaction, call `save` on it. This will:

- validate the transaction (with client-side validations)
- apply changes to the original model
- save the transaction (ie, the storage operation will be performed with the transaction, not the original)
- pass the original to the `save` callback

This means a transaction behaves just like a normal model. You can save it like this:

```coffeescript
  saveRaceHorse: (raceHorse) ->
    raceHorse.isTransaction # => true, just checking
    raceHorse.save (err, record) ->
      if !err
        Batman.redirect("/race_horses")
```

__Note:__ at time of writing, transaction __does not account for server-side validations__. There is an open issue for this [on github](https://github.com/batmanjs/batman/issues/1049).

## Forgetting a Transaction

If you don't want changes on transaction to be applied, just leave it alone.

- It's not in the `loaded` set, so it won't intefere with your app's other data.
- The original record has no references to it.
- It's still set on your controller (probably), but it will get overrided next time your user edits something.

Once it's released from the controller, it will probably just be garbage-collected when the browser gets a chance.

## Applying Changes without Saving

Transactions have an `applyChanges` function that updates the original record without performing any storage operations.

```coffeescript
transaction.applyChanges()
```

You might use this if your save operation is really complicated and you need to control it by hand.





