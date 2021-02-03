---
layout: post
title: "Serving static files in WebApp2 reponses"
date: 2013-08-04 19:22
categories:
  - Google App Engine
  - Python
  - WebApp2
  - HTML
---

On [Google App Engine](https://cloud.google.com/products/), I had to display the user-submitted image, if there was one, else display a default image.

<!-- more -->
The given object could only have one image, so I was using the [NDB BlobProperty](https://developers.google.com/appengine/docs/python/ndb/properties):

```python
class Sensor(ndb.Model):
  image = ndb.BlobProperty()
```

I put the default image in my application root (alongside `app.yaml`):

```yaml
app_root:
  request_handlers:
    - __init__.py
    - handlers.py
  - app.yaml
  - default_sensor.jpg
  ...
```

In my request handler, I checked for the presence of an image, and gave the default image if there wasn't one there:

```python
# responds to "/sensors/(\w+)/image"
class SensorImage(webapp2.RequestHandler):
  DEFAULT_IMAGE = 'default_sensor.jpg'
  def get(self, hex):
    r = self.response
    r.headers['Content-Type'] = "image/jpg"
    this_sensor = Sensor.find_by_hex(hex)

    if (not this_sensor) or (not this_sensor.image):

      image = open(SensorImage.DEFAULT_IMAGE, 'rb')
      r.body_file.write( image.read() )
      image.close()

    else:
      r.body_file.write( this_sensor.image )

```

That way, I had one URL that didn't change whether a user uploaded an image or not.
