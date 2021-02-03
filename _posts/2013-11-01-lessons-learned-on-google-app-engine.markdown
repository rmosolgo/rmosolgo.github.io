---
layout: post
title: "Lessons Learned on Google App Engine"
date: 2013-11-01 13:00
categories:
  - Google App Engine
  - Python
---


My involvement with a [Google App Engine](https://cloud.google.com/products/app-engine)-based project is winding down, so I'll share what I've learned.

<!-- more -->

# Building for App Engine is tough

If you're thinking about starting a project on GAE, think about it carefully. I had a hard time with it for several reasons, but my first mistake was thinking, "Oh, this will be a way to get an app going quickly and cheaply without all that sysadmin trouble." This is not the case for a few reason:

- mission-critical features depend on _GAE-specific_ APIs which are often poorly documented and not very googlable.
- you'll be learning a [new database (NDB)](https://developers.google.com/appengine/docs/python/ndb/), a [new memcache server](https://developers.google.com/appengine/docs/python/memcache/) and a [new task queuer](https://developers.google.com/appengine/docs/python/taskqueue/), among others.
- GAE support for Django is so-so. You'll probably have to learn a new framework. Make sure to use [WebApp2](http://webapp-improved.appspot.com/) if you're trying to set up a lightweight application.

If you want quick, cheap prototyping, consider [Heroku](http://heroku.com/) instead. You'll have access to all the standard components of the modern web stack (rather than GAE-specific ones) and Heroku supports [many languages](https://devcenter.heroku.com/categories/language-support).

# Development server != Production server

The development environment differs from the production environment in several ways. The ones I found are:

- No memory limit on the development server
- No timeouts on the development server
- Asynchronous features don't work on the development server (futures don't resolve until they're explicitly waited for)


So, something that works in development may not work in production! (And apparently the same is [true for the test stubs](https://developers.google.com/appengine/docs/python/tools/localunittesting#Python_Introducing_the_Python_testing_utilities).)


# You might have to pay for your staging environment

Unless you look into [AppScale](http://www.appscale.com/) (I didn't), you'll need another GAE instance for your staging server. Unless you pay, you won't be able to test rigorous features of the app.

# The Datastore has some drawbacks

1. You pay to use it. If your application will be database-intensive (reads, writes and/or deletes), it's gonna cost you. It adds up -- make sure to set a nice low cap on your budget.

1. The pricing is non-intuitive at first. You're charged for each value in the stored entity, its key, and each value in any indexes that entity has.

1. Indexes are expensive to maintain (because of the point above). Remove ones you don't desperately need!

1. It's an unfamiliar, low-level API. To me, anyways -- it's no ActiveRecord.

# Don't cache if you're running big queries

Make sure to pass the [`use_cache=false` context option](https://developers.google.com/appengine/docs/python/ndb/functions#context_options) or else it will kill your instance for memory overload! For example:

```python
  some_big_query = AppModel.query(AppModel.some_property == value)
  lots_of_items = some_big_query.fetch(use_cache=False) # otherwise it will cache entities in memory
```

Also, consider the [`keys_only` option](https://developers.google.com/appengine/docs/python/ndb/queryclass#kwdargs_options) if you're performing actions that could work with just the keys. [Deleting](https://developers.google.com/appengine/docs/python/ndb/keyclass#Key_delete), for example:

```python
  unwanted_entity_keys = AppModel.query(AppModel.some_property == value).fetch(keys_only=True)
  ndb.delete_multi(unwanted_entity_keys)
```

# Use pages to run big queries

Datastore operations are limited to 60 seconds, even on the backend. If you're iterating over lots of entities and/or performing time-consuming tasks on each one, you'll want to use the [`Query#fetch_page`](https://developers.google.com/appengine/docs/python/ndb/queryclass#Query_fetch_page) method. For example, creating a CSV based on a query:

```python
class AppModel(ndb.model):
  CSV_HEADER = "heading,heading,heading\n"
  @class_method
  def csv_by_dates(cls, start_date, end_date):
    PAGE_SIZE = 500 # I'll process 500 at a time
    csv = cls.CSV_HEADER

    # here's a big query:
    query = cls.query(cls.date > start_date, cls.date < end_date).order(cls.date)
    # use the fetch_page method:
    results, cursor, more = query.fetch_page(PAGE_SIZE, use_cache=False)

    while len(results) > 0:
      for d in results:
        csv += d.to_csv() # load up the CSV
      # pass `cursor` to the next query:
      results, cursor, more = query.fetch_page(PAGE_SIZE, start_cursor=cursor, use_cache=False)

    return csv

  # def to_csv(self): ...
```



_Ok, that's all for now!_
