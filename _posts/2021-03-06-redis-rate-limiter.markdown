---
layout: post
title: "Lessons learned implementing a sharded, replicated rate limiter with Redis"
date: 2021-03-06 00:00
categories:
  - Ruby
  - Redis
  - APIs
  - Rate Limiting
---

About a year ago, we migrated an old rate limiter to Redis. In the end, it worked out great, but we learned some lessons along the way.

<!-- more -->

### The Problem

We had an old rate limiter that was simple enough:

- For every request, determine a "key" for the current rate limit
- In Memcached, increment the value of that key, setting it to `1` if there wasn't any current value
- Also, if there wasn't already one, set a "reset at" value in Memcached, using a related key (eg, `"#{key}:reset_at"`)
- When incrementing, if the "reset at" value is in the past, ignore the existing value and set a new "reset at"
- At the beginning of each request, if the value for the key is above the limit, and "reset at" is in the future, then reject the request

(There might have been more nuance to it, but that's the main idea.)

However, this limiter had two problems:

- Our Memcached architecture was due to change. Since it was _mostly_ used as a caching layer, we were going to switch from a single, shared Memcached to one Memcached per datacenter. Although that'd work fine for application caching, it would cause our rate limiter to behave very strangely if client requests were routed to different data centers.
- Memcached "persistence" wasn't working for us. The Memcached backend was shared by the rate limiter and other application caches which meant that, when it filled up, it would sometimes evict rate limiter data, even when it was still active. (As a result, clients would get "fresh" rate limit windows when they shouldn't. Sometimes, only _one_ key would be evicted -- they'd keep the same "used" value, but get new, future, "reset at" values!)

### The Proposed Solution

After some discussion, we decided on a new design for the rate limiter:

- Use Redis, since it has a more appropriate persistence system and simple sharding and replication setups
- Shard inside the application: the app would pick, for each key, which Redis cluster to read and write from
- To mitigate the CPU-bound nature of Redis, put a single primary (for writes) and several replicas (for reads) in each cluster
- Instead of writing "reset at" in the database, use Redis expiration to make values disappear when they no longer apply
- Implement the storage logic in Lua, to guarantee atomicity of operations (this was an improvement over the previous design)

One option we _considered_ but decided against was using our MySQL-backed KV store ([`GitHub::KV`](https://github.com/github/github-ds#githubkv)) for storage. We didn't want to add traffic to already-busy MySQL primaries: usually, we use replicas for `GET` requests, but rate limit updates would require write access to a primary. By choosing a different storage backend, we could avoid the additional (and substantial) write traffic to MySQL.

Another advantage to using Redis is that it's a well-traveled path. We could take inspiration from two excellent existing resources:

- Redis's own documentation, which includes some [rate limiter patterns](https://redis.io/commands/incr#pattern-rate-limiter)
- Stripe's technical blog post, ["Scaling your API with Rate Limiters"](https://stripe.com/blog/rate-limiters), which includes a Ruby and Redis [example implementation](https://gist.github.com/ptarjan/e38f45f2dfe601419ca3af937fff574d)

### The Release

To roll out this change, we isolated the current persistence logic into a `MemcachedBackend` class, and built a new `RedisBackend` class for the rate limiter. We used a feature flag to gate access to the new backend. This allowed us to gradually increase the percentage of clients using the new backend. We could change the percentage _without_ a deploy, which meant, if something went wrong, we could quickly switch back to the old implementation.

The release went smoothly, and when it was done, we removed the feature flag and the `MemcachedBackend` class, and integrated `RedisBackend` directly with the `Throttler` class that delegated to it.

Then, the bug reports started flowing in....

### The Bugs

A lot of integrators watch their rate limit usage very closely. We got two really interesting bug reports in the weeks following our release:

1. Some clients observed that their `Retry-After` header value "wobbled" -- it might show `2020-01-01 10:00:00` for one request, but `2020-01-01 10:00:01` on another request (with one second difference).
2. Some clients had their requests _rejected_ for being over the limit, but the response headers said `X-RateLimit-Remaining: 5000`. That doesn't make sense: if they've got a full rate limit window ahead of them, why was the request rejected?

How odd!


### Fix 1: Manage "reset at" in application code

I was optimistic about using Redis's built-in time-to-live (TTL) to implement our "reset at" feature. But it turns out, my implementation caused the "wobble" described above.

The Lua script returned the TTL of the client's rate limit value, and then in Ruby, it was added to `Time.now.to_i` to get a timestamp for the `Retry-After` header. The problem was, time _passes_ between the call to `TTL` (in Redis) and `Time.now.to_i` (in Ruby). Depending exactly how much time, and where it fell on the clock's second boundary, the resulting timestamp might be different. For example, consider the following calls:

Redis call begins | latency | `TTL` (Redis) | latency |`Time.now` returns | sum of `TTL` and `Time.now`
----|----|-----|----|----|---
`10:00:04.2` | `0.1` | `5` | `0.1` | `10:00:05.4` | `10:00:10.1`
(then, a half-second later) |  |  | | |
`10:00:05.9` | `0.05` | `5` | `0.1` | `10:00:06.05` | `10:00:11.05`

In that case, since the second boundary happened _between_ the call to `TTL` and `Time.now` resulting timestamp was on second _bigger_ than the previous ones.

We could have tried increasing the precision of this operation (eg, Redis `PTTL`), but there would _still_ have been some wobble, even if it was greatly reduced.

Another possibility was to calculate the time using _only_ Redis, instead of mixing Ruby and Redis calls to create it. Redis's `TIME` command could have been used as the source of truth. (Old Redis versions didn't allow `TIME` in Lua scripts, but Redis 5+ does.) I avoided this design because it would have been harder to test: by using Ruby's time as the source of truth, I could time-travel in my tests with `Timecop`, asserting that expired keys were handled correctly without actually _waiting_ for Redis's calls to the system clock to return true, future times. (I still had to wait on Redis to test the `EXPIRE`-based database cleanup, but since `expires_at` came from Ruby-land, I could inject very short expiration windows to simplify testing.)

Instead, we decided to _persist_ the "reset at" time from Ruby in the database. That way, we could be sure it wouldn't wobble. (Wobbling was an effect of the _calculation_ -- but reading from the database would guarantee a stable value.) Instead of reading `TTL` from Redis, we stored another value in the database (effectively doubling our storage footprint, but OK).

We still applied a TTL to rate limit keys, but they were set for one second _after_ the "reset at" time. That way, we could use Redis's own semantics to clean up "dead" rate limit windows.

### Fix 2: Account for expiration in replicas

We found another problem that worked like this:

1. At the beginning of the request, check the client's current rate limit value. If it's over the maximum allowed limit, prepare a rejection response.
2. Before delivering the response, increment the current rate limit value, and use the response to populate the `X-RateLimit-...` headers.

Weirdly, many clients reported _rejections_ that included `X-RateLimit-Remaining: 5000` headers. What's going on!?

Well, it turned out that Step 1 above hit a Redis _replica_, since it was a read operation. The read operation returned information about the client's previous window, and the application prepared a rejection response.

Then, Step 2 would hit a Redis _primary_. During that database call, Redis would expire the previous window data and return data for a _fresh_ rate limit. This is a known limitation of Redis: replicas don't expire data until they receive instructions to do so from their primaries, and primaries don't expire keys until they're accessed ([GitHub issue](https://github.com/redis/redis/issues/187)). (In fact, primaries _do_ randomly sample keys from time to time, expiring them as appropriate, see ["How Redis Expires Keys"](https://redis.io/commands/expire#how-redis-expires-keys).)

Addressing this issue required two things:

- Basically, the same fix as above: instead of relying on Redis's TTL to expire old rate limit windows, we needed to manage that feature in the application. (The application should be prepared to read stale data from replicas, then ignore it.)
- Even after fixing that, a better design was required: in the case of rate-limited requests, we should avoid a second call to the database. The client's window might expire between the two calls, resulting in the kind of inconsistent response described above. This fix required improving the Ruby code that prepared responses so that the response from Step 1 above was used to populate `X-RateLimit-...` headers.

### The Final Scripts

Here are the Lua scripts we ended up with for implementing this pattern:

```lua
-- RATE_SCRIPT:
--   count a request for a client
--   and return the current state for the client
-- rename the inputs for clarity below
local rate_limit_key = KEYS[1]
local increment_amount = tonumber(ARGV[1])
local next_expires_at = tonumber(ARGV[2])
local current_time = tonumber(ARGV[3])
local expires_at_key = rate_limit_key .. ":exp"
local expires_at = tonumber(redis.call("get", expires_at_key))
if not expires_at or expires_at < current_time then
  -- this is either a brand new window,
  -- or this window has closed, but redis hasn't cleaned up the key yet
  -- (redis will clean it up in one more second)
  -- initialize a new rate limit window
  redis.call("set", rate_limit_key, 0)
  redis.call("set", expires_at_key, next_expires_at)
  -- tell Redis to clean this up _one second after_ the expires-at time.
  -- that way, clock differences between Ruby and Redis won't cause data to disappear.
  -- (Redis will only clean up these keys "long after" the window has passed)
  redis.call("expireat", rate_limit_key, next_expires_at + 1)
  redis.call("expireat", expires_at_key, next_expires_at + 1)
  -- since the database was updated, return the new value
  expires_at = next_expires_at
end
-- Now that the window is either known to already exist _or_ be freshly initialized,
-- increment the counter (`incrby` returns a number)
local current = redis.call("incrby", rate_limit_key, increment_amount)
return { current, expires_at }
```

```lua
-- CHECK_SCRIPT:
--   Getting both the value and the expiration
--   of key as needed by our algorithm needs to be ran
--   in an atomic way, hence the script.

-- rename the inputs for clarity below
local rate_limit_key = KEYS[1]
local expires_at_key = rate_limit_key .. ":exp"
local current_time = tonumber(ARGV[1])
local tries = tonumber(redis.call("get", rate_limit_key))
local expires_at = nil -- maybe overridden below
if not tries then
  -- this client hasn't initialized a window yet
  -- let this fall through to returning {nil, nil},
  -- where the application will provide defaults
else
  -- we found a number of tries, now check
  -- if this window is actually expired
  expires_at = tonumber(redis.call("get", expires_at_key))
  if not expires_at or expires_at < current_time then
    -- this window hasn't been cleaned up by Redis yet, but it has closed.
    -- (maybe it was _partly_ cleaned up, if we found `tries` but not `expires_at`)
    -- ignore the data in the database; return a fresh window instead
    tries = nil
    expires_at = nil
  end
end
-- Maybe {nil, nil} if the window is brand new (or expired)
return { tries, expires_at }
```

### Conclusion

After working out the issues described above, the limiter has worked great. There's still one shortcoming we're considering: the current implementation doesn't increment the "current" rate limit value until after the request is _finished_. We do this because we don't charge clients for `304 Not Modified` responses (this can happen when the client provides an E-Tag). A better implementation might increment the value when the request _starts_, then refunds the client if the response is `304`. That would prevent some edge cases where a client can exceed its limit when the final allowed request is still being processed.
