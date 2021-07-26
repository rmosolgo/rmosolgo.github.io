---
layout: post
title: "What makes a good ID?"
date: 2021-07-26 00:00
categories:
  - Software
  - GraphQL
---

At my job, we're working on [revamping the global ID system](https://github.blog/2021-02-10-new-global-id-format-coming-to-graphql/) we use for GraphQL. Here are a few lessons I've learned through my participation in the project.

<!-- more -->

In short, we've been considering, "what makes a good global identifier?" I've found a few takeaways. (Our sibling team pointed out some similiar ideas when [reworking personal access tokens](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/).)

## Human-friendliness

When developing and debugging applications, people will have to work wit these global IDs. We can make things easier by following a few rules:

- __Include a clue__ in the ID for the kind of object that the ID references. (Slack and Stripe do this.) For example, we included a `{capital_letters}_` prefix in each new ID to give the reader a clue as to what _kind_ of ID they're seeing. `U_abcdef` is a `User`, `PR_ghijk` is a `PullRequest`, and so on.
- __Keep it short__ because, the longer the opaque string, the more our eyes glaze over and the more likely we are to misjudge equivalence between them. We accomplished this by messagepacking the "contents" of the ID, as described below. (Previously, we base64 encoded _strings_, but with messagepack, we generate a binary payload of IDs, then base64 encode _that_, which results in a shorter opaque string.)
- __Be URL-safe__ so that people can drop IDs in query params without  worrying about encoding. This makes it easier to debug sometimes. For us, that means using `Base64.urlsafe_encode64` from the Ruby standard library instead of `Base64.encode64`.
- __Be double-clickable__: interestingly `underscores_double_click_fine` but `dashes-dont-double-click-nicely`. (I suppose this varies by browser, though).

## Computer-friendliness

One of the motivators for our re-work was to include some platform-related routing data _inside_ these global IDs. In a future architecture, we'd like to host different user and repository data in different data centers, so including more routing information in IDs could support more efficient request routing. Some points to support that:

- __Include enough data__ to make sure the global IDs can fetch their objects effectively. Plain ol' primary keys from the database won't work here, because if the system wants to look up `500`, it doesn't know what table to search for that ID. A slightly more sophisticated approach would embed the table name in the ID, too (eg, `users:500`), and that would be enough information to find an object in the database.

    Interestingly, if you're using a backend which doesn't have namespacing like SQL tables, then _just_ an identifier might be fine. For us, we have several kinds of backends (MySQL, git, external applications), so although the _default_ behavior is SQL-related, it supports overrides for other backends.

    Beyond that, you can consider _how_ the system runs. Maybe you could include some other identifying information in the ID to speed up authentication (eg, owner ID) or data retreival (eg, sharding key).

- __Ensure compatibility and stability__ over time. We have configuration code in the GraphQL-Ruby object type classes that generates IDs for that kind of object. From those, we generate an artifact (a YAML file) the specifies the structure of each kind of ID. This artifact helps us maintain the system as it grows:

    - There's a script for regenerating the artifact. It checks the new structure against the old structure and raises an error if it detects any breaking changes. The errors describe _why_ the change is breaking and how the developer might modify the new structure to avoid this breaking change. This way, we can avoid changes that break existing ID patterns. (There's an override to _allow_ breaking changes, too, because that's life.)
    - There's a test for ensuring that the artifact always matches the state of the source code. That way, we can be sure that the artifact _always_ reflects the source code accurately.

    I figure the artifact itself might come in handy down the line, too. When we need external systems (routers, etc) to parse incoming global IDs for routing data, they can use that artifact as a starting point to generate parsing code.

## Roll-out

Fine, designing a better ID system is fun enough. But what about _releasing_ a new system, when old IDs are meant to be _stable_? How can we migrate the API without breaking basic API contracts? A lot of this work remains to be done, but here's the basic idea:

- Release __new IDs for new objects__ first. Basically, we check the `created_at` on objects as we generate IDs, and if they're after a certain point (configured in Ruby and printed in the artifact described above), then we use the new ID routine. For older objects, we keep generating the old IDs.
- Always __accept both kinds__ of IDs for lookups. Return a warning if a legacy ID is used to fetch a newly-created object. Then ...
- Accept __per-request headers__ for returning _all new_ or _all old_ IDs. This provides an approach for migrating old IDs to new IDs. Clients could send old IDs from an existing database, but include the `X-New-IDs: true` header to refetch those objects, then update the IDs in the database.
- __Eventually stop generating legacy IDs__, even though they're still valid input. This will cause some weird breakages for anyone who hasn't updated, but a lot of functionality will still work.
- __Eventually stop accepting legacy IDs__, raising a distinctive error when one is received, including the new ID for an object. This will break all functionality for apps with old IDs in their database, but still provide a migration path.
- __Finally, delete legacy ID-related code__. At that point, legacy IDs will be gibberish to the system, and there will be no way to migrate old IDs anymore.

In theory, a workflow like that will provide a gradual migration path for integrators to update any IDs that are persisted in their system. If it turns out that we _need_ it, we could even create a dedicated API of some kind for translating IDs from old to new. To make the experience really nice, we could relax the rate limiting constraints around that API to encourage people to make good use of it.

## Other Approaches

Even if the path described above is the one we take, there are _technically_ some alternatives:

- A __lookup table__ for mapping new IDs to old IDs (and vice-versa). We could maintain this to support legacy IDs even after we delete the Ruby code for it. This _could work_ but it comes with a lot of complexity about replicating that table in all datacenters and making sure to always check it.
- __Persisting IDs__ on the objects that have them. Honestly, I'd love this approach. In theory, objects should always have the same ID. Why not just write it to a column on that object's table in the database (or other persistence mechanism)? Then you could delegate lookups to the backend and you'd only have to generate an ID _once_ for the object.

  I think this approach _would_ work fine, but it's daunting to think of the scale of the migration required for our data, especially considering the complexity required for non-SQL backends like `git` and external services. Even if we were able to do it for SQL-backed data, then we'd have to mix approaches for those other backends. Yikes!

  Additionally, those persisted IDs would have to contain the routing-related info described above, as well as their table name. That way, when GraphQL (or another system) received a global ID, it would know where to look to find that object.

  I _think_ this is how [Facebook's TAO backend](https://www.usenix.org/conference/atc13/technical-sessions/presentation/bronson) works. There's only one database table (`objects`), and each object has an ID that includes its sharding key. So, when the backend looks up an ID, it can quickly determine which shard the ID belongs to, and then check the `objects` table for it. That sounds really slick! Personally, I can see where GraphQL _came from_ when I think about the TAO backend.

## Conclusion

A lot of this work remains to be done, and from what we've done so far, I'd guess there are still a few internal kinks to work out. But the plan seems good enough from here, and I'm looking forward to improving the system for humans and computers alike!
