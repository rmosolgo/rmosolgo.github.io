---
layout: post
title: "Enable filesystem writes in GAE dev_appserver"
date: 2013-08-05 20:43
categories:
  - Google App Engine
  - Python
---

[Google App Engine](https://cloud.google.com/products/)'s `dev_appserver` prevents filesystem writes because GAE has no filesystem -- but sometimes you want to write anyways!

<!-- more -->

I was working over a big set of data from the [Google App Engine High-Replication Datastore](https://developers.google.com/appengine/docs/python/storage#App_Engine_Datastore) and I found that, somewhere in my loop, memory was slipping away...

So I got [objgraph](http://mg.pov.lt/objgraph/), which creates a graphic based on your memory usage. But I had a problem: Google App Engine doesn't have a filesystem, so the development server prevents you from writing to files. `objgraph` couldn't create my graphic!

Luckily, the fix was simple: I found the line that threw the error and commented it out. _(The file is `[your_appengine_root]\google\appengine\tools\devappserver2\python\stubs.py`)_

```python
  # Starting on line 242:
  def __init__(self, filename, mode='r', bufsize=-1, **kwargs):
    """Initializer. See file built-in documentation."""
    # if mode not in FakeFile.ALLOWED_MODES:
    #   raise IOError(errno.EROFS, 'Read-only file system', filename)

    if not FakeFile.is_file_accessible(filename):
      raise IOError(errno.EACCES, 'file not accessible', filename)

    super(FakeFile, self).__init__(filename, mode, bufsize, **kwargs)
```

By the way, it didn't turn out to be a memory leak. It was [GAE's NDB caching](https://developers.google.com/appengine/docs/python/ndb/cache) in action -- I just disabled it by:
```python
for d_key in query.iter(keys_only=true):
  d = d_key.get(use_cache=False, use_memcache=False)
  # ...
  d.put(use_cache=False, use_memcache=False)
```

Then I was all clear!
